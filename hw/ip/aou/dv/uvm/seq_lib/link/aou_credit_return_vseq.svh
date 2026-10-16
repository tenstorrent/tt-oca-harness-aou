// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Credit advertisement and return corners (ports of aou_credit_encoding_test
// and aou_msgcredit_encoding_test, extended). Every loop is one activation
// epoch with its own remote-die credit setup, chosen before activation:
//   - initial advertisement per class at an encoded value (Table 17), or a
//     non-encodable depth that needs several grants;
//   - return through CrdtGrant only, header MsgCredit only, both mixed in a
//     flit, or DUT-like (initial grant, then header);
//   - return immediately, only at RX dequeue, delayed, withheld until a
//     release (in bursts while traffic runs, so the DUT sees its credit
//     oscillate);
//   - optionally over-grants beyond the buffer, which the DUT's counter must
//     absorb by saturating (§6.4).
// Traffic runs both ways; the model checks that the DUT never sends without
// credit (AOU-R16) and that its own decoding of the DUT's grants and
// MsgCredit lets every transaction finish.
// Knobs: +loops +method=dut|hdr|grant|mixed|rand +ret=imm|consume|delayed|
// withheld|rand +depth=<granules, all classes> +overgrant=0|1 +T1_TXN.
class aou_credit_return_vseq extends aou_link_base_vseq;
  `uvm_object_utils(aou_credit_return_vseq)

  protected bit osc_on;

  function new(string name = "aou_credit_return_vseq");
    super.new(name);
  endfunction

  task body();
    int unsigned loops = arg_range("loops", 2, 4);
    link_up();
    for (int unsigned i = 0; i < loops; i++) begin
      string ret = arg_str("ret", "rand");
      bit og = 1'(arg_int("overgrant", $urandom_range(3) == 0));
      // Advertising beyond the buffer is legal (the counter saturates, §6.4)
      // but AOU_FDI_CHECKER reports it against its own capacity.
      if (og) expect_event("AOU-R21", 0, 0);
      setup_epoch(arg_str("method", "rand"), ret);
      sw_activate();
      osc_on = 1'b1;
      fork
        if (cfg.l3_cfg.ret_policy[AOU_CC_WDATA] == AOU_RET_WITHHELD) oscillate();
        if (og) overgrant();
        begin
          traffic(AOU_T1_BOTH_DIRS, num_txns, aou_t1_traffic_cfg::named("short"));
          osc_on = 1'b0;
        end
      join
      env.l3.model.release_withheld();
      drain();
      sw_deactivate();
    end
  endtask

  // Smallest workable depth per class. The model frees data credit when a
  // whole burst is handed on, so a data class must hold the longest burst
  // of the "short" profile: 4 beats at the widest data width in the build
  // (WriteData512 = 60, ReadData512 = 56, WriteData1024 = 120 granules);
  // requests and responses need one message (3 and 1).
  function int unsigned min_depth(aou_cred_class_e c);
    int unsigned w = cfg.remote_bytes;
    bit [1:0] dl;
    foreach (cfg.rp_bytes[r]) begin
      if (cfg.rp_bytes[r] > w) w = cfg.rp_bytes[r];
      if (cfg.remote_bytes_of(r) > w) w = cfg.remote_bytes_of(r);
    end
    dl = (w > 64) ? AOU_DL_1024 : (w > 32) ? AOU_DL_512 : AOU_DL_256;
    case (c)
      AOU_CC_WDATA: return 4 * aou_data_len(AOU_MT_WDATA, dl);
      AOU_CC_RDATA: return 4 * aou_data_len(AOU_MT_RDATA, dl);
      AOU_CC_WRESP: return 1;
      default:      return 3;
    endcase
  endfunction

  function int unsigned pick_depth(aou_cred_class_e c);
    int unsigned legal[$];
    int unsigned d = arg_int("depth", 0);
    if (d != 0) return (d < min_depth(c)) ? min_depth(c) : d;
    for (int unsigned e = 0; e < ((c == AOU_CC_WRESP) ? 4 : 8); e++)
      if (aou_cred_dec3(3'(e)) >= min_depth(c)) legal.push_back(aou_cred_dec3(3'(e)));
    // One in four epochs: a depth no single field encodes.
    if ($urandom_range(3) == 0) return min_depth(c) + $urandom_range(200);
    return legal[$urandom_range(legal.size() - 1)];
  endfunction

  function aou_cred_ret_e pick_ret(string ret);
    case (ret)
      "imm":      return AOU_RET_IMMEDIATE;
      "consume":  return AOU_RET_ON_CONSUME;
      "delayed":  return AOU_RET_DELAYED;
      "withheld": return AOU_RET_WITHHELD;
      "rand":     return aou_cred_ret_e'($urandom_range(3));
      default:    `uvm_fatal(get_type_name(), {"unknown return policy ", ret})
    endcase
    return AOU_RET_ON_CONSUME;
  endfunction

  // The remote die's credit setup for the next activation (it is in
  // DISABLED, so the new depths are what it advertises).
  function void setup_epoch(string method, string ret);
    aou_l3_cfg c = cfg.l3_cfg;
    case (method)
      "dut":   c.pol.cred_method = AOU_CRM_DUT_LIKE;
      "hdr":   c.pol.cred_method = AOU_CRM_HDR;
      "grant": c.pol.cred_method = AOU_CRM_GRANT;
      "mixed": c.pol.cred_method = AOU_CRM_MIXED;
      "rand":  c.pol.cred_method = aou_cred_method_e'($urandom_range(3));
      default: `uvm_fatal(get_type_name(), {"unknown credit method ", method})
    endcase
    c.ret_delay = $urandom_range(40, 1);
    for (int k = 0; k < AOU_CC_NUM; k++) begin
      aou_cred_class_e cc = aou_cred_class_e'(k);
      c.rx_depth[k] = pick_depth(cc);
      c.ret_policy[k] = pick_ret(ret);
    end
    // Withheld credit comes back only through oscillate(), on WDATA.
    foreach (c.ret_policy[k])
      if (c.ret_policy[k] == AOU_RET_WITHHELD && k != AOU_CC_WDATA)
        c.ret_policy[k] = AOU_RET_DELAYED;
    env.l3.model.crd.reset_link();
    `uvm_info(get_type_name(), $sformatf("credit epoch: method=%s depth=%p ret=%p delay=%0d",
                                         c.pol.cred_method.name(), c.rx_depth, c.ret_policy,
                                         c.ret_delay), UVM_LOW)
  endfunction

  // Withholds and releases the WDATA returns in bursts while traffic runs.
  task oscillate();
    while (osc_on) begin
      wait_cycles($urandom_range(600, 50));
      env.l3.model.release_withheld();
    end
  endtask

  // Grants up to 8 x 128 extra credits on random classes mid-traffic.
  task overgrant();
    int unsigned k = $urandom_range(8, 1);
    for (int unsigned i = 0; i < k; i++) begin
      aou_l3_overgrant_seq s = aou_l3_overgrant_seq::type_id::create("s");
      wait_cycles($urandom_range(300, 10));
      s.cls = aou_cred_class_e'($urandom_range(AOU_CC_NUM - 1));
      s.n = (s.cls == AOU_CC_WRESP) ? 8 : 128;
      s.rp = 2'($urandom_range(cfg.n_rp - 1));
      s.start(p_sequencer.l3_sqr);
    end
  endtask
endclass

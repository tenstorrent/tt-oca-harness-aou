// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Credit accounting for both directions, per wire RP and credit class
// (spec chapter 6, MAS 3.9). One credit is one granule.
//   TX: credits the DUT granted us. Added from MsgCredit and CrdtGrant
//       (saturating at tx_cred_max), consumed in full at a message's start.
//   RX: credits we grant the DUT. outstanding = advertised and unused;
//       occupancy = received granules still in the modelled buffer;
//       pending = freed granules not yet advertised again. Freeing follows
//       the class's return policy; a DUT message needing more than
//       outstanding is an overflow (AOU-R16).
class aou_credit_mgr extends uvm_object;
  `uvm_object_utils(aou_credit_mgr)

  aou_l3_cfg   cfg;

  int unsigned tx_cred[AOU_RP_MAX][AOU_CC_NUM];
  int unsigned tx_granted[AOU_RP_MAX][AOU_CC_NUM];
  int unsigned tx_consumed[AOU_RP_MAX][AOU_CC_NUM];
  // Highest credit held since entering DISABLED: what the DUT advertised.
  int unsigned tx_full[AOU_RP_MAX][AOU_CC_NUM];
  int unsigned tx_saturations;
  int unsigned tx_underflows;

  int unsigned rx_outstanding[AOU_RP_MAX][AOU_CC_NUM];
  int unsigned rx_occupancy[AOU_RP_MAX][AOU_CC_NUM];
  int unsigned rx_pending[AOU_RP_MAX][AOU_CC_NUM];
  int unsigned rx_withheld[AOU_RP_MAX][AOU_CC_NUM];
  int unsigned rx_returned[AOU_RP_MAX][AOU_CC_NUM];
  int unsigned rx_overflows;
  // Coverage of the DUT side: exhausted when the DUT used up what we granted,
  // starved when we granted from that state (at tick starved_tick).
  bit          rx_exhausted[AOU_RP_MAX][AOU_CC_NUM];
  bit          rx_starved[AOU_RP_MAX][AOU_CC_NUM];
  int unsigned rx_starved_tick[AOU_RP_MAX][AOU_CC_NUM];
  // Delayed returns: due tick, RP, class, amount.
  int unsigned dly_due[$];
  int unsigned dly_rp[$];
  int unsigned dly_cc[$];
  int unsigned dly_n[$];
  int unsigned tick_now;
  int unsigned hdr_rr;

  function new(string name = "aou_credit_mgr");
    super.new(name);
  endfunction

  // Entry to DISABLED (8.2): credits from the partner are discarded and the
  // credits to advertise return to the free space of the modelled buffer.
  function void reset_link();
    for (int unsigned r = 0; r < AOU_RP_MAX; r++) begin
      for (int unsigned c = 0; c < AOU_CC_NUM; c++) begin
        int unsigned d = (r < cfg.rp_count && !cfg.rx_starve[r][c]) ? cfg.rx_depth[c] : 0;
        tx_cred[r][c] = 0;
        tx_full[r][c] = 0;
        rx_outstanding[r][c] = 0;
        rx_withheld[r][c] = 0;
        rx_exhausted[r][c] = 1'b0;
        rx_starved[r][c] = 1'b0;
        rx_pending[r][c] = (d > rx_occupancy[r][c]) ? d - rx_occupancy[r][c] : 0;
      end
    end
    dly_due.delete();
    dly_rp.delete();
    dly_cc.delete();
    dly_n.delete();
    hdr_rr = 0;
  endfunction

  // ---- TX ------------------------------------------------------------
  // Returns 1 when the grant saturated the counter.
  function bit tx_grant(int unsigned r, aou_cred_class_e c, int unsigned n);
    tx_granted[r][c] += n;
    if (tx_cred[r][c] + n > cfg.tx_cred_max) begin
      tx_cred[r][c] = cfg.tx_cred_max;
      tx_saturations++;
      if (tx_cred[r][c] > tx_full[r][c]) tx_full[r][c] = tx_cred[r][c];
      return 1'b1;
    end
    tx_cred[r][c] += n;
    if (tx_cred[r][c] > tx_full[r][c]) tx_full[r][c] = tx_cred[r][c];
    return 1'b0;
  endfunction

  // Classes still short of what the DUT advertised (AOU-R31), listed in why.
  function int unsigned tx_short(output string why);
    int unsigned n = 0;
    why = "";
    for (int unsigned r = 0; r < cfg.rp_count; r++) begin
      for (int unsigned c = 0; c < AOU_CC_NUM; c++) begin
        if (tx_cred[r][c] < tx_full[r][c]) begin
          n++;
          why = {why, $sformatf(" RP%0d %s %0d/%0d", r, aou_cc_name(aou_cred_class_e'(c)),
                                tx_cred[r][c], tx_full[r][c])};
        end
      end
    end
    return n;
  endfunction

  function bit tx_can(int unsigned r, aou_cred_class_e c, int unsigned n);
    return tx_cred[r][c] >= n;
  endfunction

  // Consumption without enough credit only happens under injection; the
  // counter floors at zero and the shortfall is counted.
  function void tx_consume(int unsigned r, aou_cred_class_e c, int unsigned n);
    tx_consumed[r][c] += n;
    if (tx_cred[r][c] < n) begin
      tx_underflows++;
      tx_cred[r][c] = 0;
    end else begin
      tx_cred[r][c] -= n;
    end
  endfunction

  // ---- RX ------------------------------------------------------------
  // A DUT message of n granules started. Returns 0 on overflow.
  function bit rx_receive(int unsigned r, aou_cred_class_e c, int unsigned n);
    bit ok = rx_outstanding[r][c] >= n;
    if (!ok) rx_overflows++;
    rx_outstanding[r][c] = ok ? rx_outstanding[r][c] - n : 0;
    if (ok && rx_outstanding[r][c] == 0) rx_exhausted[r][c] = 1'b1;
    rx_occupancy[r][c] += n;
    if (cfg.ret_policy[c] == AOU_RET_IMMEDIATE) rx_free(r, c, n);
    return ok;
  endfunction

  // The consumer dequeued a message: its granules leave the buffer.
  function void rx_consume(int unsigned r, aou_cred_class_e c, int unsigned n);
    if (cfg.ret_policy[c] != AOU_RET_IMMEDIATE) rx_free(r, c, n);
  endfunction

  function void rx_free(int unsigned r, aou_cred_class_e c, int unsigned n);
    rx_occupancy[r][c] = (rx_occupancy[r][c] >= n) ? rx_occupancy[r][c] - n : 0;
    case (cfg.ret_policy[c])
      AOU_RET_DELAYED: begin
        dly_due.push_back(tick_now + cfg.ret_delay);
        dly_rp.push_back(r);
        dly_cc.push_back(c);
        dly_n.push_back(n);
      end
      AOU_RET_WITHHELD: rx_withheld[r][c] += n;
      default: rx_pending[r][c] += n;
    endcase
  endfunction

  function void release_withheld();
    foreach (rx_withheld[r, c]) begin
      rx_pending[r][c] += rx_withheld[r][c];
      rx_withheld[r][c] = 0;
    end
  endfunction

  // Advertise n credits the buffer does not have (injection: tests the DUT's
  // saturation and its use of extra credit).
  function void inject_overgrant(int unsigned r, aou_cred_class_e c, int unsigned n);
    rx_pending[r][c] += n;
  endfunction

  // Time for AOU_RET_DELAYED, counted in flits sent and received.
  function bit tick();
    bit moved = 1'b0;
    tick_now++;
    for (int i = dly_due.size() - 1; i >= 0; i--) begin
      if (dly_due[i] <= tick_now) begin
        rx_pending[dly_rp[i]][dly_cc[i]] += dly_n[i];
        dly_due.delete(i);
        dly_rp.delete(i);
        dly_cc.delete(i);
        dly_n.delete(i);
        moved = 1'b1;
      end
    end
    return moved;
  endfunction

  function bit rx_has_pending(bit req_ok = 1'b1, bit rsp_ok = 1'b1);
    for (int unsigned r = 0; r < cfg.rp_count; r++) begin
      for (int unsigned c = 0; c < AOU_CC_NUM; c++) begin
        if (rx_pending[r][c] != 0 && cls_ok(aou_cred_class_e'(c), req_ok, rsp_ok)) return 1'b1;
      end
    end
    return 1'b0;
  endfunction

  static function bit cls_ok(aou_cred_class_e c, bit req_ok, bit rsp_ok);
    return (c inside {AOU_CC_RDATA, AOU_CC_WRESP}) ? rsp_ok : req_ok;
  endfunction

  function bit [2:0] take(int unsigned r, aou_cred_class_e c);
    bit [2:0] e = aou_cred_enc_floor(c, rx_pending[r][c]);
    int unsigned n = aou_cred_dec3(e);
    rx_pending[r][c] -= n;
    if (n != 0 && rx_exhausted[r][c]) begin
      rx_starved[r][c] = 1'b1;
      rx_starved_tick[r][c] = tick_now;
      rx_exhausted[r][c] = 1'b0;
    end
    rx_outstanding[r][c] += n;
    rx_returned[r][c] += n;
    return e;
  endfunction

  // Header MsgCredit for the next RP (round robin) with something to return.
  function bit take_hdr(output bit [15:0] mc, input bit req_ok = 1'b1, input bit rsp_ok = 1'b1);
    mc = '0;
    for (int unsigned k = 0; k < cfg.rp_count; k++) begin
      int unsigned r = (hdr_rr + k) % cfg.rp_count;
      bit any = 1'b0;
      for (int unsigned c = 0; c < AOU_CC_NUM; c++) begin
        if (rx_pending[r][c] != 0 && cls_ok(aou_cred_class_e'(c), req_ok, rsp_ok)) any = 1'b1;
      end
      if (any) begin
        bit [2:0] e[AOU_CC_NUM];
        foreach (e[c]) begin
          e[c] = cls_ok(aou_cred_class_e'(c), req_ok, rsp_ok) ? take(r, aou_cred_class_e'(c)) : '0;
        end
        mc = {2'(r), e[AOU_CC_WRESP][1:0], e[AOU_CC_RDATA], e[AOU_CC_WDATA], e[AOU_CC_RREQ],
              e[AOU_CC_WREQ]};
        hdr_rr = (r + 1) % cfg.rp_count;
        return 1'b1;
      end
    end
    return 1'b0;
  endfunction

  // A CrdtGrant carrying as much as encodes for every implemented RP.
  function bit take_grant(aou_msg_crdtgrant g, bit req_ok = 1'b1, bit rsp_ok = 1'b1);
    bit any = 1'b0;
    for (int unsigned r = 0; r < cfg.rp_count; r++) begin
      for (int unsigned c = 0; c < AOU_CC_NUM; c++) begin
        if (cls_ok(aou_cred_class_e'(c), req_ok, rsp_ok)) begin
          g.enc[r][c] = take(r, aou_cred_class_e'(c));
          if (g.enc[r][c] != 0) any = 1'b1;
        end
      end
    end
    return any;
  endfunction

  // Decoded header MsgCredit: RP in [15:14] (Table 16).
  static function void hdr_decode(bit [15:0] mc, output int unsigned r,
                                  output int unsigned n[AOU_CC_NUM]);
    r = int'(mc[15:14]);
    n[AOU_CC_WREQ]  = aou_cred_dec3(mc[2:0]);
    n[AOU_CC_RREQ]  = aou_cred_dec3(mc[5:3]);
    n[AOU_CC_WDATA] = aou_cred_dec3(mc[8:6]);
    n[AOU_CC_RDATA] = aou_cred_dec3(mc[11:9]);
    n[AOU_CC_WRESP] = aou_cred_dec2(mc[13:12]);
  endfunction

  function string tx2string();
    string s = "";
    for (int unsigned r = 0; r < cfg.rp_count; r++) s = {s, $sformatf("rp%0d=%p ", r, tx_cred[r])};
    return s;
  endfunction
endclass

// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Malformed messages from the remote die, one kind per case, between bursts
// of checked traffic. The spec defines no receiver reaction (BUGS/012); the
// interim expectation is that the DUT drops what it cannot decode, raises
// no interrupt and no LinkReset, and later traffic completes with correct
// data. Each injection must be reported by the testbench's own checkers
// (the model's TX decode and AOU_FDI_CHECKER), which proves it reached the
// wire.
//   bad_type    reserved MSGTYPE 0111b..1111b          AOU-R3
//   bad_miscop  reserved MISCOP                         AOU-R3
//   bad_actop   reserved ACTIVATIONOP                   AOU-R3
//   bad_dlength WriteData with DLENGTH=11b              AOU-R3
//   rsvd        CrdtGrant (no credit) with RsvdZero17   AOU-R11
//   flip_start  MsgStart set inside a CrdtGrant         AOU-R4
//   rp_range    WriteResp naming RP >= RP_COUNT         AOU-R14
//   hdr_rp      header MsgCredit naming RP >= RP_COUNT  AOU-R14
//   grant_rp    CrdtGrant crediting an RP >= RP_COUNT   AOU-R11
//   fdid        an empty flit with FDId 1               AOU-R9
//   hdr_rsvd    an empty flit with protocol-header      AOU-R1
//               RsvdZero bits set
// RP-range kinds need RP_COUNT < 4 and are skipped otherwise.
// Knobs: +kind=<one of the above>|all +T1_TXN.
class aou_rx_msg_error_vseq extends aou_link_base_vseq;
  `uvm_object_utils(aou_rx_msg_error_vseq)

  function new(string name = "aou_rx_msg_error_vseq");
    super.new(name);
  endfunction

  static function string rule_of(string kind);
    case (kind)
      "rsvd", "grant_rp":   return "AOU-R11";
      "flip_start":         return "AOU-R4";
      "rp_range", "hdr_rp": return "AOU-R14";
      "fdid":               return "AOU-R9";
      "hdr_rsvd":           return "AOU-R1";
      default:              return "AOU-R3";
    endcase
  endfunction

  task body();
    string all[11] = '{"bad_type", "bad_miscop", "bad_actop", "bad_dlength", "rsvd",
                       "flip_start", "rp_range", "hdr_rp", "grant_rp", "fdid", "hdr_rsvd"};
    string arg = arg_str("kind", "all");
    string kinds[$];
    foreach (all[i]) begin
      if (arg != "all" && arg != all[i]) continue;
      if (cfg.n_rp >= 4 && (all[i] == "rp_range" || all[i] == "hdr_rp" || all[i] == "grant_rp"))
        continue;
      kinds.push_back(all[i]);
    end
    if (kinds.size() == 0) `uvm_fatal(get_type_name(), {"nothing to run for +kind=", arg})
    kinds.shuffle();
    // Side reports of a corrupted stream: a reserved granule after a flipped
    // MsgStart decodes as a reserved type, and an undecodable Activation
    // granule can also break the placement rules.
    foreach (kinds[i]) expect_event(rule_of(kinds[i]), 1, 0);
    foreach (kinds[i]) begin
      case (kinds[i])
        "flip_start": expect_event("AOU-R3", 0, 0);
        "bad_actop":  expect_event("AOU-R6", 0, 0);
        "rp_range":   expect_event("AOU-R16", 0, 0);
        // AOU_FDI_CHECKER reports header RsvdZero as VIOL_RSVD_NONZERO.
        "hdr_rsvd":   expect_event("AOU-R11", 0, 0);
        default: ;
      endcase
    end
    link_up();
    sw_activate();
    check_traffic(num_txns);
    foreach (kinds[i]) begin
      pause_traffic();
      inject_kind(kinds[i]);
      wait_cycles(1000);
      check_no_linkreset(kinds[i]);
      resume_traffic();
      check_traffic(num_txns);
    end
    sw_deactivate();
  endtask

  task check_no_linkreset(string kind);
    aou_core rm = p_sequencer.regs;
    check_field(rm.lp_linkreset.invalid_actmsg_err, 0, "T1-L18", {kind, " (BUGS/012 interim)"});
    check_field(rm.lp_linkreset.msgcredit_err, 0, "T1-L18", {kind, " (BUGS/012 interim)"});
    check_field(rm.aou_init.activate_state_enabled, 1, "T1-L18", {kind, " (BUGS/012 interim)"});
  endtask

  task inject_kind(string kind);
    aou_packer pk = env.l3.model.pk;
    `uvm_info(get_type_name(), {"injecting ", kind}, UVM_LOW)
    case (kind)
      "bad_type": begin
        aou_l3_bad_type_seq s = aou_l3_bad_type_seq::type_id::create("s");
        s.kind = 0;
        s.msg_type = 4'($urandom_range(15, 7));
        s.start(p_sequencer.l3_sqr);
      end
      "bad_miscop", "bad_actop", "bad_dlength": begin
        aou_l3_bad_type_seq s = aou_l3_bad_type_seq::type_id::create("s");
        s.kind = (kind == "bad_miscop") ? 1 : (kind == "bad_actop") ? 2 : 3;
        s.start(p_sequencer.l3_sqr);
      end
      "rsvd", "flip_start", "grant_rp": begin
        aou_msg_crdtgrant g = aou_msg_crdtgrant::type_id::create("g");
        g.ignore_state = 1'b1;
        if (kind == "rsvd") g.rsvd = 17'($urandom_range(17'h1FFFF, 1));
        if (kind == "grant_rp") g.enc[3][AOU_CC_WREQ] = 3'd1;
        env.l3.send(g);
        // Same time step as the send: the next flit built carries the grant
        // at G0 (the link is idle), so G1 is inside its body.
        if (kind == "flip_start") pk.inj_flip_start = 1;
      end
      "rp_range": begin
        aou_msg_wresp m = aou_msg_wresp::type_id::create("m");
        m.rp = 2'(cfg.n_rp);
        m.ignore_credits = 1'b1;
        env.l3.send(m);
      end
      "hdr_rp", "fdid", "hdr_rsvd": begin
        pk.inj_empty = 1'b1;
        if (kind == "fdid") pk.inj_fdid = 1;
        else if (kind == "hdr_rsvd") pk.inj_hdr_rsvd = $urandom_range(32'h3FFF, 1);
        else pk.inj_msg_credit = int'({2'(cfg.n_rp), 14'h0249});
        env.l3.model.kick();
      end
      default: `uvm_fatal(get_type_name(), {"unknown injection ", kind})
    endcase
  endtask
endclass

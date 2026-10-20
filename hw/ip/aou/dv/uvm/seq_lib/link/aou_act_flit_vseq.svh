// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Credited messages waiting at the moment the DUT sends an Activation message,
// which AoU v0.8 4.4 sends alone in its flit (AOU-R6 judges it). +loops=N
// loops (default 4, deact_rsp 12) of +mode=:
//   act_req    requests held across an activation in which the DUT sends the
//              last activation message. Local requests issued while DISABLED
//              wake the DUT (INT_ACTIVATE_START; software activates it first);
//              the remote die acks, grants its credit and only then asks, so
//              the DUT's ActivateAck goes out with credit and requests ready.
//   deact_rsp  the DUT's DeactivateReq with responses arriving. The remote die
//              reads and writes with long bursts while the DUT's M ports space
//              every R beat and B by g cycles, just over the DUT's quiet window
//              (DEACTIVATE_TIME_OUT_VALUE 0: 8 cycles); software sets
//              DEACTIVATE_START (CREDIT_MANAGE=1) mid-stream, so the
//              DeactivateReq leaves in a gap and the next response follows it
//              within a flit time. g sweeps 9..12 (default 12 loops).
class aou_act_flit_vseq extends aou_link_base_vseq;
  `uvm_object_utils(aou_act_flit_vseq)

  function new(string name = "aou_act_flit_vseq");
    super.new(name);
  endfunction

  task body();
    string mode = arg_str("mode", "act_req");
    int unsigned loops = arg_int("loops", (mode == "deact_rsp") ? 12 : 4);
    link_up();
    sw_activate(AOU_T1_BY_APB, AOU_T1_DUT_FIRST);
    check_traffic(num_txns);
    case (mode)
      "act_req":   repeat (loops) act_req_once();
      "deact_rsp": for (int unsigned i = 0; i < loops; i++) deact_rsp_once(9 + i % 4);
      default:     `uvm_fatal(get_type_name(), {"unknown +mode=", mode})
    endcase
    sw_deactivate(AOU_T1_BY_APB);
  endtask

  task act_req_once();
    aou_t1_traffic_cfg p = aou_t1_traffic_cfg::named("short");
    deactivate(AOU_T1_BY_APB);
    ensure_link();
    cfg.l3_cfg.ack_first = 1'b1;
    cfg.l3_cfg.act_req_after_grant = 1'b1;
    `uvm_info(get_type_name(), "requests while DISABLED; the DUT acks last", UVM_LOW)
    traffic(AOU_T1_L2R, num_txns, p);
    if (!env.status.enabled || l3_state() != AOU_LS_ENABLED)
      `uvm_error(get_type_name(), "T1-L32: requests while DISABLED did not activate the link")
    cfg.l3_cfg.ack_first = 1'b0;
    cfg.l3_cfg.act_req_after_grant = 1'b0;
  endtask

  task deact_rsp_once(int unsigned g);
    aou_t1_traffic_cfg p = aou_t1_traffic_cfg::named("long");
    p.max_len = 8'd63;
    `uvm_info(get_type_name(), $sformatf("DeactivateReq with responses every %0d cycles", g),
              UVM_LOW)
    write_field(p_sequencer.regs.aou_init.deactivate_time_out_value, 0);
    foreach (cfg.m_sub_cfg[r]) begin
      cfg.m_sub_cfg[r].timing.r_beat.set_fixed(g);
      cfg.m_sub_cfg[r].timing.r_lat.set_fixed(g);
      cfg.m_sub_cfg[r].timing.b_lat.set_fixed(g);
    end
    traffic_nb(AOU_T1_R2L, 12, p);
    wait_cycles(100);
    deactivate(AOU_T1_BY_APB, 1'b0, 1);
    wait_traffic();
    foreach (cfg.m_sub_cfg[r]) cfg.m_sub_cfg[r].timing.apply(AOU_AXI_TIMING_RANDOM);
    ensure_link();
    sw_activate(AOU_T1_BY_APB, AOU_T1_DUT_FIRST);
  endtask
endclass

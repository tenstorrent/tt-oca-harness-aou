// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Adapter-initiated FDI link events while AoU is ENABLED and traffic runs
// (fdi_enc=RTL). AoU's reaction is unspecified (BUGS/015); the interim
// expectations are:
//   retrain, clk_wake  transparent: AoU stays ENABLED, no interrupt, every
//                      transaction completes with correct data;
//   l1                 software deactivates first (MAS §7.3.6), the adapter
//                      enters and leaves L1 (clk_req wake, Retrain, Active),
//                      and the link activates again;
//   linkerror,         the link is lost mid-traffic; INT_REQ_LINKRESET may
//   link_reset,        rise; software resets AOU_CORE while the link is down,
//   inband_drop,       brings it up and activates again. In-flight
//   disabled           transactions are aborted by the reset (an M-port ID
//                      mismatch interrupt is tolerated); all later traffic
//                      must complete. Disabled is Adapter-initiated and needs
//                      fdi_enc=SPEC, which the test selects for it.
// Knobs: +event=retrain|clk_wake|l1|linkerror|link_reset|inband_drop|disabled|rand
// (rand never picks disabled)
// +loops +T1_TXN.
class aou_link_event_vseq extends aou_link_base_vseq;
  `uvm_object_utils(aou_link_event_vseq)

  int unsigned n_down;

  function new(string name = "aou_link_event_vseq");
    super.new(name);
  endfunction

  task body();
    string evs[6] = '{"retrain", "clk_wake", "l1", "linkerror", "link_reset", "inband_drop"};
    int unsigned loops = arg_range("loops", 2, 4);
    string arg = arg_str("event", "rand");
    link_up();
    sw_activate();
    for (int unsigned i = 0; i < loops; i++) begin
      string ev = (arg == "rand") ? evs[$urandom_range(5)] : arg;
      `uvm_info(get_type_name(), $sformatf("event %0d/%0d: %s", i + 1, loops, ev), UVM_LOW)
      case (ev)
        "retrain", "clk_wake": transparent(ev == "retrain" ? LSM_EV_RETRAIN : LSM_EV_CLK_WAKE);
        "l1": l1_cycle();
        "linkerror": link_down(LSM_EV_LINKERROR, 1'b0);
        "link_reset": link_down(LSM_EV_LINK_RESET, 1'b0);
        "inband_drop": link_down(LSM_EV_LINK_RESET, 1'b1);
        "disabled": link_down(LSM_EV_DISABLED, 1'b0);
        default: `uvm_fatal(get_type_name(), {"unknown link event ", ev})
      endcase
    end
    check_traffic(num_txns);
    sw_deactivate();
  endtask

  task transparent(aou_lsm_ev_e ev);
    traffic_nb(AOU_T1_BOTH_DIRS, num_txns);
    wait_cycles($urandom_range(500, 20));
    link_event(ev);
    wait_traffic();
    drain();
    check_field(p_sequencer.regs.aou_init.activate_state_enabled, 1, "T1-L19",
                {ev.name(), " is transparent to AoU (BUGS/015 interim)"});
  endtask

  task l1_cycle();
    check_traffic(num_txns);
    sw_deactivate();
    // A deactivation the remote side started also tears the FDI link down
    // (BUGS/011); the adapter completes that before any PM entry.
    ensure_link();
    link_event(LSM_EV_L1_ENTRY);
    wait_cycles($urandom_range(400, 20));
    link_event(LSM_EV_L1_EXIT);
    sw_activate();
  endtask

  task link_down(aou_lsm_ev_e ev, bit inband_drop);
    n_down++;
    expect_event("INT_REQ_LINKRESET", 0, n_down);
    // The DUT can lose track of local M-port transactions when the link
    // drops under them (BUGS/015 interim).
    expect_event("INT_MI0_ID_MISMATCH", 0, n_down);
    traffic_nb(AOU_T1_BOTH_DIRS, num_txns);
    wait_cycles($urandom_range(500, 20));
    recover(null, 1'b1, ev, inband_drop);
    wait_traffic();
    drain();
  endtask
endclass

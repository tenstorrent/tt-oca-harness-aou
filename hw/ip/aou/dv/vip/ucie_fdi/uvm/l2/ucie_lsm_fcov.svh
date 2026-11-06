// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// The model's own link-state coverage: plain SystemVerilog covergroups, built
// by the link-state agent when cfg.fcov_en is set. An observer of the
// link-state monitor like any other: every clock it looks for what changed
// and samples only then. The driver also reports each link event it runs
// (sample_event). Transitions are explicit (previous, current) bins of
// pl_state_sts codes: the ones the model makes, so 100% means every
// transition was made.
class ucie_lsm_fcov extends uvm_object implements ucie_lsm_observer;
  `uvm_object_utils(ucie_lsm_fcov)

  // The link events the model runs, as cg_event bins.
  typedef enum int {
    EV_BRINGUP, EV_RETRAIN, EV_RETRAIN_TO_LINKERROR, EV_RETRAIN_TO_LINKRESET,
    EV_RETRAIN_TO_DISABLED, EV_LINKERROR, EV_LINKERROR_MID_FLIT, EV_LINKERROR_ON_REQUEST,
    EV_L1_ENTRY, EV_L1_EXIT, EV_L1_EXIT_ON_WAKE, EV_LINK_RESET, EV_LINK_RESET_TO_LINKERROR,
    EV_DISABLED, EV_DISABLED_TO_LINKERROR, EV_INBAND_DROP, EV_CLK_WAKE, EV_ABORT
  } ev_e;

  bit [7:0]    tr;        // {previous, current} pl_state_sts
  logic [3:0]  hs_sts;    // pl_state_sts when a handshake completed
  int unsigned rx_code;   // 0/1 entry in Reset/Retrain, 2/3 exit in Active/LinkError
  ev_e         ev;
  int unsigned ab_at;     // abort: 0 Reset, 1 after the wake, 2 after the Active request, 3 in L1
  int unsigned ab_to;     // abort: 0 LinkError, 1 LinkReset, 2 Disabled, 3 Reset

  covergroup cg_state;
    cp_tr: coverpoint tr {
      bins reset_active = {8'h01};
      bins active_retrain = {8'h1B};
      bins retrain_active = {8'hB1};
      bins active_l1 = {8'h14};
      bins l1_retrain = {8'h4B};
      bins active_linkerror = {8'h1A};
      bins active_linkreset = {8'h19};
      bins active_disabled = {8'h1C};
      bins linkerror_reset = {8'hA0};
      bins linkreset_reset = {8'h90};
      bins disabled_reset = {8'hC0};
      bins retrain_linkerror = {8'hBA};
      bins retrain_linkreset = {8'hB9};
      bins retrain_disabled = {8'hBC};
      bins linkreset_linkerror = {8'h9A};
      bins disabled_linkerror = {8'hCA};
      bins reset_linkerror = {8'h0A};
      bins reset_linkreset = {8'h09};
      bins reset_disabled = {8'h0C};
      bins l1_linkerror = {8'h4A};
      bins l1_linkreset = {8'h49};
      bins l1_disabled = {8'h4C};
    }
  endgroup

  // pl_clk_req/lp_clk_ack handshakes, by the state they completed in.
  covergroup cg_clk;
    cp_state: coverpoint hs_sts {
      bins reset = {4'h0};
      bins active = {4'h1};
      bins l1 = {4'h4};
      bins linkreset = {4'h9};
      bins linkerror = {4'hA};
      bins disabled = {4'hC};
    }
  endgroup

  // lp_wake_req/pl_wake_ack handshakes, by the state they completed in.
  covergroup cg_wake;
    cp_state: coverpoint hs_sts {
      bins reset = {4'h0};
      bins l1 = {4'h4};
      bins retrain = {4'hB};
    }
  endgroup

  covergroup cg_rx_active;
    cp_edge: coverpoint rx_code {
      bins entry_in_reset = {0};
      bins entry_in_retrain = {1};
      bins exit_in_active = {2};
      bins exit_in_linkerror = {3};
    }
  endgroup

  // LSM_EV_INBAND_DROP has no bin: it is meant for a link left in Reset
  // (auto_bringup 0), where a test drives the bringup itself.
  covergroup cg_event;
    cp_event: coverpoint ev {
      bins bringup = {EV_BRINGUP};
      bins retrain = {EV_RETRAIN};
      bins retrain_to_linkerror = {EV_RETRAIN_TO_LINKERROR};
      bins retrain_to_linkreset = {EV_RETRAIN_TO_LINKRESET};
      bins retrain_to_disabled = {EV_RETRAIN_TO_DISABLED};
      bins linkerror = {EV_LINKERROR};
      bins linkerror_mid_flit = {EV_LINKERROR_MID_FLIT};
      bins linkerror_on_request = {EV_LINKERROR_ON_REQUEST};
      bins l1_entry = {EV_L1_ENTRY};
      bins l1_exit = {EV_L1_EXIT};
      bins l1_exit_on_wake = {EV_L1_EXIT_ON_WAKE};
      bins link_reset = {EV_LINK_RESET};
      bins link_reset_to_linkerror = {EV_LINK_RESET_TO_LINKERROR};
      bins disabled = {EV_DISABLED};
      bins disabled_to_linkerror = {EV_DISABLED_TO_LINKERROR};
      bins clk_wake = {EV_CLK_WAKE};
      bins abort = {EV_ABORT};
    }
  endgroup

  covergroup cg_abort;
    cp_at: coverpoint ab_at {
      bins reset = {0};
      bins after_wake = {1};
      bins after_active_request = {2};
      bins in_l1 = {3};
    }
    cp_to: coverpoint ab_to {
      bins linkerror = {0};
      bins linkreset = {1};
      bins disabled = {2};
      bins reset = {3};
    }
  endgroup

  function new(string name = "ucie_lsm_fcov");
    super.new(name);
    cg_state = new();
    cg_clk = new();
    cg_wake = new();
    cg_rx_active = new();
    cg_event = new();
    cg_abort = new();
  endfunction

  virtual function void observe(ucie_lsm_obs_t cur, ucie_lsm_obs_t prev);
    if (!(cur.rst_n && prev.rst_n)) return;
    if (cur.pl_state_sts != prev.pl_state_sts) begin
      tr = {prev.pl_state_sts, cur.pl_state_sts};
      cg_state.sample();
    end
    if (cur.clk_ack && !prev.clk_ack) begin
      hs_sts = cur.pl_state_sts;
      cg_clk.sample();
    end
    if (cur.wake_ack && !prev.wake_ack) begin
      hs_sts = cur.pl_state_sts;
      cg_wake.sample();
    end
    if (cur.rx_active_req != prev.rx_active_req) begin
      if (cur.rx_active_req) rx_code = prev.sts == LSM_RETRAIN ? 1 : 0;
      else rx_code = prev.sts == LSM_LINKERROR ? 3 : 2;
      cg_rx_active.sample();
    end
  endfunction

  // A link event as the driver starts it.
  function void sample_event(ucie_lsm_item it);
    case (it.kind)
      LSM_EV_BRINGUP: ev = EV_BRINGUP;
      LSM_EV_RETRAIN:
        case (it.to)
          LSM_LINKERROR: ev = EV_RETRAIN_TO_LINKERROR;
          LSM_LINKRESET: ev = EV_RETRAIN_TO_LINKRESET;
          LSM_DISABLED:  ev = EV_RETRAIN_TO_DISABLED;
          default:       ev = EV_RETRAIN;
        endcase
      LSM_EV_LINKERROR:   ev = EV_LINKERROR;
      LSM_EV_L1_ENTRY:    ev = EV_L1_ENTRY;
      LSM_EV_L1_EXIT:     ev = EV_L1_EXIT;
      LSM_EV_LINK_RESET:  ev = it.to == LSM_LINKERROR ? EV_LINK_RESET_TO_LINKERROR : EV_LINK_RESET;
      LSM_EV_DISABLED:    ev = it.to == LSM_LINKERROR ? EV_DISABLED_TO_LINKERROR : EV_DISABLED;
      LSM_EV_INBAND_DROP: ev = EV_INBAND_DROP;
      LSM_EV_CLK_WAKE:    ev = EV_CLK_WAKE;
      LSM_EV_ABORT: begin
        ev = EV_ABORT;
        ab_at = it.in_l1 ? 3 : it.at == LSM_AB_RESET ? 0 : it.at == LSM_AB_WAKE ? 1 : 2;
        ab_to = it.to == LSM_LINKERROR ? 0 : it.to == LSM_LINKRESET ? 1 :
                it.to == LSM_DISABLED ? 2 : 3;
        cg_abort.sample();
      end
      default: return;  // LSM_EV_IDLE: no event
    endcase
    cg_event.sample();
  endfunction

  // What the driver does on its own: a LinkError entered mid-flit, or one the
  // Protocol Layer requested (lp_linkerror), and an L1 exit the Protocol Layer
  // started (lp_wake_req in L1).
  function void sample_own(ev_e e);
    ev = e;
    cg_event.sample();
  endfunction

  // Each covergroup's coverage (type scores); not asked of Verilator, as in
  // ucie_fdi_fcov.
  function string convert2string();
`ifdef VERILATOR
    return "not scored by this simulator";
`else
    return $sformatf({"state %0.1f%% clk %0.1f%% wake %0.1f%% rx_active %0.1f%% event %0.1f%% ",
                      "abort %0.1f%%"}, cg_state.get_coverage(), cg_clk.get_coverage(),
                     cg_wake.get_coverage(), cg_rx_active.get_coverage(),
                     cg_event.get_coverage(), cg_abort.get_coverage());
`endif
  endfunction
endclass

// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
//
// L2: FDI link state. The Adapter-side link-state agent (pl_state_sts per
// FDI, inband_pres, wake/clk/rx_active handshakes, Adapter-initiated events)
// and its monitor with the handshake checks (UCIe r1.1 §8.2-8.3).

package ucie_lsm_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  `include "ucie_fdi_macros.svh"
  import ucie_fdi_pkg::*;

  // Adapter link states (pl_state_sts)
  typedef enum bit [3:0] {
    LSM_RESET,
    LSM_ACTIVE,
    LSM_ACTIVE_PMNAK,
    LSM_L1,
    LSM_L2,
    LSM_LINKRESET,
    LSM_LINKERROR,
    LSM_RETRAIN,
    LSM_DISABLED,
    LSM_UNKNOWN
  } ucie_lsm_state_e;

  // Protocol Layer requests (lp_state_req)
  typedef enum bit [3:0] {
    LSM_REQ_NOP,
    LSM_REQ_ACTIVE,
    LSM_REQ_L1,
    LSM_REQ_L2,
    LSM_REQ_LINKRESET,
    LSM_REQ_RETRAIN,
    LSM_REQ_DISABLED,
    LSM_REQ_RESERVED
  } ucie_lsm_req_e;

  typedef enum bit [3:0] {
    LSM_EV_BRINGUP,      // Reset to Active (clk_req, inband_pres, Active entry)
    LSM_EV_RETRAIN,      // Active to Retrain and back
    LSM_EV_LINKERROR,    // Active to LinkError, then Reset and bringup
    LSM_EV_L1_ENTRY,     // stallreq/ack, Active to L1
    LSM_EV_L1_EXIT,      // clk_req wake, back to Active
    LSM_EV_LINK_RESET,   // Active to LinkReset, then Reset and bringup
    LSM_EV_INBAND_DROP,  // inband_pres low for a while in Reset
    LSM_EV_CLK_WAKE,     // a pl_clk_req handshake
    LSM_EV_IDLE,         // wait `cycles`
    LSM_EV_DISABLED,     // Active to Disabled, then Reset and bringup
    LSM_EV_ABORT         // a bringup or an L1 exit abandoned part-way (ucie_lsm_item::at)
  } ucie_lsm_ev_e;

  // Where LSM_EV_ABORT leaves the bringup or the L1 exit (ucie_lsm_driver::do_abort)
  typedef enum bit [1:0] {
    LSM_AB_RESET,        // Reset before pl_inband_pres: training never completed
    LSM_AB_WAKE,         // `gap` cycles after the pl_clk_req that wakes the Protocol Layer
                         // (0: status first)
    LSM_AB_REQ_ACTIVE    // `gap` cycles after the Protocol Layer requested Active, before the
                         // Active entry
  } ucie_lsm_abort_e;

  // UCIe state codes (UCIe r1.1 Table 8-2) on pl_state_sts and lp_state_req.
  // States without a code return 4'hF with ok=0.
  function automatic logic [3:0] sts_code(ucie_lsm_state_e s, output bit ok);
    ok = 1'b1;
    case (s)
      LSM_RESET:        return 4'h0;
      LSM_ACTIVE:       return 4'h1;
      LSM_ACTIVE_PMNAK: return 4'h3;
      LSM_L1:           return 4'h4;
      LSM_L2:           return 4'h8;
      LSM_LINKRESET:    return 4'h9;
      LSM_LINKERROR:    return 4'hA;
      LSM_RETRAIN:      return 4'hB;
      LSM_DISABLED:     return 4'hC;
      default: begin ok = 1'b0; return 4'hF; end
    endcase
  endfunction

  function automatic ucie_lsm_state_e sts_decode(logic [3:0] code);
    case (code)
      4'h0:    return LSM_RESET;
      4'h1:    return LSM_ACTIVE;
      4'h3:    return LSM_ACTIVE_PMNAK;
      4'h4:    return LSM_L1;
      4'h8:    return LSM_L2;
      4'h9:    return LSM_LINKRESET;
      4'hA:    return LSM_LINKERROR;
      4'hB:    return LSM_RETRAIN;
      4'hC:    return LSM_DISABLED;
      default: return LSM_UNKNOWN;
    endcase
  endfunction

  function automatic logic [3:0] req_code(ucie_lsm_req_e r);
    case (r)
      LSM_REQ_NOP:       return 4'h0;
      LSM_REQ_ACTIVE:    return 4'h1;
      LSM_REQ_L1:        return 4'h4;
      LSM_REQ_L2:        return 4'h8;
      LSM_REQ_LINKRESET: return 4'h9;
      LSM_REQ_RETRAIN:   return 4'hB;
      LSM_REQ_DISABLED:  return 4'hC;
      default:           return 4'hF;
    endcase
  endfunction

  function automatic ucie_lsm_req_e req_decode(logic [3:0] code);
    case (code)
      4'h0:    return LSM_REQ_NOP;
      4'h1:    return LSM_REQ_ACTIVE;
      4'h4:    return LSM_REQ_L1;
      4'h8:    return LSM_REQ_L2;
      4'h9:    return LSM_REQ_LINKRESET;
      4'hB:    return LSM_REQ_RETRAIN;
      4'hC:    return LSM_REQ_DISABLED;
      default: return LSM_REQ_RESERVED;
    endcase
  endfunction

  `include "l2/ucie_lsm_cfg.svh"
  `include "l2/ucie_lsm_obs.svh"
  `include "l2/ucie_lsm_observer.svh"
  `include "l2/ucie_lsm_item.svh"
  `include "l2/ucie_lsm_monitor.svh"
  `include "l2/ucie_lsm_driver.svh"
  `include "l2/ucie_lsm_agent.svh"
  `include "l2/ucie_lsm_event_seq.svh"
  `include "l2/ucie_lsm_l1_seq.svh"

endpackage

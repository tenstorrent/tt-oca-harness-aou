// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
//
// L2: FDI link state. The Adapter-side link-state agent (pl_state_sts per
// PHY, inband_pres, wake/clk/rx_active handshakes, PL-initiated events), its
// monitor with the handshake checks, and a reference model of the DUT's
// bringup controller (integrator guide §3.14-3.16, §6.6; UCIe r1.1 §8.2-8.3).
//
// fdi_enc selects the state encodings on pl_state_sts, lp_state_req and
// O_FDI_FSM_STATE: SPEC is UCIe; RTL is the DUT's documented encoding
// (BUGS/001), the default until that is fixed.

package aou_lsm_pkg;
  import uvm_pkg::*;
  import aou_rule_pkg::*;
  import aou_fc_pkg::*;
  `include "uvm_macros.svh"
  `include "aou_macros.svh"
  `include "aou_fc_macros.svh"
  import aou_fdi_pkg::*;

  typedef enum bit {AOU_FDI_ENC_RTL, AOU_FDI_ENC_SPEC} aou_fdi_enc_e;

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
  } aou_lsm_state_e;

  // Protocol Layer requests (lp_state_req). LINKERROR exists only in the RTL
  // encoding (integrator guide §3.14).
  typedef enum bit [3:0] {
    LSM_REQ_NOP,
    LSM_REQ_ACTIVE,
    LSM_REQ_L1,
    LSM_REQ_L2,
    LSM_REQ_LINKRESET,
    LSM_REQ_RETRAIN,
    LSM_REQ_DISABLED,
    LSM_REQ_LINKERROR,
    LSM_REQ_RESERVED
  } aou_lsm_req_e;

  // States of the bringup controller (integrator guide §6.6)
  typedef enum bit [3:0] {
    BRG_RESET,
    BRG_WAIT_PRESENCE,
    BRG_WAKE_ASSERT,
    BRG_WAKE_WAIT_ACK,
    BRG_REQ_ACTIVE,
    BRG_ACTIVE,
    BRG_LINKERROR,
    BRG_RETRAIN,
    BRG_DEACTIVATE,
    BRG_UNWAKE_WAIT,
    BRG_L1,
    BRG_L1_CLK_WAKE,
    BRG_LINKDOWN         // Adapter in LinkReset/Disabled (fdi_enc=SPEC; BUGS/001 item 4)
  } aou_brg_state_e;

  typedef enum bit [3:0] {
    LSM_EV_BRINGUP,      // Reset to Active (clk_req, inband_pres, Active entry)
    LSM_EV_RETRAIN,      // Active to Retrain and back
    LSM_EV_LINKERROR,    // Active to LinkError, then Reset and bringup
    LSM_EV_L1_ENTRY,     // stallreq/ack, Active to L1
    LSM_EV_L1_EXIT,      // clk_req wake, back to Active
    LSM_EV_LINK_RESET,   // Active to LinkReset (RTL encoding: Reset), then bringup
    LSM_EV_INBAND_DROP,  // inband_pres low for a while in Reset
    LSM_EV_CLK_WAKE,     // a pl_clk_req handshake
    LSM_EV_IDLE,         // wait `cycles`
    LSM_EV_DISABLED      // Active to Disabled (fdi_enc=SPEC), then Reset and bringup
  } aou_lsm_ev_e;

  // Bringup software pins of the DUT
  typedef enum bit [1:0] {
    LSM_SW_ACTIVATE,
    LSM_SW_DEACTIVATE,
    LSM_SW_RETRAIN,
    LSM_SW_LINKERROR
  } aou_lsm_sw_e;

  // pl_state_sts and O_FDI_FSM_STATE codes. States the RTL encoding has no
  // code for return 4'hF with ok=0.
  function automatic logic [3:0] sts_code(aou_lsm_state_e s, aou_fdi_enc_e enc, output bit ok);
    ok = 1'b1;
    if (enc == AOU_FDI_ENC_SPEC) begin
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
    end
    case (s)
      LSM_RESET:     return 4'h0;
      LSM_ACTIVE:    return 4'h1;
      LSM_LINKERROR: return 4'h2;
      LSM_RETRAIN:   return 4'h3;
      LSM_L1:        return 4'h4;
      LSM_L2:        return 4'h5;
      LSM_DISABLED:  return 4'h6;
      default: begin ok = 1'b0; return 4'hF; end
    endcase
  endfunction

  function automatic aou_lsm_state_e sts_decode(logic [3:0] code, aou_fdi_enc_e enc);
    if (enc == AOU_FDI_ENC_SPEC) begin
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
    end
    case (code)
      4'h0:    return LSM_RESET;
      4'h1:    return LSM_ACTIVE;
      4'h2:    return LSM_LINKERROR;
      4'h3:    return LSM_RETRAIN;
      4'h4:    return LSM_L1;
      4'h5:    return LSM_L2;
      4'h6:    return LSM_DISABLED;
      default: return LSM_UNKNOWN;
    endcase
  endfunction

  function automatic logic [3:0] req_code(aou_lsm_req_e r, aou_fdi_enc_e enc);
    if (enc == AOU_FDI_ENC_SPEC) begin
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
    end
    case (r)
      LSM_REQ_NOP:       return 4'h0;
      LSM_REQ_ACTIVE:    return 4'h1;
      LSM_REQ_LINKERROR: return 4'h2;
      LSM_REQ_RETRAIN:   return 4'h3;
      LSM_REQ_L1:        return 4'h4;
      LSM_REQ_L2:        return 4'h5;
      LSM_REQ_DISABLED:  return 4'h6;
      default:           return 4'hF;
    endcase
  endfunction

  function automatic aou_lsm_req_e req_decode(logic [3:0] code, aou_fdi_enc_e enc);
    if (enc == AOU_FDI_ENC_SPEC) begin
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
    end
    case (code)
      4'h0:    return LSM_REQ_NOP;
      4'h1:    return LSM_REQ_ACTIVE;
      4'h2:    return LSM_REQ_LINKERROR;
      4'h3:    return LSM_REQ_RETRAIN;
      4'h4:    return LSM_REQ_L1;
      4'h5:    return LSM_REQ_L2;
      4'h6:    return LSM_REQ_DISABLED;
      default: return LSM_REQ_RESERVED;
    endcase
  endfunction

  `include "l2/aou_lsm_cfg.svh"
  `include "l2/aou_lsm_obs.svh"
  `include "l2/aou_lsm_item.svh"
  `include "l2/aou_lsm_fc_bins.svh"
  `include "l2/aou_lsm_cov.svh"
  `include "l2/aou_bringup_model.svh"
  `include "l2/aou_lsm_monitor.svh"
  `include "l2/aou_lsm_driver.svh"
  `include "l2/aou_lsm_agent.svh"
  `include "l2/aou_lsm_event_seq.svh"
  `include "l2/aou_lsm_bringup_seq.svh"
  `include "l2/aou_lsm_retrain_seq.svh"
  `include "l2/aou_lsm_linkerror_seq.svh"
  `include "l2/aou_lsm_l1_seq.svh"
  `include "l2/aou_lsm_reset_seq.svh"
  `include "l2/aou_lsm_inband_drop_seq.svh"
  `include "l2/aou_lsm_clk_wake_seq.svh"

endpackage

// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// One clock's view of the link-state signals, as the monitor samples them.
// pl_state_sts is the one the DUT follows (I_PHY_TYPE in TWO_PHY builds).
class aou_lsm_obs extends uvm_sequence_item;
  `uvm_object_utils(aou_lsm_obs)

  bit             rst_n = '0;
  logic [3:0]     pl_state_sts = '0;
  aou_lsm_state_e sts = LSM_RESET;
  bit             inband_pres = '0;
  bit             clk_req = '0;
  bit             wake_ack = '0;
  bit             rx_active_req = '0;
  logic [3:0]     lp_state_req = '0;
  aou_lsm_req_e   req = LSM_REQ_NOP;
  bit             wake_req = '0;
  bit             clk_ack = '0;
  bit             rx_active_sts = '0;
  bit             linkerror = '0;
  bit             sw_activate = '0;
  bit             sw_deactivate = '0;
  bit             sw_retrain = '0;
  bit             sw_linkerror = '0;
  logic [3:0]     fsm_state = '0;
  bit             link_up = '0;
  bit             int_activate = '0;
  bit             int_deactivate = '0;
  bit             req_linkreset = '0;
  bit             act_st_disabled = '0;

  function new(string name = "aou_lsm_obs");
    super.new(name);
  endfunction

  function string convert2string();
    return $sformatf({"sts=%s(%0h) req=%s(%0h) inband=%0b clk=%0b/%0b wake=%0b/%0b rx=%0b/%0b ",
                      "fsm=%0h up=%0b sw=%0b%0b%0b%0b"},
                     sts.name(), pl_state_sts, req.name(), lp_state_req, inband_pres,
                     clk_req, clk_ack, wake_req, wake_ack, rx_active_req, rx_active_sts,
                     fsm_state, link_up, sw_activate, sw_deactivate, sw_retrain, sw_linkerror);
  endfunction
endclass

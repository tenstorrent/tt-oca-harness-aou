// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// One clock's view of the link-state signals, as the monitor samples them.
// pl_state_sts is the one of the FDI the Protocol Layer follows
// (ucie_lsm_cfg::active_phy). A plain value: the monitor keeps this clock's and
// the previous one and hands both to its observers, with nothing allocated.
typedef struct {
  bit              rst_n;
  logic [3:0]      pl_state_sts;
  ucie_lsm_state_e sts;
  bit              inband_pres;
  bit              clk_req;
  bit              wake_ack;
  bit              rx_active_req;
  logic [3:0]      lp_state_req;
  ucie_lsm_req_e   req;
  bit              wake_req;
  bit              clk_ack;
  bit              rx_active_sts;
  bit              linkerror;
} ucie_lsm_obs_t;

// The value before reset: everything low, Reset, NOP.
function automatic ucie_lsm_obs_t obs_reset();
  ucie_lsm_obs_t o;
  o.rst_n = 1'b0;
  o.pl_state_sts = 4'h0;
  o.sts = LSM_RESET;
  o.inband_pres = 1'b0;
  o.clk_req = 1'b0;
  o.wake_ack = 1'b0;
  o.rx_active_req = 1'b0;
  o.lp_state_req = 4'h0;
  o.req = LSM_REQ_NOP;
  o.wake_req = 1'b0;
  o.clk_ack = 1'b0;
  o.rx_active_sts = 1'b0;
  o.linkerror = 1'b0;
  return o;
endfunction

function automatic string obs2string(ucie_lsm_obs_t o);
  return $sformatf("sts=%s(%0h) req=%s(%0h) inband=%0b clk=%0b/%0b wake=%0b/%0b rx=%0b/%0b",
                   o.sts.name(), o.pl_state_sts, o.req.name(), o.lp_state_req, o.inband_pres,
                   o.clk_req, o.clk_ack, o.wake_req, o.wake_ack, o.rx_active_req,
                   o.rx_active_sts);
endfunction

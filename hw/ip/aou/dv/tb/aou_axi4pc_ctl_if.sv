// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Link-event control of the Axi4PC checkers on the DUT's AXI ports (config_db key
// "axi4pc_ctl"; driven by aou_t1_axi4pc_ctl, applied by tb/aou_axi4pc_gate.sv).
// present: Axi4PC is compiled in. guard: the BUGS/021 guard owns the ports across
// AOU_SW_RESET. off_set: a one-cycle request to hold every port's checker in reset.
// s_off/m_off[r]: RP r's S/M checker is held in reset beyond its port's reset.
// chk_scope: the checkers' generate scope (<scope>[r].u_s_axi4pc, .u_m_axi4pc).
interface aou_axi4pc_ctl_if (input logic clk);
  string      chk_scope;
  wire        present;
  wire        guard;
  logic       off_set = 1'b0;
  wire  [7:0] s_off;
  wire  [7:0] m_off;

  clocking cb @(posedge clk);
    output off_set;
    input  present, guard, s_off, m_off;
  endclocking
endinterface

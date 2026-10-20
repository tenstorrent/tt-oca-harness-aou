// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Link-event control of the Axi4PC checkers on the DUT's AXI ports (config_db key
// "axi4pc_ctl"; driven by aou_t1_axi4pc_ctl, applied by tb/aou_axi4pc_gate.sv).
// present: Axi4PC is compiled in. guard: the BUGS/021 guard owns the ports across
// AOU_SW_RESET. off_set: a one-cycle request to hold every port's checker in reset.
// s_resync/m_resync[r]: a one-cycle request to reset RP r's S/M checker once, then hold
// it until the port is quiet (its tracking is no longer valid, aou_t1_axi4pc_ctl).
// s_off/m_off[r]: RP r's S/M checker is held in reset beyond its port's reset.
// s_sync_wait/m_sync_wait[r]: a resync of RP r's S/M checker waits for a quiet cycle.
// chk_scope: the checkers' generate scope (<scope>[r].u_s_axi4pc, .u_m_axi4pc).
interface aou_axi4pc_ctl_if (input logic clk);
  string      chk_scope;
  wire        present;
  wire        guard;
  logic       off_set = 1'b0;
  logic [7:0] s_resync = '0;
  logic [7:0] m_resync = '0;
  wire  [7:0] s_off;
  wire  [7:0] m_off;
  wire  [7:0] s_sync_wait;
  wire  [7:0] m_sync_wait;

  clocking cb @(posedge clk);
    output off_set, s_resync, m_resync;
    input  present, guard, s_off, m_off, s_sync_wait, m_sync_wait;
  endclocking
endinterface

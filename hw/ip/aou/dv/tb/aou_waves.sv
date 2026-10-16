// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc
//
// Run-time waveform dumping for simulators without a Tcl shell, enabled by
// +waves (or +waves=<file stem>) with no rebuild. The Makefile binds this into
// every non-VCS top and defines AOU_WAVES_TOP; VCS dumps FSDB through UCLI.
// Formats: FST on Verilator (built with --trace-fst), SHM on Xcelium, else VCD.

`timescale 1ns/1ps

module aou_waves;
  initial begin
    string arg;
    string stem;
    // "+waves" leaves arg empty; "+waves=<stem>" leaves "=<stem>".
    if ($value$plusargs("waves%s", arg)) begin
      stem = (arg.len() > 1 && arg[0] == "=") ? arg.substr(1, arg.len() - 1) : "waves";
`ifdef VERILATOR
      $dumpfile({stem, ".fst"});
      $dumpvars;
`elsif AOU_WAVES_SHM
      $shm_open({stem, ".shm"});
      $shm_probe(`AOU_WAVES_TOP, "AS");
`else
      $dumpfile({stem, ".vcd"});
      $dumpvars(0, `AOU_WAVES_TOP);
`endif
    end
  end
endmodule

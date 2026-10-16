// SPDX-License-Identifier: Apache-2.0
// Copyright (c) Tenstorrent USA Inc
//*************************************************************************
//
// Shared collector for AXI4 functional-coverage text reports.
//
//   Each coverage instance registers its report section at end-of-sim and
//   calls flush(); flush() rewrites the combined file from the queue, so
//   the last `final` block emits the complete report regardless of order.
//
//   Output (one file per run): <dir>/aou_axi4_fc.<run>.txt
//     dir : +AXI4_FC_RPT_DIR=<path>  (default ".")
//     run : +AXI4_FC_RUN_NAME=<name> (default "run")
//
//   Human-readable summary + machine-readable "#BINDATA" region consumed
//   by the union merge (hw/ip/aou/dv/scripts/merge_axi4_fc.py). Pure SystemVerilog.
//
//*************************************************************************
`ifndef AOU_AXI4_FC_PKG_SV
`define AOU_AXI4_FC_PKG_SV

package aou_axi4_fc_pkg;

  class aou_axi4_fc_collector;
    // Per-interface accumulators (static => shared across all instances)
    static string names[$];
    static real   totals[$];
    static string sections[$];   // human-readable per-interface blocks
    static string bindata[$];    // machine-readable per-interface bin dumps

    // Default to the sim run directory (CWD); override with +AXI4_FC_RPT_DIR.
    static string default_dir = ".";

    // Register one interface's results.
    static function void add(string name, real total, string section, string bin_sec);
      names.push_back(name);
      totals.push_back(total);
      sections.push_back(section);
      bindata.push_back(bin_sec);
    endfunction

    // (Re)write this run's report file from everything registered so far.
    static function void flush();
      int    fd;
      string dir;
      string run;
      string fname;

      dir = default_dir;
      run = "run";
      void'($value$plusargs("AXI4_FC_RPT_DIR=%s", dir));
      void'($value$plusargs("AXI4_FC_RUN_NAME=%s", run));
      if (dir.len() == 0) dir = ".";
      if (run.len() == 0) run = "run";
      fname = $sformatf("%s/aou_axi4_fc.%s.txt", dir, run);

      fd = $fopen(fname, "w");
      if (fd == 0) begin
        $display("[AXI4_FC] WARNING: could not open report file: %s", fname);
        return;
      end

      $fwrite(fd, "================================================================================\n");
      $fwrite(fd, "AOU RTL - AXI4 FUNCTIONAL COVERAGE SUMMARY\n");
      $fwrite(fd, "================================================================================\n");
      $fwrite(fd, "Run        : %0s\n", run);
      $fwrite(fd, "Generated  : %0t\n", $time);
      $fwrite(fd, "Interfaces : %0d\n", names.size());
      $fwrite(fd, "\n");
      $fwrite(fd, "--- PER-INTERFACE TOTAL COVERAGE ---\n");
      $fwrite(fd, "%-34s %8s\n", "INTERFACE", "TOTAL%");
      $fwrite(fd, "--------------------------------------------------\n");
      foreach (names[i])
        $fwrite(fd, "%-34s %7.2f%%\n", names[i], totals[i]);
      $fwrite(fd, "\n\n");
      $fwrite(fd, "################################################################################\n");
      $fwrite(fd, "# PER-INTERFACE DETAIL\n");
      $fwrite(fd, "################################################################################\n\n");
      foreach (sections[i])
        $fwrite(fd, "%s", sections[i]);

      // Machine-readable bin data for the cross-run union merge.
      $fwrite(fd, "\n\n#BINDATA v1\n");
      foreach (bindata[i])
        $fwrite(fd, "%s", bindata[i]);
      $fwrite(fd, "#ENDBINDATA\n");

      $fclose(fd);
    endfunction
  endclass

endpackage

`endif // AOU_AXI4_FC_PKG_SV

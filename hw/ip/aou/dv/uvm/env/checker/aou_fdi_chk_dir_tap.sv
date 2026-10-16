// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Per-direction view of AOU_FDI_CHECKER's findings, for aou_fdi_chk_adapter.
// O_VIOLATION merges both directions and the capture record names only the
// first finding, so a second class reported in the same capture would lose its
// direction. The top connects the checker's internal finding matrix here; the
// outputs follow O_VIOLATION's sticky/clear behaviour, per direction (0 LP,
// 1 PL), with the flit number of the first finding since the last clear.
module aou_fdi_chk_dir_tap
  import aou_fdi_wire_pkg::GRANULE_CNT;
  import aou_fdi_checker_pkg::VIOL_CLASS_CNT;
(
    input  logic                                            clk,
    input  logic                                            rst_n,
    input  logic                                            clr,
    input  logic [1:0]                                      go,
    input  logic [1:0][GRANULE_CNT-1:0][VIOL_CLASS_CNT-1:0] granule_viol,
    input  logic [1:0][31:0]                                flit_seq,
    output logic [1:0][VIOL_CLASS_CNT-1:0]                  dir_violation,
    output logic [1:0][31:0]                                dir_flit_seq
);
  logic [1:0][VIOL_CLASS_CNT-1:0] found;

  always_comb begin
    found = '0;
    for (int d = 0; d < 2; d++)
      if (go[d])
        for (int g = 0; g < GRANULE_CNT; g++) found[d] = found[d] | granule_viol[d][g];
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      dir_violation <= '0;
      dir_flit_seq  <= '0;
    end else begin
      for (int d = 0; d < 2; d++) begin
        if (found[d] != 0) begin
          if (clr || dir_violation[d] == 0) dir_flit_seq[d] <= flit_seq[d];
          dir_violation[d] <= (clr ? '0 : dir_violation[d]) | found[d];
        end else if (clr) begin
          dir_violation[d] <= '0;
        end
      end
    end
  end
endmodule

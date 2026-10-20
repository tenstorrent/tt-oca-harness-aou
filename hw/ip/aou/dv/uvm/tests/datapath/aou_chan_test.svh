// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// AXI channel orderings the DUT must take: the scoreboard checks the data and
// the drain that nothing hangs; xfer_cov.chan_cg shows the ordering happened.
// +chan=wfirst (plan 4.31): local writes only, each W burst presented before
//   its AW (AW held back 4-20 cycles, W at once; AXI4 A3.3.1). The DUT holds
//   WREADY until the AW arrives (MAS 3.7.5), so the check is that nothing
//   hangs and the data lands; xfer_cov.chan_cg w_before_aw shows the ordering.
// +chan=ilv (plan 8.14): reads on distinct IDs both ways, the local
//   subordinates interleave R beats of different IDs at the M ports and the
//   remote die interleaves the ReadData it returns (L3 rdata_ilv), so the DUT
//   both forwards and receives interleaved read data.
class aou_chan_test extends aou_dp_base_test;
  `uvm_component_utils(aou_chan_test)

  string       mode = "wfirst";

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void set_knobs();
    void'($value$plusargs("chan=%s", mode));
    case (mode)
      "wfirst": begin
        k.dir = AOU_T1_L2R;
        k.wr_pct = 100;
        k.lens = '{0, 1, 3, 7, 15};
        k.n = 48;
      end
      "ilv": begin
        k.dir = AOU_T1_BOTH_DIRS;
        k.wr_pct = 25;
        k.ids = aou_dp_knobs::DP_ID_UNIQUE;
        k.lens = '{3, 7, 15};
        k.batch = 8;
        k.n = 64;
      end
      default: `uvm_fatal(get_type_name(), {"bad +chan=", mode})
    endcase
  endfunction

  function void configure_test();
    for (int unsigned r = 0; r < cfg.n_rp; r++) begin
      if (mode == "wfirst") begin
        cfg.s_mgr_cfg[r].w_before_aw_en = 1'b1;
        cfg.s_mgr_cfg[r].timing.aw_valid.set_range(4, 20);
        cfg.s_mgr_cfg[r].timing.w_valid.set_zero();
      end else begin
        cfg.m_sub_cfg[r].r_interleave_en = 1'b1;
      end
    end
    if (mode == "ilv") begin
      cfg.l3_cfg.resp_fork = 1'b1;
      cfg.l3_cfg.rdata_ilv = 1'b1;
      if (cfg.remote_lat_max < 8) cfg.remote_lat_max = 8;
    end
  endfunction
endclass

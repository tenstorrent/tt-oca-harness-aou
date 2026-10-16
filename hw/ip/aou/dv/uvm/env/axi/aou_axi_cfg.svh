// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Configuration of one AXI agent (manager or subordinate) and its monitor.
class aou_axi_cfg extends uvm_object;
  `uvm_object_utils(aou_axi_cfg)

  // The agent fetches vif from uvm_config_db under vif_key when vif is null.
  string        vif_key = "";
  aou_axi_vif_t vif;

  uvm_active_passive_enum is_active = UVM_ACTIVE;
  bit has_monitor = 1'b1;

  // Real bus width in bytes (8 to 128); the interface is always 1024 bits.
  int unsigned data_bytes = 64;
  // Copied into every published transaction.
  int unsigned rp;
  bit          local_side = 1'b1;
  // The bus carries INCR bursts only (an AoU S port): sequences generate no
  // other burst type and the monitor flags one (AXI-R19).
  bit          incr_only = 1'b0;

  // Manager.
  int unsigned max_wr_outstanding = 16;
  int unsigned max_rd_outstanding = 16;
  bit          w_before_aw_en     = 1'b1;  // 0: W waits for its AW handshake

  // Subordinate.
  aou_mem mem;
  bit     reorder_en      = 1'b1;  // B/R out of order across IDs
  bit     r_interleave_en = 1'b0;  // interleave R beats of different IDs
  bit     exclusive_en    = 1'b1;  // 0: exclusive accesses get OKAY and never write
  bit     hold_req        = 1'b0;  // 1: AWREADY, WREADY and ARREADY held low

  // Monitor.
  bit checks_en = 1'b1;
  bit cov_en    = 1'b1;

  aou_axi_timing timing;

  function new(string name = "aou_axi_cfg");
    super.new(name);
    timing = aou_axi_timing::type_id::create("timing");
  endfunction

  function int unsigned max_size();
    int unsigned s = 0;
    while ((32'd1 << (s + 1)) <= data_bytes) s++;
    return s;
  endfunction

  function void check_cfg(string who);
    if (!(data_bytes inside {8, 16, 32, 64, 128}))
      `uvm_fatal(who, $sformatf("data_bytes=%0d is not 8, 16, 32, 64 or 128", data_bytes))
  endfunction
endclass

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

  // AXI USER stimulus (aou_axi_user_mode_e): the manager's AWUSER/ARUSER and
  // WUSER per W beat, the subordinate's BUSER and RUSER per R beat. The
  // default gives every transaction one random value on all its beats, so
  // the DUT's FLEX = USER check (aou_t1_attr_chk) sees a nonzero value on
  // every message while merged beats still agree. user_pat picks the values.
  aou_axi_user_mode_e user_mode = AOU_AXI_USER_CONST;
  aou_axi_user_pat_e  user_pat  = AOU_AXI_USER_PAT_RANDOM;
  protected int unsigned user_walk;

  aou_axi_timing timing;

  function new(string name = "aou_axi_cfg");
    super.new(name);
    timing = aou_axi_timing::type_id::create("timing");
  endfunction

  // The next USER value for the nonzero modes.
  function bit [15:0] next_user();
    case (user_pat)
      AOU_AXI_USER_PAT_ONES: return 16'hFFFF;
      AOU_AXI_USER_PAT_WALK: begin
        user_walk = (user_walk + 1) % 16;
        return 16'd1 << user_walk;
      end
      default: return 16'($urandom());
    endcase
  endfunction

  // Fills n values per user_mode: all zero, one value for all, or one each.
  function void fill_user(ref bit [15:0] u[], input int unsigned n);
    bit [15:0] v = 16'h0;
    u = new[n];
    if (user_mode == AOU_AXI_USER_CONST) v = next_user();
    foreach (u[i]) u[i] = (user_mode == AOU_AXI_USER_PER_BEAT) ? next_user() : v;
  endfunction

  // One value for a request or a B: zero in the zero mode.
  function bit [15:0] one_user();
    return (user_mode == AOU_AXI_USER_ZERO) ? 16'h0 : next_user();
  endfunction

  static function string user_mode_name(aou_axi_user_mode_e m);
    case (m)
      AOU_AXI_USER_ZERO:     return "zero";
      AOU_AXI_USER_CONST:    return "const_per_txn";
      AOU_AXI_USER_PER_BEAT: return "per_beat";
      default:               return "?";
    endcase
  endfunction

  // "zero", "const_per_txn" or "per_beat" (the +user_mode= plusarg); 0 if unknown.
  static function bit parse_user_mode(string s, ref aou_axi_user_mode_e m);
    case (s)
      "zero":          m = AOU_AXI_USER_ZERO;
      "const_per_txn": m = AOU_AXI_USER_CONST;
      "per_beat":      m = AOU_AXI_USER_PER_BEAT;
      default:         return 1'b0;
    endcase
    return 1'b1;
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

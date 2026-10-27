// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Byte-level AXI scoreboard (docs/ARCHITECTURE.md, "Scoreboard rule").
//
// - local_mgr_imp: transactions the local managers completed at the DUT's S
//   ports. They target the remote memory.
// - remote_imp: transactions the remote die (L4a) originated towards the DUT
//   and completed. They target the local memory.
// - local_sub_imp: what the local subordinates saw at the DUT's M ports; only
//   counted, since the memory itself is checked.
//
// remote_mem and local_mem are the memories the remote model and the local
// subordinates answer from (all local subordinates share one aou_mem). The
// scoreboard keeps a golden copy of each, taken at start of simulation. For
// every write it applies the strobed bytes to golden and checks the response
// and the real memory; for every read it checks each beat's response and,
// for OKAY/EXOKAY beats, every active lane against golden. At the end the real
// and golden memories must agree on every written byte.
//
// Reset rule. A transaction a reset aborted (abort()) counts as aborted, and
// so does a write on the bus when AOU_SW_RESET was requested (reset_outstanding),
// whatever its response: the reset loses every write queued in AOU_CORE
// (MAS 7.3.6), including one already acknowledged early (7.2.5), so the write
// may have landed or not. The bytes such a write addresses may hold their old
// value or the write's value until a checked write defines them again. A
// reset_outstanding read's SLVERR beats are not checked (MAS 7.3.6 loses the read
// and defines no response; the SLVERR is taken from the RTL); its
// OKAY beats, every other response and every later transaction are checked as
// above.
class aou_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(aou_scoreboard)

  uvm_analysis_imp_local_mgr #(aou_axi_txn, aou_scoreboard) local_mgr_imp;
  uvm_analysis_imp_local_sub #(aou_axi_txn, aou_scoreboard) local_sub_imp;
  uvm_analysis_imp_remote #(aou_axi_txn, aou_scoreboard)    remote_imp;

  aou_mem remote_mem;
  aou_mem local_mem;

  int unsigned n_l2r_wr;
  int unsigned n_l2r_rd;
  int unsigned n_r2l_wr;
  int unsigned n_r2l_rd;
  int unsigned n_local_sub;
  int unsigned n_err_resp;    // error responses seen (and expected)
  int unsigned n_mismatch;
  int unsigned n_aborted;     // ended by a reset before their response (abort())
  int unsigned n_reset_err;   // reset_outstanding: writes (lost or landed), reads with SLVERR
  int unsigned n_unchecked;   // in an add_unchecked() window

  // Windows that are not memory (the DUT's error-information debug address):
  // a transaction starting in one is counted only, never compared or applied.
  protected bit [63:0] nochk_lo[$];
  protected bit [63:0] nochk_hi[$];

  // Bytes an aborted write may or may not have changed, with the values they
  // may hold (bit v set: v is allowed), until a later write defines them again.
  protected bit [255:0] unknown_remote[bit [63:0]];
  protected bit [255:0] unknown_local[bit [63:0]];

  protected aou_mem golden_remote;
  protected aou_mem golden_local;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    local_mgr_imp = new("local_mgr_imp", this);
    local_sub_imp = new("local_sub_imp", this);
    remote_imp    = new("remote_imp", this);
  endfunction

  function void start_of_simulation_phase(uvm_phase phase);
    golden_remote = aou_mem::type_id::create("golden_remote");
    golden_local  = aou_mem::type_id::create("golden_local");
    if (remote_mem != null) golden_remote.copy_from(remote_mem);
    if (local_mem != null) golden_local.copy_from(local_mem);
  endfunction

  function void add_unchecked(bit [63:0] lo, bit [63:0] hi);
    nochk_lo.push_back(lo);
    nochk_hi.push_back(hi);
  endfunction

  protected function bit unchecked(aou_axi_txn t);
    foreach (nochk_lo[i]) if (t.addr >= nochk_lo[i] && t.addr <= nochk_hi[i]) return 1'b1;
    return 1'b0;
  endfunction

  function void write_local_mgr(aou_axi_txn t);
    if (unchecked(t)) begin
      n_unchecked++;
      return;
    end
    if (remote_mem == null) `uvm_fatal(get_type_name(), "remote_mem is not set")
    check_txn(t, golden_remote, remote_mem, "local->remote");
    if (t.dir == AOU_AXI_WR) n_l2r_wr++;
    else n_l2r_rd++;
  endfunction

  function void write_remote(aou_axi_txn t);
    if (unchecked(t)) begin
      n_unchecked++;
      return;
    end
    if (local_mem == null) `uvm_fatal(get_type_name(), "local_mem is not set")
    check_txn(t, golden_local, local_mem, "remote->local");
    if (t.dir == AOU_AXI_WR) n_r2l_wr++;
    else n_r2l_rd++;
  endfunction

  function void write_local_sub(aou_axi_txn t);
    n_local_sub++;
  endfunction

  // Reset contract: t (local_side 1: a local manager's, towards the remote
  // memory; 0: the remote die's, towards the local memory) was aborted by a
  // reset. It is neither missing nor checked; the bytes an aborted write
  // addresses become unknown.
  function void abort(aou_axi_txn t);
    n_aborted++;
    if (t.dir != AOU_AXI_WR) return;
    make_unknown(t.local_side ? golden_remote : golden_local, t);
  endfunction

  // Each strobed byte of write t may keep its value or take t's.
  protected function void make_unknown(aou_mem gold, aou_axi_txn t);
    bit [7:0] b[bit [63:0]];
    bit [255:0] ok;
    t.to_bytes(b);
    foreach (b[a]) begin
      if (gold == golden_remote)
        ok = unknown_remote.exists(a) ? unknown_remote[a] : 256'd1 << gold.read_byte(a);
      else
        ok = unknown_local.exists(a) ? unknown_local[a] : 256'd1 << gold.read_byte(a);
      ok[b[a]] = 1'b1;
      if (gold == golden_remote) unknown_remote[a] = ok;
      else unknown_local[a] = ok;
    end
  endfunction

  protected function bit is_unknown(aou_mem gold, bit [63:0] a);
    if (gold == golden_remote) return unknown_remote.exists(a);
    return unknown_local.exists(a);
  endfunction

  // v is a value unknown byte a may hold.
  protected function bit allowed(aou_mem gold, bit [63:0] a, bit [7:0] v);
    if (gold == golden_remote) return unknown_remote[a][v];
    return unknown_local[a][v];
  endfunction

  protected function void forget_unknown(aou_mem gold, aou_axi_txn t);
    bit [7:0] b[bit [63:0]];
    t.to_bytes(b);
    foreach (b[a]) begin
      if (gold == golden_remote) begin
        if (unknown_remote.exists(a)) unknown_remote.delete(a);
      end else if (unknown_local.exists(a)) begin
        unknown_local.delete(a);
      end
    end
  endfunction

  protected function void fail(string rule, string msg, aou_axi_txn t, string path);
    n_mismatch++;
    `uvm_error(get_type_name(), $sformatf("%s: %s %s: %s", rule, path, msg, t.convert2string()))
  endfunction

  protected function void check_txn(aou_axi_txn t, aou_mem gold, aou_mem actual, string path);
    if (t.dir == AOU_AXI_WR) check_write(t, gold, actual, path);
    else check_read(t, gold, path);
  endfunction

  protected function void check_write(aou_axi_txn t, aou_mem gold, aou_mem actual, string path);
    bit [1:0] exp = gold.txn_resp(t);
    bit apply = 1'b1;
    bit [7:0] b[bit [63:0]];
    int unsigned bad = 0;
    bit [63:0] first_bad;
    if (t.data.size() != t.beats() || t.strb.size() != t.beats()) begin
      fail("AXI-S01", $sformatf("write has %0d data beats for len %0d", t.data.size(), t.len),
           t, path);
      return;
    end
    // On the bus at the AOU_SW_RESET request: lost or landed, whatever the response.
    if (t.reset_outstanding) begin
      n_reset_err++;
      make_unknown(gold, t);
      return;
    end
    if (exp != AOU_AXI_OKAY) begin
      n_err_resp++;
      if (t.bresp != exp)
        fail("AXI-S01", $sformatf("BRESP %0d, memory error region gives %0d", t.bresp, exp),
             t, path);
      apply = !t.lock;
    end else if (t.lock) begin
      apply = (t.bresp == AOU_AXI_EXOKAY);
      if (t.bresp != AOU_AXI_OKAY && t.bresp != AOU_AXI_EXOKAY)
        fail("AXI-S01", $sformatf("exclusive write BRESP %0d", t.bresp), t, path);
    end else if (t.bresp != AOU_AXI_OKAY) begin
      fail("AXI-S01", $sformatf("BRESP %0d, expected OKAY", t.bresp), t, path);
    end
    if (!apply) return;
    gold.write_txn(t);
    forget_unknown(gold, t);
    if (actual == null) return;
    t.to_bytes(b);
    foreach (b[a]) begin
      if (actual.read_byte(a) != gold.read_byte(a)) begin
        if (bad == 0) first_bad = a;
        bad++;
      end
    end
    if (bad > 0)
      fail("AXI-S02", $sformatf("%0d written bytes differ, first at %0h: %0h, expected %0h",
                                bad, first_bad, actual.read_byte(first_bad),
                                gold.read_byte(first_bad)), t, path);
  endfunction

  protected function void check_read(aou_axi_txn t, aou_mem gold, string path);
    bit [1:0] exp;
    bit [63:0] base;
    bit [7:0] got;
    bit reset_err = 1'b0;
    if (t.data.size() != t.beats() || t.rresp.size() != t.beats()) begin
      fail("AXI-S03", $sformatf("read has %0d data beats for len %0d", t.data.size(), t.len),
           t, path);
      return;
    end
    for (int unsigned i = 0; i < t.beats(); i++) begin
      if (t.reset_outstanding && t.rresp[i] == AOU_AXI_SLVERR) begin
        reset_err = 1'b1;
        continue;
      end
      exp = gold.beat_resp(t, i);
      if (exp != AOU_AXI_OKAY) begin
        n_err_resp++;
        if (t.rresp[i] != exp)
          fail("AXI-S03", $sformatf("beat %0d RRESP %0d, memory error region gives %0d", i,
                                    t.rresp[i], exp), t, path);
        continue;
      end
      if (!(t.rresp[i] == AOU_AXI_OKAY || (t.lock && t.rresp[i] == AOU_AXI_EXOKAY))) begin
        fail("AXI-S03", $sformatf("beat %0d RRESP %0d, expected OKAY", i, t.rresp[i]), t, path);
        continue;
      end
      base = t.beat_base(i);
      for (int unsigned l = t.lane_lo(i); l <= t.lane_hi(i); l++) begin
        got = t.data[i][8*l +: 8];
        if (is_unknown(gold, base + 64'(l))) begin
          if (allowed(gold, base + 64'(l), got)) continue;
          fail("AXI-S04", $sformatf({"beat %0d lane %0d (addr %0h) read %0h, neither its old ",
                                     "value %0h nor an aborted write's"}, i, l, base + 64'(l),
                                    got, gold.read_byte(base + 64'(l))), t, path);
          break;
        end
        if (got != gold.read_byte(base + 64'(l))) begin
          fail("AXI-S04", $sformatf("beat %0d lane %0d (addr %0h) read %0h, expected %0h", i, l,
                                    base + 64'(l), got, gold.read_byte(base + 64'(l))), t, path);
          break;
        end
      end
    end
    if (reset_err) n_reset_err++;
  endfunction

  protected function void compare_mem(aou_mem gold, aou_mem actual, string name);
    bit [63:0] addrs[$];
    int unsigned bad = 0;
    if (actual == null) return;
    actual.get_written(addrs);
    gold.get_written(addrs);
    foreach (addrs[k]) begin
      if (is_unknown(gold, addrs[k]) ? !allowed(gold, addrs[k], actual.read_byte(addrs[k])) :
          actual.read_byte(addrs[k]) != gold.read_byte(addrs[k])) begin
        if (bad < 8)
          `uvm_error(get_type_name(), $sformatf("AXI-S05: %s memory at %0h is %0h, expected %0h%s",
                                                name, addrs[k], actual.read_byte(addrs[k]),
                                                gold.read_byte(addrs[k]),
                                                is_unknown(gold, addrs[k]) ?
                                                " or an aborted write's value" : ""))
        bad++;
      end
    end
    if (bad > 0) begin
      n_mismatch += bad;
      `uvm_error(get_type_name(), $sformatf("AXI-S05: %s memory differs from golden at %0d bytes",
                                            name, bad))
    end
  endfunction

  function void check_phase(uvm_phase phase);
    compare_mem(golden_remote, remote_mem, "remote");
    compare_mem(golden_local, local_mem, "local");
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info(get_type_name(), $sformatf({"local->remote %0d writes %0d reads; remote->local %0d ",
        "writes %0d reads; %0d at M ports; %0d error responses; %0d mismatches; ",
        "%0d aborted by reset; %0d on the bus at AOU_SW_RESET; %0d unchecked"},
        n_l2r_wr, n_l2r_rd, n_r2l_wr, n_r2l_rd, n_local_sub, n_err_resp, n_mismatch,
        n_aborted, n_reset_err, n_unchecked), UVM_LOW)
  endfunction
endclass

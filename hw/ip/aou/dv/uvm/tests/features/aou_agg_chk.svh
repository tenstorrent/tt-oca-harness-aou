// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// MAS 3.8 aggregator, observed at the DUT's M port for remote-originated traffic.
// FEAT-R03 (enabled): a narrow multi-beat burst never reaches the M port; it is
// promoted to the full bus width. FEAT-R04 (disabled): every original burst
// reaches the M port with its own address, size and length. The enable is per
// RP (agg_en[rp]), and each RP is judged by its own. A write is only eligible
// when it is modifiable and not exclusive (AWCACHE[1]=1, AWLOCK=0; MAS 3.8.2,
// RTL PR #89); other writes pass through unchanged even with the aggregator
// on, and are judged like FEAT-R04. Reads are always eligible (3.8.3).
// need_from/need_to (bytes, 0: off) require at least one eligible narrow
// multi-beat original of that beat size on an RP of that width, so a run that
// claims a promotion (plan 17.3: 256-bit bursts onto a 1024-bit RP) shows it
// happened.
class aou_agg_chk extends uvm_component;
  `uvm_component_utils(aou_agg_chk)

  uvm_tlm_analysis_fifo #(aou_axi_txn) orig_fifo;
  uvm_tlm_analysis_fifo #(aou_axi_txn) mport_fifo;

  bit          agg_en[4] = '{0, 0, 0, 0};
  int unsigned rp_bytes[];       // local (M port) bus width per RP
  int unsigned need_from = 0;
  int unsigned need_to = 0;

  int unsigned n_narrow_orig;    // narrow multi-beat originals: the interesting ones
  int unsigned n_m;
  protected int unsigned n_by_width[string];  // narrow originals, "<beat>-><RP width>"
  protected int unsigned m_seen[string];
  protected string       want[$];

  function new(string name, uvm_component parent);
    super.new(name, parent);
    orig_fifo  = new("orig_fifo", this);
    mport_fifo = new("mport_fifo", this);
  endfunction

  // The M-port width of the transaction's RP: RP widths differ on the
  // mixed-width configurations.
  function int unsigned bus_bytes(aou_axi_txn t);
    return (t.rp < rp_bytes.size()) ? rp_bytes[t.rp] : 64;
  endfunction

  function bit narrow_burst(aou_axi_txn t);
    return t.beat_bytes() < bus_bytes(t) && t.len != 0;
  endfunction

  // The aggregator may merge this burst: on for its RP, and for a write only
  // when it is modifiable and not exclusive (MAS 3.8.2).
  function bit eligible(aou_axi_txn t);
    return agg_en[t.rp] && (t.dir == AOU_AXI_RD || (t.cache[1] && !t.lock));
  endfunction

  static function string width_key(int unsigned from, int unsigned to);
    return $sformatf("%0d->%0d", from, to);
  endfunction

  function string key(aou_axi_txn t);
    return $sformatf("%0d:%0h:%0d:%0d", t.dir, t.addr, t.size, t.len);
  endfunction

  function void take_orig(aou_axi_txn t);
    // Exercised: a narrow original the aggregator could act on (its RP off, or
    // on and the burst eligible); with it on, a non-eligible write proves nothing.
    if (narrow_burst(t) && (!agg_en[t.rp] || eligible(t))) begin
      string wk = width_key(t.beat_bytes(), bus_bytes(t));
      n_narrow_orig++;
      if (n_by_width.exists(wk)) n_by_width[wk]++;
      else n_by_width[wk] = 1;
    end
    // A beat wider than the RP goes through the width converter, which
    // reshapes the burst whatever the aggregator does.
    if (!eligible(t) && t.beat_bytes() <= bus_bytes(t)) want.push_back(key(t));
  endfunction

  function void take_m(aou_axi_txn t);
    string k = key(t);
    n_m++;
    if (eligible(t) && narrow_burst(t))
      `uvm_error(get_type_name(), $sformatf(
          "FEAT-R03: RP%0d aggregator on but a %0d-byte, %0d-beat burst reached the M port: %s",
          t.rp, t.beat_bytes(), t.beats(), t.convert2string()))
    if (m_seen.exists(k)) m_seen[k]++;
    else m_seen[k] = 1;
  endfunction

  task run_phase(uvm_phase phase);
    aou_axi_txn t;
    fork
      forever begin orig_fifo.get(t); take_orig(t); end
      forever begin mport_fifo.get(t); take_m(t); end
    join
  endtask

  function void check_phase(uvm_phase phase);
    aou_axi_txn t;
    while (orig_fifo.try_get(t)) take_orig(t);
    while (mport_fifo.try_get(t)) take_m(t);
    if (n_narrow_orig == 0)
      `uvm_error(get_type_name(), "FEAT-R03: no narrow multi-beat burst was exercised")
    if (need_from != 0 && !n_by_width.exists(width_key(need_from, need_to)))
      `uvm_error(get_type_name(), $sformatf(
          "FEAT-R03: no narrow multi-beat %0d-byte burst on a %0d-byte RP was exercised",
          need_from, need_to))
    foreach (want[i]) begin
      if (m_seen.exists(want[i]) && m_seen[want[i]] > 0) m_seen[want[i]]--;
      else
        `uvm_error(get_type_name(), $sformatf(
            {"FEAT-R04: aggregator off (or write not eligible) but burst ",
             "{dir:addr:size:len}=%s not unchanged at the M port"},
            want[i]))
    end
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info(get_type_name(), $sformatf(
        "agg_en=%p: %0d narrow multi-beat originals (beat bytes->RP bytes: %p), %0d M-port",
        agg_en, n_narrow_orig, n_by_width, n_m), UVM_LOW)
  endfunction
endclass

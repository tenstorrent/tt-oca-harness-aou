// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// MAS 3.6 splitter, observed at the DUT's M port for remote-originated traffic.
// FEAT-R01: no M-port burst is longer than MAX_AxBURSTLEN + 1 beats (the
// effective value: an illegal write is stored as 0xF). FEAT-R02: each original
// burst becomes ceil(beats / (MAX_AxBURSTLEN + 1)) M-port bursts, so with every
// burst within the limit the M port sees exactly the original bursts.
// Limits are per RP (plan 15.16). A remote beat wider than the RP is first cut
// into RP-wide beats before the splitter, which still keeps every M-port
// burst within the limit (MAS 3.6.1), so the beats counted are the RP beats
// (plan 15.17: a 16-beat 512-bit burst is 32 beats on a 256-bit RP). Needs size-aligned bursts and the
// aggregator off; the test keeps both.
class aou_split_chk extends uvm_component;
  `uvm_component_utils(aou_split_chk)

  uvm_tlm_analysis_fifo #(aou_axi_txn) orig_fifo;   // remote-originated, completed
  uvm_tlm_analysis_fifo #(aou_axi_txn) mport_fifo;  // DUT M port

  int unsigned max_awlen[4] = '{15, 15, 15, 15};
  int unsigned max_arlen[4] = '{15, 15, 15, 15};
  int unsigned rp_bytes[];       // local (M port) bus width per RP

  int unsigned n_orig[4][2];
  int unsigned n_split_orig[4][2];  // originals longer than the limit
  int unsigned n_conv_orig[4][2];   // originals whose beats the downsizer cut
  int unsigned n_exp_m[4][2];
  int unsigned n_m[4][2];

  function new(string name, uvm_component parent);
    super.new(name, parent);
    orig_fifo  = new("orig_fifo", this);
    mport_fifo = new("mport_fifo", this);
  endfunction

  function int unsigned max_len(int unsigned rp, aou_axi_dir_e d);
    return (d == AOU_AXI_WR) ? max_awlen[rp] : max_arlen[rp];
  endfunction

  // Beats of t once its beats are cut to the RP width.
  function int unsigned rp_beats(aou_axi_txn t);
    int unsigned bb = t.beat_bytes();
    int unsigned w = (t.rp < rp_bytes.size()) ? rp_bytes[t.rp] : bb;
    return (bb > w) ? t.beats() * (bb / w) : t.beats();
  endfunction

  function void take_orig(aou_axi_txn t);
    int unsigned per = max_len(t.rp, t.dir) + 1;
    int unsigned nb = rp_beats(t);
    int unsigned subs = (nb + per - 1) / per;
    n_orig[t.rp][t.dir]++;
    n_exp_m[t.rp][t.dir] += subs;
    if (subs > 1) n_split_orig[t.rp][t.dir]++;
    if (nb != t.beats()) n_conv_orig[t.rp][t.dir]++;
  endfunction

  function void take_m(aou_axi_txn t);
    n_m[t.rp][t.dir]++;
    aou_rule_log::check("FEAT-R01", get_type_name());
    if (int'(t.len) > int'(max_len(t.rp, t.dir))) begin
      aou_rule_log::fire("FEAT-R01", get_type_name());
      `uvm_error(get_type_name(), $sformatf(
          "FEAT-R01: RP%0d M-port burst of %0d beats, MAX_%sBURSTLEN=%0d: %s", t.rp, t.beats(),
          (t.dir == AOU_AXI_WR) ? "AW" : "AR", max_len(t.rp, t.dir), t.convert2string()))
    end
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
    foreach (n_m[r, d]) begin
      if (n_orig[r][d] == 0 && n_m[r][d] == 0) continue;
      aou_rule_log::check("FEAT-R02", get_type_name());
      if (n_m[r][d] != n_exp_m[r][d]) begin
        aou_rule_log::fire("FEAT-R02", get_type_name());
        `uvm_error(get_type_name(), $sformatf(
            "FEAT-R02: RP%0d %s: %0d originals need %0d M-port bursts, saw %0d", r,
            (d == int'(AOU_AXI_WR)) ? "writes" : "reads", n_orig[r][d], n_exp_m[r][d], n_m[r][d]))
      end
    end
  endfunction

  function void report_phase(uvm_phase phase);
    foreach (n_orig[r]) begin
      if (n_orig[r][0] + n_orig[r][1] == 0) continue;
      `uvm_info(get_type_name(), $sformatf(
          {"RP%0d max aw/ar len %0d/%0d: wr %0d orig (%0d split, %0d downsized) -> %0d M; ",
           "rd %0d orig (%0d split, %0d downsized) -> %0d M"},
          r, max_awlen[r], max_arlen[r], n_orig[r][0], n_split_orig[r][0], n_conv_orig[r][0],
          n_m[r][0], n_orig[r][1], n_split_orig[r][1], n_conv_orig[r][1], n_m[r][1]), UVM_LOW)
    end
  endfunction
endclass

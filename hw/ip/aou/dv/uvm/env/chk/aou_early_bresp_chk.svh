// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// MAS 3.7 early write response, for local writes (DUT S port -> remote model).
// FEAT-R05: with EARLY_BRESP_EN=1 a bufferable write (AWCACHE[0]=1) that is
// not exclusive gets its B at the S port before the remote die has completed
// it, unless an older write with the same ID was still waiting for its B when
// it was issued (MAS 3.7.7: the early B then waits for that write). FEAT-R06:
// any other write, exclusive ones included (MAS 3.7.1), gets its B only after
// the remote die completed it. B time is its BVALID rise on the S
// port, not the handshake the manager may delay with BREADY. A B that followed
// another B back to back (BVALID held across the handshake) may have waited
// behind it, so FEAT-R05 is not judged for it. Writes pair with
// their remote completion by ID and address; stimulus keeps those unique
// among in-flight writes.
// The enable is per RP and may change between traffic phases (plan 16.14,
// 16.15): set_en() records each change, and a write is judged by its RP's
// setting when its AW was accepted (the vseq changes it only with no write
// pending, WRITE_RESP_DONE = 1, MAS 3.7.8).
class aou_early_bresp_chk extends uvm_component;
  `uvm_component_utils(aou_early_bresp_chk)

  uvm_tlm_analysis_fifo #(aou_axi_txn) s_fifo;       // local manager monitor (S port)
  uvm_tlm_analysis_fifo #(aou_axi_txn) remote_fifo;  // remote model responses

  bit          early_en[4] = '{0, 0, 0, 0};
  int unsigned n_rp = 1;

  int unsigned n_early;
  int unsigned n_early_held;   // bufferable, behind an older same-ID write
  int unsigned n_normal;

  protected aou_axi_txn s_all[$];
  protected aou_axi_txn pair_s[$];
  protected aou_axi_txn pair_r[$];

  // Per RP, BVALID rise time of every B in handshake order, and the S-port
  // writes in publication (= handshake) order.
  protected time         b_rise[4][$];
  protected bit          b_queued[4][$];
  protected aou_axi_txn  s_ord[4][$];
  protected aou_axi_vif_t vif[4];
  protected time         en_t[4][$];   // set_en() times and values, per RP
  protected bit          en_v[4][$];

  protected aou_axi_txn s_q[string][$];
  protected aou_axi_txn r_q[string][$];

  function new(string name, uvm_component parent);
    super.new(name, parent);
    s_fifo      = new("s_fifo", this);
    remote_fifo = new("remote_fifo", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    for (int unsigned r = 0; r < n_rp; r++)
      if (!uvm_config_db#(virtual aou_axi_bus_if #(.DATA_W(1024)))::get(
              this, "", $sformatf("s_axi%0d", r), vif[r]))
        `uvm_fatal(get_type_name(), $sformatf("no s_axi%0d interface", r))
  endfunction

  // RP r's EARLY_BRESP_EN is v for writes accepted from now on.
  function void set_en(int unsigned r, bit v);
    en_t[r].push_back($time);
    en_v[r].push_back(v);
  endfunction

  function bit en_at(int unsigned r, time t);
    bit v = early_en[r];
    foreach (en_t[r][i]) if (en_t[r][i] <= t) v = en_v[r][i];
    return v;
  endfunction

  task watch_b(int unsigned r);
    time t0;
    bit  in_b = 1'b0;
    bit  hs_last = 1'b0;
    bit  queued = 1'b0;
    forever begin
      @(vif[r].mon_cb);
      if (vif[r].mon_cb.bvalid === 1'b1 && !in_b) begin
        in_b = 1'b1;
        t0 = $time;
        queued = hs_last;
      end
      hs_last = 1'b0;
      if (in_b && vif[r].mon_cb.bready === 1'b1) begin
        b_rise[r].push_back(t0);
        b_queued[r].push_back(queued);
        in_b = 1'b0;
        hs_last = 1'b1;
      end
    end
  endtask

  // The B waited behind another B the manager had not yet accepted, so when
  // it became ready cannot be seen.
  function bit b_was_queued(aou_axi_txn s);
    foreach (s_ord[s.rp][i])
      if (s_ord[s.rp][i] == s) return (i < b_queued[s.rp].size()) ? b_queued[s.rp][i] : 1'b0;
    return 1'b0;
  endfunction

  function time b_time(aou_axi_txn s);
    foreach (s_ord[s.rp][i])
      if (s_ord[s.rp][i] == s) return (i < b_rise[s.rp].size()) ? b_rise[s.rp][i] : s.t_done;
    return s.t_done;
  endfunction

  function string key(aou_axi_txn t);
    return $sformatf("%0h:%0h", t.id, t.addr);
  endfunction

  function bit expect_early(aou_axi_txn s);
    return en_at(s.rp, s.t_addr) && s.cache[0] && !s.lock;
  endfunction

  function void judge(aou_axi_txn s, aou_axi_txn r);
    pair_s.push_back(s);
    pair_r.push_back(r);
  endfunction

  // An older write with the same ID had not got its B when s was issued.
  function bit held_by_older(aou_axi_txn s);
    foreach (s_all[i])
      if (s_all[i] != s && s_all[i].id == s.id && s_all[i].t_addr < s.t_addr &&
          s_all[i].t_done >= s.t_addr)
        return 1'b1;
    return 1'b0;
  endfunction

  function void evaluate(aou_axi_txn s, aou_axi_txn r);
    if (expect_early(s) && (held_by_older(s) || b_was_queued(s))) begin
      n_early_held++;
      if (s.bresp != AOU_AXI_OKAY)
        `uvm_error(get_type_name(), $sformatf("FEAT-R05: early B is %0d, not OKAY: %s", s.bresp,
                                              s.convert2string()))
    end else if (expect_early(s)) begin
      n_early++;
      if (!(b_time(s) < r.t_done))
        `uvm_error(get_type_name(), $sformatf(
            "FEAT-R05: bufferable write's B at %0t is not before the remote completion at %0t: %s",
            b_time(s), r.t_done, s.convert2string()))
      if (s.bresp != AOU_AXI_OKAY)
        `uvm_error(get_type_name(), $sformatf("FEAT-R05: early B is %0d, not OKAY: %s", s.bresp,
                                              s.convert2string()))
    end else begin
      n_normal++;
      if (!(b_time(s) > r.t_done))
        `uvm_error(get_type_name(), $sformatf(
            "FEAT-R06: write's B at %0t is not after the remote completion at %0t: %s",
            b_time(s), r.t_done, s.convert2string()))
    end
  endfunction

  function void take(aou_axi_txn t, bit is_s);
    string k;
    if (t.dir != AOU_AXI_WR) return;
    k = key(t);
    if (is_s) begin
      s_all.push_back(t);
      s_ord[t.rp].push_back(t);
      if (r_q.exists(k) && r_q[k].size() > 0) judge(t, r_q[k].pop_front());
      else s_q[k].push_back(t);
    end else begin
      if (s_q.exists(k) && s_q[k].size() > 0) judge(s_q[k].pop_front(), t);
      else r_q[k].push_back(t);
    end
  endfunction

  task run_phase(uvm_phase phase);
    aou_axi_txn t;
    for (int unsigned r = 0; r < n_rp; r++) begin
      automatic int unsigned rr = r;
      fork
        watch_b(rr);
      join_none
    end
    fork
      forever begin s_fifo.get(t); take(t, 1'b1); end
      forever begin remote_fifo.get(t); take(t, 1'b0); end
    join
  endtask

  function void check_phase(uvm_phase phase);
    aou_axi_txn t;
    int unsigned left = 0;
    while (s_fifo.try_get(t)) take(t, 1'b1);
    while (remote_fifo.try_get(t)) take(t, 1'b0);
    foreach (pair_s[i]) evaluate(pair_s[i], pair_r[i]);
    foreach (s_q[k]) left += s_q[k].size();
    foreach (r_q[k]) left += r_q[k].size();
    if (left != 0)
      `uvm_error(get_type_name(), $sformatf(
          "FEAT-R06: %0d writes have no matching S-port B or remote completion", left))
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info(get_type_name(), $sformatf(
        "early_en=%p: %0d early, %0d early not timed (same-ID or B queue), %0d normal B",
        early_en, n_early, n_early_held, n_normal), UVM_LOW)
  endfunction
endclass

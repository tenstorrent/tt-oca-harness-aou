// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Write-transaction watchdog (MAS software-operation 7.2.6; plan 16.17-16.23),
// stimulus only: the env's aou_t1_wdt_chk judges the DUT (FEAT-R23 to R28).
// The watchdog is for error capture: software reads it before it resets the
// device. aou_wdt_test programs the threshold T, WDT_EN on every RP and the
// mask before activation. A hang is the remote die answering every write
// `lat` cycles late (remote B latency with forked responses), so each write
// lands and only its B waits. The flow:
//  1. 3T + 100 cycles with WDT_EN set and nothing outstanding;
//  2. hang: writes on each RP in `rps` (multi_rp: starts staggered by T/2 +
//     50 cycles). near_miss first restarts the count with single writes whose
//     AW lands T-3..T idle cycles after the last handshake, the last ones in
//     the cycle that would have expired;
//  3. wait for each RP's expiry and read WRITE_EARLY_RESPONSE_RPn; masked:
//     clear the mask, so the pin rises with the status set;
//  4. W1C of WDT_TRANS_TIMEOUT_ERR on each RP, read-modify-write (the read
//     updates the mirror, the write carries WDT_EN and EARLY_BRESP_EN back),
//     then 3T + 200 cycles still hung with no second expiry, and a read;
//  5. a device reset, AOU_SW_RESET (the MAS 7.3.6 sequence) or I_RESETN, then
//     reprogram and activate;
//  6. hang again: the reset re-armed the watchdog, so it expires again;
//  7. the remote latency returns to normal and every write completes.
// A hang that ends with no expiry the checker could judge (the writes were
// answered before the threshold) proves nothing, so the sequence reports it
// as a stimulus failure. It is a check of the test, not of the DUT, and has
// no rule ID; it polls the checker's model once per cycle for a bounded time.
class aou_wdt_vseq extends aou_dp_vseq;
  `uvm_object_utils(aou_wdt_vseq)

  string       wdt_case = "expiry";   // expiry | near_miss | masked | multi_rp
  int unsigned thr = 300;
  string       reset_kind = "hard";   // hard | sw
  int unsigned rps = 1;               // RPs that hang (bit r: RP r)
  int unsigned n_wr = 4;              // writes per RP per hang
  int unsigned lat;                   // remote B latency during a hang

  protected aou_t1_wdt_chk chk;
  protected int unsigned   n_calls;   // traffic calls so far, each in its own window
  // The AXI ID of a hang's writes: the second hang uses others, since the
  // local manager holds a new write on an ID whose response a reset dropped.
  protected bit [9:0]      hang_id;

  function new(string name = "aou_wdt_vseq");
    super.new(name);
  endfunction

  task pre_body();
    super.pre_body();
    void'(uvm_config_db#(string)::get(null, "*", "wdt_case", wdt_case));
    void'(uvm_config_db#(int unsigned)::get(null, "*", "wdt_thr", thr));
    void'(uvm_config_db#(string)::get(null, "*", "wdt_reset", reset_kind));
    void'(uvm_config_db#(int unsigned)::get(null, "*", "wdt_rps", rps));
    void'(uvm_config_db#(int unsigned)::get(null, "*", "wdt_n_wr", n_wr));
    chk = env.wdt_chk;
    lat = 6 * thr + 8000;
    if (wdt_case == "near_miss") lat += 12 * thr;
    if (wdt_case == "multi_rp") lat += cfg.n_rp * (thr / 2 + 50);
    `uvm_info(get_type_name(), $sformatf("case %s T=%0d reset %s rps=%4b writes %0d latency %0d",
                                         wdt_case, thr, reset_kind, rps[3:0], n_wr, lat), UVM_LOW)
  endtask

  task body();
    link_up();
    configure_dut();
    activate(AOU_T1_BY_APB, AOU_T1_DUT_FIRST);
    wait_cycles(3 * thr + 100);
    hang(wdt_case == "near_miss");
    read_status();
    if (wdt_case == "masked")
      write_field(p_sequencer.regs.aou_interrupt_mask.int_early_wdt_mask, 0);
    for (int unsigned r = 0; r < cfg.n_rp; r++) if (rps[r]) clear_status(r);
    wait_cycles(3 * thr + 200);
    read_status();
    device_reset();
    hang(1'b0);
    read_status();
    cfg.remote_cfg.timing.b_lat.set_range(0, cfg.remote_lat_max);
    wait_traffic();
    drain();
  endtask

  // n writes on RP r, in an address window no other call of this test uses.
  protected task writes(int unsigned r, int unsigned n);
    aou_t1_traffic_cfg p = make_profile();
    p.rp_mask = 4'(1 << r);
    p.wr_pct = 100;
    p.base = p.base + 64'(n_calls++) * p.span;
    k.ids = aou_dp_knobs::DP_ID_SAME;
    k.id_value = hang_id + 10'(r);
    traffic_nb(AOU_T1_L2R, n, p);
  endtask

  // Waits up to `bound` cycles for cond to hold (outstanding writes, an expiry
  // or a new AW restart on RP r, by `what`).
  protected task wait_for(int unsigned r, string what, int unsigned bound, int unsigned n0 = 0);
    for (int unsigned i = 0; i < bound; i++) begin
      case (what)
        "pending": if (chk.outstanding(r) != 0) return;
        "expiry":  if (chk.expired(r)) return;
        default:   if (chk.n_aw_restart[r] != n0 || chk.expired(r)) return;
      endcase
      wait_cycles(1);
    end
  endtask

  protected task hang(bit restarts);
    bit first = 1'b1;
    hang_id = (hang_id == 10'h150) ? 10'h2A0 : 10'h150;
    cfg.remote_cfg.timing.b_lat.set_fixed(lat);
    for (int unsigned r = 0; r < cfg.n_rp; r++) begin
      if (!rps[r]) continue;
      if (!first) wait_cycles(thr / 2 + 50);
      first = 1'b0;
      if (restarts) near_miss(r);
      else writes(r, n_wr);
    end
    for (int unsigned r = 0; r < cfg.n_rp; r++) begin
      if (!rps[r]) continue;
      wait_for(r, "expiry", 2 * thr + 5000);
      if (!chk.expired(r))
        `uvm_error(get_type_name(), $sformatf(
            {"stimulus failure: RP%0d: the hang ended with no expiry (%0d writes ",
             "outstanding, %0d idle cycles, WDT_THRESHOLD %0d)"},
            r, chk.outstanding(r), chk.idle_count(r), thr))
    end
  endtask

  // Single writes whose AW handshake cuts the count short at T-3, T-2, T-1 and
  // T idle cycles, then T and T-1 again; the delay from the call to the
  // handshake is learnt from each restart the checker saw.
  protected task near_miss(int unsigned r);
    longint d = 2;
    writes(r, 1);
    wait_for(r, "pending", 5000);
    for (longint i = 0; i < 8; i++) begin
      longint want = (i < 4) ? longint'(thr) - 3 + i : longint'(thr) - (i % 2);
      int unsigned n0 = chk.n_aw_restart[r];
      int unsigned guard = 0;
      if (chk.expired(r)) break;
      while (longint'(chk.idle_count(r)) + d < want && guard++ < thr + 1000) wait_cycles(1);
      writes(r, 1);
      wait_for(r, "restart", 2000, n0);
      if (chk.n_aw_restart[r] != n0) begin
        d += longint'(chk.last_restart_idle[r]) - want;
        if (d < 0) d = 0;
        if (d > 50) d = 50;
        `uvm_info(get_type_name(), $sformatf("RP%0d AW restart after %0d idle cycles (aim %0d)",
                                             r, chk.last_restart_idle[r], want), UVM_MEDIUM)
      end
    end
  endtask

  protected task read_status();
    for (int unsigned r = 0; r < cfg.n_rp; r++) begin
      uvm_reg_data_t v;
      uvm_reg rg = p_sequencer.regs.get_reg_by_name($sformatf("write_early_response_rp%0d", r));
      read_field(rg.get_field_by_name("wdt_trans_timeout_err"), v);
      `uvm_info(get_type_name(), $sformatf("RP%0d WDT_TRANS_TIMEOUT_ERR %0d", r, v), UVM_LOW)
    end
  endtask

  protected task clear_status(int unsigned r);
    uvm_reg_data_t v;
    uvm_reg rg = p_sequencer.regs.get_reg_by_name($sformatf("write_early_response_rp%0d", r));
    read_field(rg.get_field_by_name("wdt_trans_timeout_err"), v);
    write_field(rg.get_field_by_name("wdt_trans_timeout_err"), 1);
  endtask

  protected task device_reset();
    `uvm_info(get_type_name(), {"device reset: ", reset_kind}, UVM_LOW)
    if (reset_kind == "sw") begin
      sw_reset(k.feat);
    end else begin
      hard_reset(AOU_T1_RST_BOTH, 1'b0);
      link_up();
      program_cfg(k.feat);
      activate(AOU_T1_BY_APB, AOU_T1_DUT_FIRST);
    end
    wait_traffic();
  endtask
endclass

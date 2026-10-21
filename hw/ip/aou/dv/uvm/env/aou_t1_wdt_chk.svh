// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Write-transaction watchdog (MAS software-operation 7.2.6, architecture 3.7.5,
// interrupts INT_EARLY_WDT_ERR; RDL WRITE_EARLY_RESPONSE_RPn.WDT_EN and
// WDT_TRANS_TIMEOUT_ERR, WRITE_EARLY_RESPONSE_WDT_CTL.WDT_THRESHOLD), on every RP
// in every test, from aou_wdt_if (config_db key "wdt").
//
// Per RP the model counts the writes outstanding (AW accepted by the RP, the
// remote die's actual B not yet received; with early response on that B never
// reaches a pin) and the consecutive core cycles with WDT_EN set, a write
// outstanding and no AW or B handshake. The watchdog expires when that count
// reaches WDT_THRESHOLD (T), at most once per core reset (I_RESETN or
// AOU_SW_RESET), whatever the W1C or WDT_EN do in between. It only reports:
// the writes stay outstanding.
//   FEAT-R23: the status sets by the (T+1)th such cycle (T = 0: the first).
//   FEAT-R24: it sets only after at least max(T, 1) such cycles.
//   FEAT-R25: once per core reset: no second set before the next one.
//   FEAT-R26: it holds until a W1C of bit 17 or a core reset; a W1C clears it.
//   FEAT-R27: INT_EARLY_WDT_ERR = (OR of the status bits) & ~INT_EARLY_WDT_MASK.
//   FEAT-R28: a read of WRITE_EARLY_RESPONSE_RPn returns the status (bit 17)
//             and WDT_EN (bit 16) of the read's cycle, and WRITE_RESP_DONE
//             (bit 14) = 1 exactly when the model has nothing outstanding.
// Interim expectations where the documents are silent, inferred from the RTL
// (owner question open): "reaches the threshold" is after T or T+1 such cycles (the
// RTL: T+1), T = 0 expires on the first, a threshold lowered below the running
// count expires on the next such cycle, and an expiry in the cycle of a W1C
// leaves the bit set (R26 tolerates it only as a first expiry).
//
// The model holds core state only: it is ignored and cleared while the core is
// in reset (the AXI ports may show handshakes then that the core does not
// count), and an FDI reset leaves it alone, as it leaves the DUT's writes
// outstanding. A B with nothing outstanding (a stray response) is clamped and
// logged; WRITE_RESP_DONE is not checked on that RP until the next core reset.
// The status per RP and the SFR's APB port are white-box taps; the handshakes
// are the early-response controller's ports.
class aou_t1_wdt_chk extends uvm_component;
  `uvm_component_utils(aou_t1_wdt_chk)

  aou_core rm;
  int unsigned n_rp = AOU_T1_RP_COUNT;

  int unsigned s_ev;
  covergroup cg_wdt;
    cp_ev: coverpoint s_ev {
      `AOU_T1_WDT_FC_EV(AOU_FC_CG)
    }
  endgroup
  aou_fc_group fc_wdt;

  protected virtual aou_wdt_if vif;
  protected bit [15:0] addr[4];

  // Model per RP; the *_p values describe the previous core cycle.
  protected int unsigned pend[4];
  protected longint unsigned idle[4];
  protected bit          fired[4];
  protected bit          lost[4];         // missed expiry reported: stop judging
  protected bit          stray[4];        // a B with nothing outstanding since the reset
  protected bit          may_p[4];
  protected bit          must_p[4];
  protected bit          st_p[4];
  protected bit          w1c_p[4];
  protected bit          was_hard;        // the current core reset included I_RESETN
  protected bit          rst_hard;        // the last core reset included I_RESETN
  protected bit          in_rst = 1'b1;
  protected bit          seen_before[4];  // an expiry in an earlier reset epoch
  protected bit          mask_p;
  protected bit          pin_bad;         // FEAT-R27 reported until the pin is right again
  protected bit          multi_p;
  // A read of RPn's register in its setup cycle, judged in its access cycle.
  protected bit          rd_pend;
  protected int unsigned rd_rp;
  protected bit [2:0]    rd_exp;          // {status, WDT_EN, WRITE_RESP_DONE}
  protected bit          rd_done_chk;

  // For the directed test (stimulus only).
  int unsigned n_expiry[4];               // expiries since the start of the test
  int unsigned n_aw_restart[4];           // AW handshakes that restarted a running count
  longint unsigned last_restart_idle[4];  // the count an AW restart cut short

  function new(string name, uvm_component parent);
    aou_fc_db db;
    aou_fc_point p;
    bit fresh;
    super.new(name, parent);
    cg_wdt = new();
    db = aou_fc_db::get();
    fc_wdt = db.group("env.cg_wdt", fresh);
    if (fresh) begin
      p = fc_wdt.cp("cp_ev"); `AOU_T1_WDT_FC_EV(AOU_FC_REG)
    end
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual aou_wdt_if)::get(this, "", "wdt", vif))
      `uvm_fatal(get_type_name(), "no aou_wdt_if under config_db key wdt")
  endfunction

  function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    if (rm == null) `uvm_fatal(get_type_name(), "rm (register model) not set")
    foreach (addr[r]) begin
      uvm_reg rg = rm.get_reg_by_name($sformatf("write_early_response_rp%0d", r));
      if (rg == null) `uvm_fatal(get_type_name(), $sformatf("no write_early_response_rp%0d", r))
      addr[r] = 16'(rg.get_offset());
    end
  endfunction

  // Model state the directed test waits on.
  function bit expired(int unsigned r);
    return fired[r];
  endfunction

  function int unsigned outstanding(int unsigned r);
    return pend[r];
  endfunction

  function longint unsigned idle_count(int unsigned r);
    return idle[r];
  endfunction

  protected function bit early_en(int unsigned r);
    uvm_reg rg = rm.get_reg_by_name($sformatf("write_early_response_rp%0d", r));
    return rg != null && rg.get_field_by_name("early_bresp_en").get_mirrored_value() != 0;
  endfunction

  protected function void sample(int unsigned ev);
    s_ev = ev;
    cg_wdt.sample();
    fc_wdt.sample(int'(ev));
  endfunction

  protected function void clear();
    foreach (pend[r]) begin
      pend[r] = 0;
      idle[r] = 0;
      fired[r] = 1'b0;
      lost[r] = 1'b0;
      stray[r] = 1'b0;
      may_p[r] = 1'b0;
      must_p[r] = 1'b0;
      st_p[r] = 1'b0;
      w1c_p[r] = 1'b0;
    end
    rd_pend = 1'b0;
    mask_p = 1'b0;
    pin_bad = 1'b0;
    multi_p = 1'b0;
  endfunction

  protected function void expiry(int unsigned r, longint unsigned thr, bit mask);
    fired[r] = 1'b1;
    n_expiry[r]++;
    sample(early_en(r) ? 1 : 0);
    sample(thr == 0 ? 2 : (thr < 256 ? 3 : 4));
    if (mask) sample(5);
    sample(13 + r);
    if (seen_before[r]) sample(rst_hard ? 12 : 11);
    `uvm_info(get_type_name(), $sformatf("RP%0d write watchdog expired (T=%0d, %0d outstanding)",
                                         r, thr, pend[r]), UVM_LOW)
  endfunction

  // The status change from the previous core cycle to this one (FEAT-R23 to R26).
  protected function void judge(int unsigned r, bit st, longint unsigned thr, bit mask);
    if (st && !st_p[r]) begin
      aou_rule_log::check("FEAT-R25", get_type_name());
      aou_rule_log::check("FEAT-R24", get_type_name());
      if (fired[r]) begin
        aou_rule_log::fire("FEAT-R25", get_type_name());
        `uvm_error(get_type_name(), $sformatf(
            "FEAT-R25: RP%0d WDT_TRANS_TIMEOUT_ERR set again with no core reset since its expiry",
            r))
      end else begin
        aou_rule_log::check("FEAT-R23", get_type_name());
        if (!may_p[r]) begin
          aou_rule_log::fire("FEAT-R24", get_type_name());
          `uvm_error(get_type_name(), $sformatf(
              {"FEAT-R24: RP%0d WDT_TRANS_TIMEOUT_ERR set after %0d idle cycles with writes ",
               "outstanding (%0d outstanding, WDT_THRESHOLD %0d)"}, r, idle[r], pend[r], thr))
        end
        expiry(r, thr, mask);
      end
    end else if (must_p[r] && !fired[r]) begin
      aou_rule_log::check("FEAT-R23", get_type_name());
      aou_rule_log::fire("FEAT-R23", get_type_name());
      `uvm_error(get_type_name(), $sformatf(
          {"FEAT-R23: RP%0d WDT_TRANS_TIMEOUT_ERR not set after %0d cycles with %0d writes ",
           "outstanding, WDT_EN set and no AW or B handshake (WDT_THRESHOLD %0d)"},
          r, idle[r], pend[r], thr))
      fired[r] = 1'b1;
      lost[r] = 1'b1;
    end else if (!st && st_p[r]) begin
      aou_rule_log::check("FEAT-R26", get_type_name());
      if (!w1c_p[r]) begin
        aou_rule_log::fire("FEAT-R26", get_type_name());
        `uvm_error(get_type_name(), $sformatf(
            "FEAT-R26: RP%0d WDT_TRANS_TIMEOUT_ERR cleared with no W1C and no core reset", r))
      end else if (pend[r] != 0 && vif.mon_cb.en[r] === 1'b1) begin
        sample(8);
      end
    end else if (st && st_p[r] && w1c_p[r]) begin
      aou_rule_log::check("FEAT-R26", get_type_name());
      aou_rule_log::fire("FEAT-R26", get_type_name());
      `uvm_error(get_type_name(), $sformatf(
          "FEAT-R26: RP%0d WDT_TRANS_TIMEOUT_ERR still set after a W1C (or set again by it)", r))
    end
  endfunction

  // This cycle's handshakes and idle count (the model of the timer).
  protected function void step(int unsigned r, bit aw, bit b, bit en, longint unsigned thr);
    bit q = en && pend[r] != 0 && !aw && !b;
    longint unsigned lo = (thr == 0) ? 1 : thr;
    if (aw && en && pend[r] != 0 && !fired[r]) begin
      n_aw_restart[r]++;
      last_restart_idle[r] = idle[r];
      if (thr >= 3 && idle[r] + 3 >= thr && idle[r] < thr) sample(6);
      if (idle[r] == thr && thr != 0) sample(7);
    end
    idle[r] = q ? idle[r] + 1 : 0;
    may_p[r] = q && idle[r] >= lo;
    must_p[r] = q && idle[r] >= thr + 1;
    if (aw && !b) pend[r]++;
    if (b && !aw) begin
      if (pend[r] == 0) begin
        if (!stray[r])
          `uvm_info(get_type_name(), $sformatf(
              "RP%0d: a B with no write outstanding; WRITE_RESP_DONE unchecked until a core reset",
              r), UVM_LOW)
        stray[r] = 1'b1;
      end else begin
        pend[r]--;
      end
    end
  endfunction

  // FEAT-R28: a read of WRITE_EARLY_RESPONSE_RPn, set up in one cycle (the SFR
  // latches its read data then), returned in the access cycle.
  protected function void reads();
    logic [31:0] d;
    bit bad;
    if (rd_pend && vif.mon_cb.psel === 1'b1 && vif.mon_cb.penable === 1'b1 &&
        vif.mon_cb.pready === 1'b1) begin
      d = vif.mon_cb.prdata;
      bad = d[17] !== rd_exp[2] || d[16] !== rd_exp[1] || (rd_done_chk && d[14] !== rd_exp[0]);
      rd_pend = 1'b0;
      aou_rule_log::check("FEAT-R28", get_type_name());
      if (bad) begin
        aou_rule_log::fire("FEAT-R28", get_type_name());
        `uvm_error(get_type_name(), $sformatf(
            {"FEAT-R28: WRITE_EARLY_RESPONSE_RP%0d read 0x%08h: WDT_TRANS_TIMEOUT_ERR %0b ",
             "WDT_EN %0b WRITE_RESP_DONE %0b, expected %0b %0b %s"}, rd_rp, d, d[17], d[16],
            d[14], rd_exp[2], rd_exp[1], rd_done_chk ? $sformatf("%0b", rd_exp[0]) : "(any)"))
      end
    end
    if (vif.mon_cb.psel === 1'b1 && vif.mon_cb.penable === 1'b0 && vif.mon_cb.pwrite === 1'b0)
      foreach (addr[r])
        if (vif.mon_cb.paddr === addr[r]) begin
          rd_pend = 1'b1;
          rd_rp = r;
          rd_exp = {vif.mon_cb.status[r] === 1'b1, vif.mon_cb.en[r] === 1'b1, pend[r] == 0};
          rd_done_chk = r < n_rp && !stray[r];
        end
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      bit [3:0] st;
      bit any;
      int unsigned n_set;
      longint unsigned thr;
      @(vif.mon_cb);
      if (vif.mon_cb.core_rst_n !== 1'b1) begin
        if (!in_rst) begin
          clear();
          was_hard = 1'b0;
        end
        in_rst = 1'b1;
        if (vif.mon_cb.rst_n !== 1'b1) was_hard = 1'b1;
        continue;
      end
      if (in_rst) begin
        // Out of a core reset: the RPs that expired before it may expire again.
        foreach (fired[r]) if (n_expiry[r] != 0) seen_before[r] = 1'b1;
        rst_hard = was_hard;
        clear();
        in_rst = 1'b0;
      end
      st = vif.mon_cb.status;
      thr = longint'(vif.mon_cb.thr);
      for (int unsigned r = 0; r < 4; r++) begin
        if (!lost[r]) judge(r, st[r], thr, vif.mon_cb.mask === 1'b1);
        st_p[r] = st[r];
      end
      reads();
      // FEAT-R27: the pin, every cycle out of reset.
      any = |st;
      aou_rule_log::check("FEAT-R27", get_type_name());
      if (vif.mon_cb.pin !== (any && vif.mon_cb.mask !== 1'b1)) begin
        if (!pin_bad) begin
          aou_rule_log::fire("FEAT-R27", get_type_name());
          `uvm_error(get_type_name(), $sformatf(
              "FEAT-R27: INT_EARLY_WDT_ERR %0b with WDT_TRANS_TIMEOUT_ERR %4b and the mask %0b",
              vif.mon_cb.pin, st, vif.mon_cb.mask))
        end
        pin_bad = 1'b1;
      end else begin
        pin_bad = 1'b0;
      end
      if (any && mask_p && vif.mon_cb.mask !== 1'b1) sample(9);
      mask_p = vif.mon_cb.mask === 1'b1;
      n_set = $countones(st);
      if (n_set >= 2 && !multi_p) sample(10);
      multi_p = n_set >= 2;
      for (int unsigned r = 0; r < 4; r++) begin
        w1c_p[r] = vif.mon_cb.psel === 1'b1 && vif.mon_cb.penable === 1'b0 &&
                   vif.mon_cb.pwrite === 1'b1 && vif.mon_cb.paddr === addr[r] &&
                   vif.mon_cb.pwdata[17] === 1'b1;
        step(r, vif.mon_cb.aw_hs[r] === 1'b1, vif.mon_cb.b_hs[r] === 1'b1,
             vif.mon_cb.en[r] === 1'b1, thr);
      end
    end
  endtask

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    foreach (n_expiry[r])
      if (n_expiry[r] != 0 || n_aw_restart[r] != 0)
        `uvm_info(get_type_name(), $sformatf(
            "RP%0d write watchdog: %0d expiries, %0d AW restarts of a running count", r,
            n_expiry[r], n_aw_restart[r]), UVM_LOW)
  endfunction
endclass

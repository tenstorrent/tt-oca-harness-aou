// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// The local die's software as the MAS describes it (software-operation 7.3.5):
// on INT_ACTIVATE_START it sets AOU_INIT.ACTIVATE_START and, once the DUT is
// ENABLED, clears the interrupt; on INT_DEACTIVATE_START it sets
// DEACTIVATE_START and clears the interrupt once DISABLED. This is what lets
// the remote die start activation or deactivation on its own. enable = 0
// leaves the interrupts to the test.
// Before DEACTIVATE_START (quiesce(), also used when the test itself starts a
// deactivation) software stops its AXI managers from issuing new requests
// until DISABLED; requests already issued complete normally. 7.3.5 asks for
// that with CREDIT_MANAGE = 0; with CREDIT_MANAGE = 1 software may keep
// issuing but sets DEACTIVATE_START only "once all messages have been sent",
// so it also waits until no request is part-way onto the bus.
// drain_before_deact also waits for every response first (7.3.3: software
// that guarantees this may shorten DEACTIVATE_TIME_OUT_VALUE; AoU 8.3.2
// option 1). hold_on_deact = 0 breaks the rule on purpose (negative tests).
// The wait for the new state is bounded (state_timeout cycles) and ends early
// when INT_REQ_LINKRESET rises or the env cancels it (cancel(), on every
// reset); the interrupt is then left for whoever recovers the link. After a
// time-out alone the interrupt stays pending, and since it can only rise
// again once cleared, software still clears it when the state arrives later
// by another path (the test's own activation, say), as 7.3.5 asks.
class aou_t1_sw_isr extends uvm_component;
  `uvm_component_utils(aou_t1_sw_isr)

  aou_t1_status     status;
  aou_core          rm;
  aou_apb_sequencer apb_sqr;
  aou_axi_mgr_driver mgr[];     // the local AXI managers software controls
  bit               enable = 1'b1;
  bit               hold_on_deact = 1'b1;
  bit               drain_before_deact = 1'b0;
  bit               held = 1'b0;
  int unsigned      state_timeout = 20000;
  int unsigned      n_act;
  int unsigned      n_deact;
  int unsigned      n_cancelled;
  int unsigned      busy;       // interrupts being serviced
  uvm_event         idle_ev;

  protected int unsigned gen;   // bumped by cancel()
  protected bit          ok_r[2]; // wait_state() result per service kind
  protected bit          tmo_r[2]; // wait_state() ended on state_timeout alone

  function new(string name, uvm_component parent);
    super.new(name, parent);
    idle_ev = new("idle_ev");
  endfunction

  // Returns once no interrupt is being serviced. While INT_DEACTIVATE_START
  // is pending the DUT's bringup controller takes the link down again, so
  // activation waits for this.
  task wait_idle();
    while (busy != 0) idle_ev.wait_trigger();
  endtask

  // Abandons any service in progress at its next wait (after a reset or a
  // LinkReset the state it waits for may never come).
  function void cancel();
    gen++;
  endfunction

  // Stops (on = 1) or resumes new requests from every local AXI manager.
  function void hold_requests(bit on);
    if (on != held)
      `uvm_info(get_type_name(), on ? "local managers: no new requests" :
                "local managers: issuing again", UVM_MEDIUM)
    held = on;
    foreach (mgr[r]) if (mgr[r] != null) mgr[r].hold_new = on;
  endfunction

  protected function int unsigned count_reqs(bit answered);
    int unsigned n = 0;
    foreach (mgr[r])
      if (mgr[r] != null) n += answered ? mgr[r].issued() : mgr[r].issuing();
    return n;
  endfunction

  // Software's part before it sets DEACTIVATE_START (see the header). Bounded
  // by state_timeout; a reset or LinkReset ends the wait.
  task quiesce();
    int unsigned g = gen;
    int unsigned n = 0;
    bit cm = 1'(rm.aou_con0.credit_manage.get_mirrored_value());
    if (!hold_on_deact) begin
      `uvm_info(get_type_name(),
                "hold_on_deact=0: requests keep issuing (MAS 7.3.5 broken on purpose)", UVM_LOW)
      return;
    end
    hold_requests(1'b1);
    while ((drain_before_deact && count_reqs(1'b1) != 0) || (cm && count_reqs(1'b0) != 0)) begin
      @(status.vif.mon_cb);
      if (g != gen || status.vif.mon_cb.int_req_linkreset === 1'b1) return;
      if (++n >= state_timeout) begin
        `uvm_info(get_type_name(), $sformatf("quiesce: %0d request(s) open after %0d cycles",
                                             count_reqs(drain_before_deact), n), UVM_LOW)
        return;
      end
    end
  endtask

  protected function void done();
    busy--;
    idle_ev.trigger();
  endfunction

  task write_field(uvm_reg_field f, uvm_reg_data_t value);
    aou_t1_field_seq s = aou_t1_field_seq::type_id::create("s");
    s.rm = rm;
    s.apb_sqr = apb_sqr;
    s.f = f;
    s.value = value;
    s.start(null);
  endtask

  // Waits for ENABLED (en=1) or DISABLED; ok_r[en] = 0 when cancelled, on
  // INT_REQ_LINKRESET or after state_timeout cycles.
  protected task wait_state(bit en, int unsigned g);
    int unsigned n = 0;
    ok_r[en] = 1'b1;
    tmo_r[en] = 1'b0;
    while ((en ? status.enabled : status.disabled) != 1'b1) begin
      @(status.vif.mon_cb);
      if (g != gen || status.vif.mon_cb.int_req_linkreset === 1'b1 || ++n >= state_timeout) begin
        ok_r[en] = 1'b0;
        tmo_r[en] = g == gen && status.vif.mon_cb.int_req_linkreset !== 1'b1;
        break;
      end
    end
  endtask

  // Clears the interrupt a timed-out service left pending once its state
  // arrives; a reset or LinkReset recovery (cancel()) ends the wait.
  protected task late_clear(bit act, int unsigned g);
    while ((act ? status.enabled : status.disabled) != 1'b1) begin
      @(status.vif.mon_cb);
      if (g != gen) return;
    end
    `uvm_info(get_type_name(), $sformatf("%s: state reached late, clearing the interrupt",
              act ? "INT_ACTIVATE_START" : "INT_DEACTIVATE_START"), UVM_LOW)
    write_field(act ? rm.aou_init.int_activate_start : rm.aou_init.int_deactivate_start, 1);
  endtask

  protected task service(bit act);
    int unsigned g = gen;
    busy++;
    if (act) n_act++;
    else n_deact++;
    if (!act) quiesce();
    if (g == gen) begin
      `uvm_info(get_type_name(), $sformatf("%s: setting %s",
                act ? "INT_ACTIVATE_START" : "INT_DEACTIVATE_START",
                act ? "ACTIVATE_START" : "DEACTIVATE_START"), UVM_LOW)
      write_field(act ? rm.aou_init.activate_start : rm.aou_init.deactivate_start, 1);
    end
    wait_state(act, g);
    // Requests issued from here on wake the link again (7.3.5 INT_ACTIVATE_START
    // condition 2, 7.3.6).
    if (!act) hold_requests(1'b0);
    if (ok_r[act]) begin
      write_field(act ? rm.aou_init.int_activate_start : rm.aou_init.int_deactivate_start, 1);
    end else begin
      n_cancelled++;
      `uvm_info(get_type_name(), $sformatf("%s service abandoned (reset, LinkReset or time-out)",
                act ? "INT_ACTIVATE_START" : "INT_DEACTIVATE_START"), UVM_LOW)
      if (tmo_r[act])
        fork
          late_clear(act, g);
        join_none
    end
    done();
  endtask

  task run_phase(uvm_phase phase);
    fork
      forever begin
        status.act_start_ev.wait_trigger();
        if (enable) service(1'b1);
      end
      forever begin
        status.deact_start_ev.wait_trigger();
        if (enable) service(1'b0);
      end
    join
  endtask
endclass

// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// The remote die's protocol layer as a UVM component.
//   rx_flit_imp    <- L1 monitor ap_tx: flits the DUT sent (after cancel rollback)
//   tx_flit_export -> pulled by L1's driver side: the next flit to the DUT
//   ap_rx_msg      -> decoded DUT messages (every type, Misc included)
//   ap_tx_msg      -> messages the model put into a flit
//   ap_tx_flit     -> flits handed to L1
// send(aou_msg) queues a message; credits, packing and activation are L3's.
// DUT WriteReq/WriteData/ReadReq go to cfg.l4a and the responses come back
// through the packer.
class aou_l3_agent extends uvm_component;
  `uvm_component_utils(aou_l3_agent)

  aou_l3_cfg        cfg;
  aou_l3_model      model;
  aou_l3_sequencer  sqr;
  aou_l3_msg_driver drv;

  uvm_analysis_imp #(aou_l3_flit_item, aou_l3_agent)     rx_flit_imp;
  uvm_blocking_get_imp #(aou_l3_flit_item, aou_l3_agent) tx_flit_export;
  uvm_analysis_port #(aou_msg)                           ap_rx_msg;
  uvm_analysis_port #(aou_msg)                           ap_tx_msg;
  uvm_analysis_port #(aou_l3_flit_item)                  ap_tx_flit;

  aou_msg_wreq      wreq_q[AOU_RP_MAX][$];
  aou_msg_wdata     wdata_q[AOU_RP_MAX][$];
  aou_l3_wr_txn     wr_ready[AOU_RP_MAX][$];
  aou_msg_rreq      rd_ready[AOU_RP_MAX][$];
  // Bumped whenever a responder may proceed. A uvm_event re-armed and triggered
  // again in one time slot loses the second trigger on Verilator (a write worker
  // slept through its WriteReq's last WriteData); a count and a level wait cannot.
  int unsigned      resp_gen;
  int unsigned      ticket_next[int];
  int unsigned      ticket_serve[int];
  int unsigned      rd_tickets[AOU_RP_MAX][$];
  int unsigned      writes_done;
  int unsigned      reads_done;
  bit               warned_no_l4a;
  int unsigned      resp_epoch;   // bumped by reset_flush(); older responses are dropped

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (cfg == null && !uvm_config_db#(aou_l3_cfg)::get(this, "", "cfg", cfg))
      cfg = aou_l3_cfg::type_id::create("cfg");
    model = aou_l3_model::type_id::create("model");
    model.name_tag = get_name();
    model.build(cfg);
    sqr = aou_l3_sequencer::type_id::create("sqr", this);
    drv = aou_l3_msg_driver::type_id::create("drv", this);
    rx_flit_imp = new("rx_flit_imp", this);
    tx_flit_export = new("tx_flit_export", this);
    ap_rx_msg = new("ap_rx_msg", this);
    ap_tx_msg = new("ap_tx_msg", this);
    ap_tx_flit = new("ap_tx_flit", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    drv.seq_item_port.connect(sqr.seq_item_export);
    drv.model = model;
    sqr.model = model;
  endfunction

  // ---- API -------------------------------------------------------------
  function void send(aou_msg m);
    model.send(m);
  endfunction

  task activate();
    model.activate();
  endtask

  task deactivate();
    model.deactivate();
  endtask

  task wait_state(aou_link_state_e s);
    model.lnk.wait_state(s);
  endtask

  // Reset contract: the link was reset. The model drops its queues, buffer
  // and credits (recover()), and requests the responder still holds or is
  // serving get no response.
  function void reset_flush();
    resp_epoch++;
    for (int r = 0; r < AOU_RP_MAX; r++) begin
      wreq_q[r].delete();
      wdata_q[r].delete();
      wr_ready[r].delete();
      rd_ready[r].delete();
      rd_tickets[r].delete();
    end
    ticket_next.delete();
    ticket_serve.delete();
    model.recover();
    resp_gen++;
  endfunction

  // ---- L1 boundary -----------------------------------------------------
  function void write(aou_l3_flit_item it);
    model.rx_flit(it.to_flit());
  endfunction

  task get(output aou_l3_flit_item it);
    aou_flit f;
    model.get_tx_flit(f);
    it = aou_l3_flit_item::type_id::create("it");
    it.from_flit(f);
    while (model.tx_sent_q.size() > 0) ap_tx_msg.write(model.tx_sent_q.pop_front());
    model.tx_flit_q.delete();
    ap_tx_flit.write(it);
  endtask

  // ---- Responder -------------------------------------------------------
  task run_phase(uvm_phase phase);
    for (int r = 0; r < AOU_RP_MAX; r++) begin
      automatic int rr = r;
      fork
        write_worker(rr);
        read_worker(rr);
      join_none
    end
    forever begin
      aou_msg m;
      while (model.rx_q.size() == 0) model.rx_ev.wait_trigger();
      m = model.rx_q.pop_front();
      ap_rx_msg.write(m);
      route(m);
    end
  endtask

  function bit responder_on();
    if (cfg.l4a != null) return 1'b1;
    if (!warned_no_l4a) begin
      `uvm_info(get_type_name(), "no L4a model: DUT requests are consumed without a response",
                UVM_LOW)
      warned_no_l4a = 1'b1;
    end
    return 1'b0;
  endfunction

  function void route(aou_msg m);
    aou_msg_wreq wq;
    aou_msg_wdata wd;
    aou_msg_rreq rq;
    if (m.cred_class() == AOU_CC_NONE) return;
    if (m.msg_type inside {AOU_MT_WRESP, AOU_MT_RDATA}) begin
      model.consume(m);
      return;
    end
    if (!responder_on()) begin
      model.consume(m);
      return;
    end
    if ($cast(wq, m)) begin
      wreq_q[m.rp].push_back(wq);
      match_writes(int'(m.rp));
    end else if ($cast(wd, m)) begin
      wdata_q[m.rp].push_back(wd);
      match_writes(int'(m.rp));
    end else if ($cast(rq, m)) begin
      rd_tickets[m.rp].push_back(take_ticket(1, int'(rq.rp), rq.id));
      rd_ready[m.rp].push_back(rq);
      resp_gen++;
    end
  endfunction

  function int unsigned take_ticket(int kind, int unsigned rp, bit [9:0] id);
    int key = kind * 4096 + int'(rp) * 1024 + int'(id);
    int unsigned t = ticket_next.exists(key) ? ticket_next[key] : 0;
    ticket_next[key] = t + 1;
    return t;
  endfunction

  // AXI4 has no write interleaving: WriteData follows WriteReq order per RP.
  function void match_writes(int unsigned rp);
    while (wreq_q[rp].size() > 0 && wdata_q[rp].size() >= int'(wreq_q[rp][0].len) + 1) begin
      aou_l3_wr_txn t = aou_l3_wr_txn::type_id::create("t");
      t.req = wreq_q[rp].pop_front();
      for (int unsigned i = 0; i <= t.req.len; i++) t.beats.push_back(wdata_q[rp].pop_front());
      t.ticket = take_ticket(0, rp, t.req.id);
      wr_ready[rp].push_back(t);
      resp_gen++;
    end
  endfunction

  task write_worker(int rp);
    forever begin
      aou_l3_wr_txn t;
      while (wr_ready[rp].size() == 0) wait_resp(resp_gen);
      t = wr_ready[rp].pop_front();
      if (cfg.resp_fork) begin
        fork
          serve_write(t);
        join_none
      end else begin
        serve_write(t);
      end
    end
  endtask

  task read_worker(int rp);
    forever begin
      aou_msg_rreq rq;
      int unsigned t;
      while (rd_ready[rp].size() == 0) wait_resp(resp_gen);
      rq = rd_ready[rp].pop_front();
      t = rd_tickets[rp].pop_front();
      if (cfg.resp_fork) begin
        fork
          serve_read(rq, t);
        join_none
      end else begin
        serve_read(rq, t);
      end
    end
  endtask

  task wait_resp(int unsigned seen);
    wait (resp_gen != seen);
  endtask

  task wait_turn(int kind, int unsigned rp, bit [9:0] id, int unsigned t, int unsigned epoch);
    int key = kind * 4096 + int'(rp) * 1024 + int'(id);
    while ((ticket_serve.exists(key) ? ticket_serve[key] : 0) != t && epoch == resp_epoch)
      wait_resp(resp_gen);
  endtask

  function void end_turn(int kind, int unsigned rp, bit [9:0] id);
    int key = kind * 4096 + int'(rp) * 1024 + int'(id);
    ticket_serve[key] = (ticket_serve.exists(key) ? ticket_serve[key] : 0) + 1;
    resp_gen++;
  endfunction

  // Dequeueing from the modelled RX buffer is the handover to L4a (MAS 3.9).
  task serve_write(aou_l3_wr_txn t);
    bit [1:0] bresp;
    aou_msg_wresp b;
    int unsigned epoch = resp_epoch;
    model.consume(t.req);
    foreach (t.beats[i]) model.consume(t.beats[i]);
    cfg.l4a.handle_write(t.req, t.beats, bresp);
    wait_turn(0, int'(t.req.rp), t.req.id, t.ticket, epoch);
    if (epoch != resp_epoch) return;
    b = aou_msg_wresp::type_id::create("b");
    b.rp = cfg.dest_rp[t.req.rp];
    b.id = t.req.id;
    b.resp = bresp;
    model.send(b);
    writes_done++;
    end_turn(0, int'(t.req.rp), t.req.id);
  endtask

  task serve_read(aou_msg_rreq rq, int unsigned t);
    bit [1023:0] data[$];
    bit [1:0] resp[$];
    int unsigned epoch = resp_epoch;
    model.consume(rq);
    cfg.l4a.handle_read(rq, data, resp);
    wait_turn(1, int'(rq.rp), rq.id, t, epoch);
    if (epoch != resp_epoch) return;
    foreach (data[i]) begin
      aou_msg_rdata d = aou_msg_rdata::type_id::create("d");
      d.rp = cfg.dest_rp[rq.rp];
      d.id = rq.id;
      d.dlength = aou_dl_for_size(rq.size);
      d.data = data[i];
      d.resp = (i < resp.size()) ? resp[i] : 2'b00;
      d.last = (i == data.size() - 1);
      model.send(d);
      if (cfg.rdata_ilv && !d.last) begin
        int unsigned f0 = model.tx_flits;
        wait (model.tx_flits != f0 || epoch != resp_epoch);
        if (epoch != resp_epoch) return;
      end
    end
    reads_done++;
    end_turn(1, int'(rq.rp), rq.id);
  endtask

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    model.check_end();
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info(get_type_name(), $sformatf(
              "%s: state=%s tx flits/msgs=%0d/%0d rx flits/msgs=%0d/%0d wr=%0d rd=%0d rules:%s",
              get_full_name(), model.lnk.state.name(), model.tx_flits, model.tx_msgs,
              model.rx_flits, model.rx_msgs, writes_done, reads_done, cfg.chk.summary()), UVM_LOW)
  endfunction
endclass

// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// L4a: the remote die's AXI subordinate. execute() performs one decoded request
// on cfg.mem (a write on arrival, a read's data after r_lat cycles) and returns
// the response after cfg.timing.b_lat (writes) or r_lat (reads) cycles.
// Calls may overlap (fork one per request): responses come back
// out of order across IDs and in call order within an ID, separately for reads
// and writes. Every response is also published on ap with local_side = 0.
// Cycles are counted on cfg.vif's mon_cb; vif is needed only for nonzero latency
// or same-ID waits.
class aou_remote_axi_model extends uvm_component;
  `uvm_component_utils(aou_remote_axi_model)

  aou_axi_cfg cfg;
  uvm_analysis_port #(aou_axi_txn) ap;

  int unsigned n_wr;
  int unsigned n_rd;

  protected aou_axi_vif_t vif;
  protected int unsigned wr_next[bit [9:0]];
  protected int unsigned wr_serve[bit [9:0]];
  protected int unsigned rd_next[bit [9:0]];
  protected int unsigned rd_serve[bit [9:0]];
  protected int unsigned n_active;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (cfg == null && !uvm_config_db#(aou_axi_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal(get_type_name(), "no aou_axi_cfg under config_db key cfg")
    if (cfg.vif == null && cfg.vif_key != "" &&
        !uvm_config_db#(virtual aou_axi_bus_if #(.DATA_W(1024)))::get(this, "", cfg.vif_key,
                                                                       cfg.vif))
      `uvm_fatal(get_type_name(), $sformatf("no aou_axi_bus_if under config_db key '%s'",
                                            cfg.vif_key))
    if (cfg.mem == null) cfg.mem = aou_mem::type_id::create("mem");
    vif = cfg.vif;
    ap  = new("ap", this);
  endfunction

  function int unsigned outstanding();
    return n_active;
  endfunction

  // req: a request without response fields; a write carries data[] and strb[]
  // with one entry per beat in bus-aligned lanes of req.data_bytes. rsp is a
  // copy of req with bresp, or with data[] and rresp[] for every beat.
  task execute(aou_axi_txn req, output aou_axi_txn rsp);
    int unsigned ticket;
    bit [9:0] id = req.id;
    bit is_wr = (req.dir == AOU_AXI_WR);
    n_active++;
    if (!$cast(rsp, req.clone())) `uvm_fatal(get_type_name(), "clone failed")
    rsp.local_side = 1'b0;
    if (is_wr) begin
      if (!wr_next.exists(id)) begin
        wr_next[id]  = 0;
        wr_serve[id] = 0;
      end
      ticket = wr_next[id]++;
      // The write lands on memory, and the exclusive monitor is evaluated, in
      // arrival order, as a subordinate does once it has accepted AW and W;
      // only the B is delayed. Performing it after b_lat let two writes to the
      // same address with different IDs land in random order, so an exclusive
      // write could win over an ordinary write issued before it.
      if (req.data.size() != req.beats() || req.strb.size() != req.beats())
        `uvm_error(get_type_name(), $sformatf("write request needs %0d data/strb beats: %s",
                                              req.beats(), req.convert2string()))
      else rsp.bresp = cfg.mem.axi_write(rsp, cfg.exclusive_en);
      wait_cycles(cfg.timing.b_lat.next());
      while (wr_serve[id] != ticket) wait_cycles(1);
      wr_serve[id]++;
      n_wr++;
    end else begin
      if (!rd_next.exists(id)) begin
        rd_next[id]  = 0;
        rd_serve[id] = 0;
      end
      ticket = rd_next[id]++;
      cfg.mem.axi_read_start(rsp, cfg.exclusive_en);
      wait_cycles(cfg.timing.r_lat.next());
      while (rd_serve[id] != ticket) wait_cycles(1);
      rsp.data  = new[rsp.beats()];
      rsp.rresp = new[rsp.beats()];
      rsp.strb.delete();
      for (int unsigned i = 0; i < rsp.beats(); i++) begin
        rsp.data[i]  = cfg.mem.read_beat(rsp, i);
        rsp.rresp[i] = cfg.mem.axi_read_resp(rsp, i, cfg.exclusive_en);
      end
      rd_serve[id]++;
      n_rd++;
    end
    rsp.t_done = $time;
    n_active--;
    ap.write(rsp);
  endtask

  protected task wait_cycles(int unsigned n);
    if (n == 0) return;
    if (vif == null) `uvm_fatal(get_type_name(), "nonzero latency needs cfg.vif or cfg.vif_key")
    repeat (n) @(vif.mon_cb);
  endtask

  function void check_phase(uvm_phase phase);
    if (n_active != 0)
      `uvm_error(get_type_name(), $sformatf("%0d requests still executing at end of test",
                                            n_active))
  endfunction
endclass

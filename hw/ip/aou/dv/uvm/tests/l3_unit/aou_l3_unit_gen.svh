// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Unit-test traffic through one L3 agent: writes to its own address region
// of the peer's memory, then reads every write back and compares the bytes.
// Data widths, WriteData vs WriteDataFull, strobes, RPs and IDs are random.
// RPs are the agent's own planes: a request carries cfg.dest_rp[plane] and its
// response comes back on the plane (MAS 3.10.2, symmetric maps).
class aou_l3_unit_gen extends uvm_component;
  `uvm_component_utils(aou_l3_unit_gen)

  uvm_analysis_imp #(aou_msg, aou_l3_unit_gen) rsp_imp;
  aou_l3_agent agt;
  int unsigned n_txn = 16;
  int unsigned rp_count = 4;
  bit [63:0]   base = 64'h0;

  bit [7:0]    shadow[bit [63:0]];
  bit [1023:0] exp_beats[int][$];
  int unsigned exp_bus[int][$];
  int unsigned wr_sent, wr_done, rd_sent, rd_done, beats_ok, mismatches;
  uvm_event    rsp_ev;

  bit [63:0]   wr_addr[$];
  bit [2:0]    wr_size[$];
  bit [7:0]    wr_len[$];
  bit [1:0]    wr_rp[$];

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    rsp_imp = new("rsp_imp", this);
    rsp_ev = new("rsp_ev");
  endfunction

  function void write(aou_msg m);
    aou_msg_rdata rd;
    if (m.msg_type == AOU_MT_WRESP) begin
      wr_done++;
      rsp_ev.trigger();
    end else if ($cast(rd, m)) begin
      int key = int'(rd.rp) * 1024 + int'(rd.id);
      if (!exp_beats.exists(key) || exp_beats[key].size() == 0) begin
        `uvm_error(get_type_name(), $sformatf("unexpected %s", rd.convert2string()))
        return;
      end
      begin
        bit [1023:0] e = exp_beats[key].pop_front();
        int unsigned bus = exp_bus[key].pop_front();
        bit [1023:0] mask = '0;
        for (int unsigned j = 0; j < bus * 8; j++) mask[j] = 1'b1;
        if ((rd.data & mask) != (e & mask)) begin
          mismatches++;
          `uvm_error(get_type_name(), $sformatf("read data mismatch rp%0d id %0h: got %0h exp %0h",
                                                rd.rp, rd.id, rd.data[63:0], e[63:0]))
        end else begin
          beats_ok++;
        end
      end
      if (rd.last) begin
        rd_done++;
        rsp_ev.trigger();
      end
    end
  endfunction

  static function bit [7:0] init_byte(bit [63:0] a);
    return a[7:0];
  endfunction

  task do_write(int unsigned i);
    aou_msg_wreq rq = aou_msg_wreq::type_id::create("rq");
    bit [1:0] dl = 2'($urandom_range(0, 2));
    int unsigned bus = aou_dl_bits(dl) / 8;
    bit [1:0] plane = 2'($urandom_range(0, rp_count - 1));
    rq.rp = agt.cfg.dest_rp[plane];
    rq.id = 10'($urandom_range(0, 15));
    rq.size = 3'($clog2(bus));
    rq.len = 8'($urandom_range(0, 3));
    rq.addr = base + i * 64'h1000;
    rq.cache = 4'($urandom);
    rq.prot = 3'($urandom);
    rq.qos = 4'($urandom);
    agt.send(rq);
    for (int unsigned b = 0; b <= rq.len; b++) begin
      aou_msg_wdata w = aou_msg_wdata::type_id::create("w");
      bit [63:0] a = rq.addr + b * bus;
      w.rp = rq.rp;
      w.dlength = dl;
      w.set_full(1'($urandom_range(0, 1)));
      for (int unsigned j = 0; j < bus; j++) begin
        w.data[8*j +: 8] = 8'($urandom);
        w.strb[j] = w.full() ? 1'b1 : 1'($urandom);
        if (w.strb[j]) shadow[a + 64'(j)] = w.data[8*j +: 8];
      end
      agt.send(w);
    end
    wr_addr.push_back(rq.addr);
    wr_size.push_back(rq.size);
    wr_len.push_back(rq.len);
    wr_rp.push_back(plane);
    wr_sent++;
  endtask

  task do_read(int unsigned i);
    aou_msg_rreq rq = aou_msg_rreq::type_id::create("rq");
    int unsigned bus = 1 << wr_size[i];
    int key;
    rq.rp = agt.cfg.dest_rp[wr_rp[i]];
    rq.id = 10'($urandom_range(0, 15));
    rq.size = wr_size[i];
    rq.len = wr_len[i];
    rq.addr = wr_addr[i];
    key = int'(wr_rp[i]) * 1024 + int'(rq.id);
    for (int unsigned b = 0; b <= rq.len; b++) begin
      bit [1023:0] e = '0;
      bit [63:0] a = rq.addr + b * bus;
      for (int unsigned j = 0; j < bus; j++)
        e[8*j +: 8] = shadow.exists(a + 64'(j)) ? shadow[a + 64'(j)] : init_byte(a + 64'(j));
      exp_beats[key].push_back(e);
      exp_bus[key].push_back(bus);
    end
    agt.send(rq);
    rd_sent++;
  endtask

  task run_traffic();
    for (int unsigned i = 0; i < n_txn; i++) do_write(i);
    while (wr_done < wr_sent) rsp_ev.wait_trigger();
    for (int unsigned i = 0; i < n_txn; i++) do_read(i);
    while (rd_done < rd_sent) rsp_ev.wait_trigger();
  endtask
endclass

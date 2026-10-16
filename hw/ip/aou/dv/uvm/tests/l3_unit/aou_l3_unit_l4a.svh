// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Minimal L4a for unit tests: a sparse byte memory behind aou_l4a_if_c with
// a random response latency counted in clocks. Unwritten bytes read as the
// low byte of their address.
class aou_l3_unit_l4a extends aou_l4a_if_c;
  `uvm_object_utils(aou_l3_unit_l4a)

  virtual aou_l3_unit_if vif;
  bit [7:0]    mem[bit [63:0]];
  int unsigned max_lat = 6;
  int unsigned writes;
  int unsigned reads;

  function new(string name = "aou_l3_unit_l4a");
    super.new(name);
  endfunction

  task lat();
    repeat ($urandom_range(0, max_lat)) @(vif.drv_cb);
  endtask

  static function bit [7:0] init_byte(bit [63:0] a);
    return a[7:0];
  endfunction

  virtual task handle_write(input aou_msg_wreq req, input aou_msg_wdata data[$],
                            output bit [1:0] bresp);
    lat();
    foreach (data[i]) begin
      int unsigned bus = aou_dl_bits(data[i].dlength) / 8;
      bit [63:0] a = req.addr + i * (64'd1 << req.size);
      bit [63:0] base = a & ~64'(bus - 1);
      for (int unsigned j = 0; j < bus; j++) begin
        if (data[i].strb[j]) mem[base + 64'(j)] = data[i].data[8*j +: 8];
      end
    end
    writes++;
    bresp = 2'b00;
  endtask

  virtual task handle_read(input aou_msg_rreq req, output bit [1023:0] data[$],
                           output bit [1:0] resp[$]);
    int unsigned bus = aou_dl_bits(aou_dl_for_size(req.size)) / 8;
    lat();
    data.delete();
    resp.delete();
    for (int unsigned i = 0; i <= req.len; i++) begin
      bit [63:0] a = req.addr + i * (64'd1 << req.size);
      bit [63:0] base = a & ~64'(bus - 1);
      bit [1023:0] d = '0;
      for (int unsigned j = 0; j < bus; j++)
        d[8*j +: 8] = mem.exists(base + 64'(j)) ? mem[base + 64'(j)] : init_byte(base + 64'(j));
      data.push_back(d);
      resp.push_back(2'b00);
    end
    reads++;
  endtask
endclass

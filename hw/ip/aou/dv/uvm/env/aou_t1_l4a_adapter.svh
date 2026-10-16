// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// L3's responder callback over the remote AXI model: a DUT WriteReq/WriteData
// or ReadReq becomes an aou_axi_txn on remote.execute(). Data travels in the
// lanes of a bus as wide as the message's DLENGTH (WriteData: as sent;
// ReadData: from ARSIZE, spec §5.7), so that is the txn's data_bytes.
class aou_t1_l4a_adapter extends aou_l4a_if_c;
  `uvm_object_utils(aou_t1_l4a_adapter)

  aou_remote_axi_model remote;
  int unsigned         n_wr;
  int unsigned         n_rd;

  function new(string name = "aou_t1_l4a_adapter");
    super.new(name);
  endfunction

  function aou_axi_txn mk(aou_msg_req req, aou_axi_dir_e dir, int unsigned bus);
    aou_axi_txn t = aou_axi_txn::type_id::create("l4a");
    t.dir = dir;
    t.rp = int'(req.rp);
    t.local_side = 1'b0;
    t.id = req.id;
    t.addr = req.addr;
    t.len = req.len;
    t.size = req.size;
    t.burst = AOU_AXI_INCR;
    t.lock = req.lock;
    t.cache = req.cache;
    t.prot = req.prot;
    t.qos = req.qos;
    t.data_bytes = bus;
    return t;
  endfunction

  virtual task handle_write(input aou_msg_wreq req, input aou_msg_wdata data[$],
                            output bit [1:0] bresp);
    aou_axi_txn t;
    aou_axi_txn rsp;
    int unsigned bus = (data.size() > 0) ? aou_dl_bits(data[0].dlength) / 8 : 32;
    t = mk(req, AOU_AXI_WR, bus);
    t.data = new[data.size()];
    t.strb = new[data.size()];
    foreach (data[i]) begin
      if (aou_dl_bits(data[i].dlength) / 8 != bus)
        `uvm_error(get_type_name(), $sformatf(
                   "T1-L4A01: WriteData DLENGTH changes within a burst (beat %0d: %0d bits)", i,
                   aou_dl_bits(data[i].dlength)))
      t.data[i] = data[i].data;
      t.strb[i] = data[i].strb & ({128{1'b1}} >> (128 - bus));
    end
    remote.execute(t, rsp);
    bresp = rsp.bresp;
    n_wr++;
  endtask

  virtual task handle_read(input aou_msg_rreq req, output bit [1023:0] data[$],
                           output bit [1:0] resp[$]);
    aou_axi_txn t;
    aou_axi_txn rsp;
    t = mk(req, AOU_AXI_RD, aou_dl_bits(aou_dl_for_size(req.size)) / 8);
    remote.execute(t, rsp);
    data.delete();
    resp.delete();
    foreach (rsp.data[i]) begin
      data.push_back(rsp.data[i]);
      resp.push_back(rsp.rresp[i]);
    end
    n_rd++;
  endtask
endclass

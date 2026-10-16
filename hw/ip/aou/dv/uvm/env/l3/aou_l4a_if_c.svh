// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// What L3's protocol responder needs from L4a (the remote die's AXI side).
// L4a's aou_remote_axi_model extends this. L3 hands over a DUT request with
// its data, the call may consume time (L4a owns the clock), and L3 sends the
// response through the packer, honouring credits.
virtual class aou_l4a_if_c extends uvm_object;
  function new(string name = "aou_l4a_if_c");
    super.new(name);
  endfunction

  // A DUT WriteReq and its AWLEN+1 WriteData/WriteDataFull messages, in
  // order. Return BRESP.
  virtual task handle_write(input aou_msg_wreq req, input aou_msg_wdata data[$],
                            output bit [1:0] bresp);
    bresp = 2'b00;
    `uvm_fatal("aou_l4a_if_c", "handle_write not implemented")
  endtask

  // A DUT ReadReq. Return ARLEN+1 beats: data[i] holds beat i in the lanes
  // AXI4 addressing selects on a bus as wide as the ReadData DLENGTH, resp[i]
  // its RRESP. L3 fills RP, RID, RLAST and DLENGTH (from ARSIZE, spec 5.7).
  virtual task handle_read(input aou_msg_rreq req, output bit [1023:0] data[$],
                           output bit [1:0] resp[$]);
    data.delete();
    resp.delete();
    `uvm_fatal("aou_l4a_if_c", "handle_read not implemented")
  endtask
endclass

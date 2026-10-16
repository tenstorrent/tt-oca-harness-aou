// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Logs the AoU messages that start in a flit (message type, and the
// activation op for Misc/Activation), unpacked with the L3 flit codec.
// Enough to spot the DUT's ActivateReq; L3 owns real decoding.
class aou_fdi_msg_log extends uvm_object;
  `uvm_object_utils(aou_fdi_msg_log)

  int unsigned n_msgs;
  int unsigned n_activate_req;

  function new(string name = "aou_fdi_msg_log");
    super.new(name);
  endfunction

  local function string act_name(logic [3:0] op);
    case (op)
      4'd0:    return "ActivateReq";
      4'd1:    return "ActivateAck";
      4'd2:    return "DeactivateReq";
      4'd3:    return "DeactivateAck";
      default: return "reserved";
    endcase
  endfunction

  function void log_flit(aou_flit_item f);
    aou_l3_pkg::aou_flit fl = new("fl");
    fl.from_bytes(f.data);
    `uvm_info(get_type_name(), $sformatf("%s flit: FH=%02h%02h fdid=%0d start=%012h credit=%04h",
                                         f.dir.name(), f.data[0], f.data[1], fl.fdid,
                                         fl.msg_start, fl.msg_credit), UVM_MEDIUM)
    for (int i = 0; i < aou_l3_pkg::AOU_GRANULES; i++) begin
      logic [3:0] mt;
      logic [2:0] miscop;
      logic [3:0] actop;
      if (!fl.msg_start[i]) continue;
      n_msgs++;
      mt = fl.g[i][39:36];
      miscop = fl.g[i][35:33];
      actop = fl.g[i][32:29];
      if (mt == aou_l3_pkg::AOU_MT_MISC && miscop == aou_l3_pkg::AOU_MISCOP_ACT) begin
        if (actop == aou_l3_pkg::AOU_ACT_REQ) n_activate_req++;
        `uvm_info(get_type_name(), $sformatf("  G%0d Activation op=%0d (%s)", i, actop,
                                             act_name(actop)), UVM_LOW)
      end else begin
        `uvm_info(get_type_name(), $sformatf("  G%0d MSGTYPE=%0h MISCOP=%0h granule=%010h", i, mt,
                                             miscop, fl.g[i]), UVM_LOW)
      end
    end
  endfunction
endclass

// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Builds the right aou_msg subclass from received granules.
class aou_msg_codec extends uvm_object;
  `uvm_object_utils(aou_msg_codec)

  function new(string name = "aou_msg_codec");
    super.new(name);
  endfunction

  static function aou_msg decode(aou_granule_t g[$], aou_spec_rev_e rev);
    aou_msg m;
    bit [3:0] mt = g[0][39:36];
    bit [2:0] mop = g[0][35:33];
    case (mt)
      AOU_MT_WREQ:   m = aou_msg_wreq::type_id::create("m");
      AOU_MT_RREQ:   m = aou_msg_rreq::type_id::create("m");
      AOU_MT_WDATA,
      AOU_MT_WDATAF: m = aou_msg_wdata::type_id::create("m");
      AOU_MT_RDATA:  m = aou_msg_rdata::type_id::create("m");
      AOU_MT_WRESP:  m = aou_msg_wresp::type_id::create("m");
      AOU_MT_MISC: begin
        if (mop == AOU_MISCOP_ACT && aou_msg_len(g[0], rev) != 0)
          m = aou_msg_act::type_id::create("m");
        else if (mop == AOU_MISCOP_CRDT)
          m = aou_msg_crdtgrant::type_id::create("m");
      end
      default: ;
    endcase
    if (m == null) begin
      aou_msg_raw r = aou_msg_raw::type_id::create("r");
      r.spec_rev = rev;
      r.set_granules(g);
      return r;
    end
    m.spec_rev = rev;
    m.from_granules(g);
    return m;
  endfunction
endclass

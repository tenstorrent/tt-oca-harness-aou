// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// The L1 <-> L3 boundary: one 256-byte flit in wire byte order, as L1's
// aou_flit_item carries it. L3 depends on nothing else from L1, so the
// integrator converts with a byte copy (docs/ARCHITECTURE.md, "L3 boundary").
class aou_l3_flit_item extends uvm_sequence_item;
  `uvm_object_utils(aou_l3_flit_item)

  bit [7:0]    bytes[AOU_FLIT_BYTES];
  int unsigned phy;
  time         t_start;
  aou_flit     flit;        // the decoded or source flit, when L3 made it

  function new(string name = "aou_l3_flit_item");
    super.new(name);
  endfunction

  function void from_flit(aou_flit f);
    flit = f;
    f.to_bytes(bytes);
  endfunction

  function aou_flit to_flit();
    aou_flit f = aou_flit::type_id::create("f");
    f.from_bytes(bytes);
    return f;
  endfunction

  virtual function void do_copy(uvm_object rhs);
    aou_l3_flit_item r;
    super.do_copy(rhs);
    if (!$cast(r, rhs)) `uvm_fatal(get_type_name(), "do_copy: type mismatch")
    bytes = r.bytes;
    phy = r.phy;
    t_start = r.t_start;
    flit = r.flit;
  endfunction

  virtual function string convert2string();
    return (flit != null) ? flit.convert2string() :
        $sformatf("flit bytes[62..65]=%h%h%h%h", bytes[62], bytes[63], bytes[64], bytes[65]);
  endfunction
endclass

// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// A message given as granules: reserved MSGTYPE/MISCOP/ACTIVATIONOP encodings
// arrive as this class, and tests use it to send anything the encoders refuse
// to produce. Its length is its granule count.
class aou_msg_raw extends aou_msg;
  `uvm_object_utils(aou_msg_raw)

  function new(string name = "aou_msg_raw");
    super.new(name);
  endfunction

  function void set_granules(aou_granule_t g[$]);
    raw_g = g;
    if (g.size() > 0) begin
      msg_type = g[0][39:36];
      rp = g[0][35:34];
    end
  endfunction

  virtual function int unsigned enc_granules();
    return (raw_g.size() > 0) ? raw_g.size() : 1;
  endfunction

  virtual function string kind();
    return $sformatf("Raw(MT%0d,%0dg)", msg_type, raw_g.size());
  endfunction
endclass

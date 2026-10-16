// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Base of every AoU message. A subclass encodes its fields as one message bit
// string, left-aligned in aou_msg_bits_t (bit AOU_MSG_BITS-1 is stream bit 0),
// and the base slices that into granules. Corruption hooks sit between the
// two: flip_mask is XORed into the encoded bits, len_adj adds or drops
// granules, and raw_g, when non-empty, replaces the encoding entirely.
class aou_msg extends uvm_sequence_item;
  `uvm_object_utils(aou_msg)

  bit [3:0]      msg_type;
  bit [1:0]      rp;          // wire RP field: the destination plane
  bit [15:0]     flex;        // v0.7 {PROFEXTLEN, PROF}; v0.8 FLEX
  aou_spec_rev_e spec_rev = AOU_SPEC_V07;

  // Where the message travelled, filled by the packer or unpacker.
  aou_l3_dir_e   dir = AOU_L3_TX;
  int            start_flit = -1;
  int            start_granule = -1;
  int            span_flits;

  // Error injection.
  aou_granule_t  raw_g[$];
  aou_msg_bits_t flip_mask;
  int            len_adj;
  bit            ignore_credits;  // send without (enough) credit
  bit            ignore_state;    // send regardless of the link state

  function new(string name = "aou_msg");
    super.new(name);
  endfunction

  // Encoded length in granules, from the encoding itself.
  virtual function int unsigned enc_granules();
    aou_msg_bits_t b;
    int unsigned n;
    pack_bits(b);
    n = aou_msg_len(b[AOU_MSG_BITS-1 -: AOU_GRANULE_W], spec_rev);
    return (n == 0) ? 1 : n;
  endfunction

  // Granules this message occupies on the wire, after injection hooks.
  function int unsigned num_granules();
    int n;
    if (raw_g.size() > 0) return raw_g.size();
    n = int'(enc_granules()) + len_adj;
    return (n < 1) ? 1 : n;
  endfunction

  virtual function void pack_bits(output aou_msg_bits_t b);
    b = '0;
    b[AOU_MSG_BITS-1 -: 4] = msg_type;
  endfunction

  virtual function void unpack_bits(aou_msg_bits_t b);
    msg_type = b[AOU_MSG_BITS-1 -: 4];
  endfunction

  // Reserved fields observed non-zero; "" when all are zero.
  virtual function string rsvd_nonzero();
    return "";
  endfunction

  virtual function string kind();
    return $sformatf("MT%0d", msg_type);
  endfunction

  virtual function string fields2string();
    return "";
  endfunction

  function aou_cred_class_e cred_class();
    return aou_cred_class_of(msg_type);
  endfunction

  function bit is_misc();
    return msg_type == AOU_MT_MISC;
  endfunction

  function bit is_request();
    return msg_type inside {AOU_MT_WREQ, AOU_MT_RREQ};
  endfunction

  function void to_granules(ref aou_granule_t g[$]);
    aou_msg_bits_t b;
    int unsigned n;
    g.delete();
    if (raw_g.size() > 0) begin
      foreach (raw_g[i]) g.push_back(raw_g[i]);
      return;
    end
    pack_bits(b);
    b ^= flip_mask;
    n = num_granules();
    for (int unsigned i = 0; i < n; i++) begin
      g.push_back((i < AOU_MAX_MSG_G) ? b[AOU_MSG_BITS-1-AOU_GRANULE_W*i -: AOU_GRANULE_W] : '0);
    end
  endfunction

  function void from_granules(input aou_granule_t g[$]);
    aou_msg_bits_t b = '0;
    foreach (g[i]) begin
      if (i < AOU_MAX_MSG_G) b[AOU_MSG_BITS-1-AOU_GRANULE_W*i -: AOU_GRANULE_W] = g[i];
    end
    unpack_bits(b);
  endfunction

  // Stream-bit helpers for layouts with many small fields (CrdtGrant).
  static function void put_bits(ref aou_msg_bits_t b, input int unsigned s,
                                input bit [31:0] v, input int unsigned w);
    for (int unsigned k = 0; k < w; k++) b[AOU_MSG_BITS-1-(s+k)] = v[w-1-k];
  endfunction

  static function bit [31:0] get_bits(input aou_msg_bits_t b, input int unsigned s,
                                      input int unsigned w);
    bit [31:0] v = '0;
    for (int unsigned k = 0; k < w; k++) v[w-1-k] = b[AOU_MSG_BITS-1-(s+k)];
    return v;
  endfunction

  virtual function void do_copy(uvm_object rhs);
    aou_msg r;
    super.do_copy(rhs);
    if (!$cast(r, rhs)) `uvm_fatal(get_type_name(), "do_copy: type mismatch")
    msg_type = r.msg_type;
    rp = r.rp;
    flex = r.flex;
    spec_rev = r.spec_rev;
    dir = r.dir;
    start_flit = r.start_flit;
    start_granule = r.start_granule;
    span_flits = r.span_flits;
    raw_g = r.raw_g;
    flip_mask = r.flip_mask;
    len_adj = r.len_adj;
    ignore_credits = r.ignore_credits;
    ignore_state = r.ignore_state;
  endfunction

  // Two messages compare equal when they encode to the same granules.
  virtual function bit do_compare(uvm_object rhs, uvm_comparer comparer);
    aou_msg r;
    aou_granule_t a[$], b[$];
    if (!$cast(r, rhs)) return 1'b0;
    to_granules(a);
    r.to_granules(b);
    if (a.size() != b.size()) return 1'b0;
    foreach (a[i]) if (a[i] != b[i]) return 1'b0;
    return 1'b1;
  endfunction

  virtual function string convert2string();
    string s = $sformatf("%s rp=%0d", kind(), rp);
    if (start_flit >= 0) s = {s, $sformatf(" @f%0d.g%0d", start_flit, start_granule)};
    return {s, " ", fields2string()};
  endfunction
endclass

// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// CrdtGrant Misc message (Table 19, Figure 20): 2 granules. After MSGTYPE and
// MISCOP come the credit fields class by class (WREQ, RREQ, WDATA, RDATA) for
// RP0..3, three bits each, then WRESP for RP0..3 at two bits, then RsvdZero17.
// Each field carries the source RP's credits.
class aou_msg_crdtgrant extends aou_msg;
  `uvm_object_utils(aou_msg_crdtgrant)

  bit [2:0]  enc[AOU_RP_MAX][AOU_CC_NUM];
  bit [16:0] rsvd;

  function new(string name = "aou_msg_crdtgrant");
    super.new(name);
    msg_type = AOU_MT_MISC;
  endfunction

  // Exact value when n is encodable, otherwise the largest encodable below it.
  function void set_cred(int unsigned r, aou_cred_class_e c, int unsigned n);
    enc[r][c] = aou_cred_enc_floor(c, n);
  endfunction

  function int unsigned get_cred(int unsigned r, aou_cred_class_e c);
    return aou_cred_dec3(enc[r][c]);
  endfunction

  function bit any_nonzero();
    foreach (enc[r, c]) if (enc[r][c] != 0) return 1'b1;
    return 1'b0;
  endfunction

  virtual function void pack_bits(output aou_msg_bits_t b);
    int unsigned s = 7;
    b = '0;
    b[AOU_MSG_BITS-1 -: 7] = {msg_type, AOU_MISCOP_CRDT};
    for (int unsigned c = 0; c < AOU_CC_NUM - 1; c++) begin
      for (int unsigned r = 0; r < AOU_RP_MAX; r++) begin
        put_bits(b, s, 32'(enc[r][c]), 3);
        s += 3;
      end
    end
    for (int unsigned r = 0; r < AOU_RP_MAX; r++) begin
      put_bits(b, s, 32'(enc[r][AOU_CC_WRESP][1:0]), 2);
      s += 2;
    end
    put_bits(b, s, 32'(rsvd), 17);
  endfunction

  virtual function void unpack_bits(aou_msg_bits_t b);
    int unsigned s = 7;
    msg_type = b[AOU_MSG_BITS-1 -: 4];
    for (int unsigned c = 0; c < AOU_CC_NUM - 1; c++) begin
      for (int unsigned r = 0; r < AOU_RP_MAX; r++) begin
        enc[r][c] = 3'(get_bits(b, s, 3));
        s += 3;
      end
    end
    for (int unsigned r = 0; r < AOU_RP_MAX; r++) begin
      enc[r][AOU_CC_WRESP] = 3'(get_bits(b, s, 2));
      s += 2;
    end
    rsvd = 17'(get_bits(b, s, 17));
  endfunction

  virtual function string rsvd_nonzero();
    return (rsvd != 0) ? "RsvdZero17" : "";
  endfunction

  // Fields for an RP the link lacks must be zero (6.4.2).
  function bit unsupported_rp_nonzero(int unsigned rp_count);
    for (int unsigned r = rp_count; r < AOU_RP_MAX; r++) begin
      for (int unsigned c = 0; c < AOU_CC_NUM; c++) if (enc[r][c] != 0) return 1'b1;
    end
    return 1'b0;
  endfunction

  virtual function string kind();
    return "CrdtGrant";
  endfunction

  virtual function string fields2string();
    string s = "";
    for (int unsigned r = 0; r < AOU_RP_MAX; r++) begin
      s = {s, $sformatf("rp%0d=%0d/%0d/%0d/%0d/%0d ", r, get_cred(r, AOU_CC_WREQ),
                        get_cred(r, AOU_CC_RREQ), get_cred(r, AOU_CC_WDATA),
                        get_cred(r, AOU_CC_RDATA), get_cred(r, AOU_CC_WRESP))};
    end
    return s;
  endfunction

  virtual function void do_copy(uvm_object rhs);
    aou_msg_crdtgrant r;
    super.do_copy(rhs);
    if (!$cast(r, rhs)) `uvm_fatal(get_type_name(), "do_copy: type mismatch")
    enc = r.enc;
    rsvd = r.rsvd;
  endfunction
endclass

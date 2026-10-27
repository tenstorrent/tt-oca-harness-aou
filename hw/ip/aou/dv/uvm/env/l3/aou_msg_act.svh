// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 Tenstorrent USA Inc

// Activation Misc message (v0.7 Table 26, v0.8 Table 26/27).
//   v0.7: MSGTYPE, MISCOP=010, ACTIVATIONOP, PropertyReq, RsvdZero28 (1 granule).
//   v0.8: ActivateReq adds RsvdZero3 and, per RP, ProfileID/Rev/Opt (4 granules);
//         the other opcodes are MSGTYPE, MISCOP, ACTIVATIONOP, RsvdZero29.
class aou_msg_act extends aou_msg;
  `uvm_object_utils(aou_msg_act)

  bit [3:0]  op;
  bit        property_req;
  bit [28:0] rsvd;
  bit [4:0]  profile_id[AOU_RP_MAX];
  bit [4:0]  profile_rev[AOU_RP_MAX];
  bit [15:0] profile_opt[AOU_RP_MAX];
  bit [13:0] rsvd_rp[AOU_RP_MAX];   // entry 0 unused

  function new(string name = "aou_msg_act");
    super.new(name);
    msg_type = AOU_MT_MISC;
  endfunction

  function bit v08_req();
    return spec_rev == AOU_SPEC_V08 && op == AOU_ACT_REQ;
  endfunction

  virtual function void pack_bits(output aou_msg_bits_t b);
    b = '0;
    if (v08_req()) begin
      b[AOU_MSG_BITS-1 -: 40] = {msg_type, AOU_MISCOP_ACT, op, rsvd[2:0], profile_id[0],
                                 profile_rev[0], profile_opt[0]};
      for (int unsigned r = 1; r < AOU_RP_MAX; r++) begin
        b[AOU_MSG_BITS-1-40*r -: 40] = {rsvd_rp[r], profile_id[r], profile_rev[r],
                                        profile_opt[r]};
      end
    end else if (spec_rev == AOU_SPEC_V08) begin
      b[AOU_MSG_BITS-1 -: 40] = {msg_type, AOU_MISCOP_ACT, op, rsvd[28:0]};
    end else begin
      b[AOU_MSG_BITS-1 -: 40] = {msg_type, AOU_MISCOP_ACT, op, property_req, rsvd[27:0]};
    end
  endfunction

  virtual function void unpack_bits(aou_msg_bits_t b);
    bit [2:0] mop;
    {msg_type, mop, op} = b[AOU_MSG_BITS-1 -: 11];
    rsvd = '0;
    property_req = 1'b0;
    if (v08_req()) begin
      {rsvd[2:0], profile_id[0], profile_rev[0], profile_opt[0]} = b[AOU_MSG_BITS-12 -: 29];
      for (int unsigned r = 1; r < AOU_RP_MAX; r++) begin
        {rsvd_rp[r], profile_id[r], profile_rev[r], profile_opt[r]} =
            b[AOU_MSG_BITS-1-40*r -: 40];
      end
    end else if (spec_rev == AOU_SPEC_V08) begin
      rsvd = b[AOU_MSG_BITS-12 -: 29];
    end else begin
      {property_req, rsvd[27:0]} = b[AOU_MSG_BITS-12 -: 29];
    end
  endfunction

  virtual function string rsvd_nonzero();
    if (rsvd != 0) return "RsvdZero";
    // v0.7 Table 26: PropertyReq is 0 on every opcode but ActivateReq.
    if (spec_rev == AOU_SPEC_V07 && property_req && op != AOU_ACT_REQ)
      return "PropertyReq on a non-ActivateReq opcode";
    if (v08_req()) begin
      for (int unsigned r = 1; r < AOU_RP_MAX; r++) begin
        if (rsvd_rp[r] != 0) return $sformatf("RsvdZero before RP%0d profile", r);
      end
    end
    return "";
  endfunction

  // A DeactivateReq whose only non-zero reserved bit is v0.7's PropertyReq
  // position (v0.8 makes it the top RsvdZero bit). Taken from the RTL: the DUT
  // marks the DeactivateReq that AOU_CON0.DEACTIVATE_FORCE sends this way and
  // no other (MAS software-operation 7.1).
  function bit forced_deact_mark();
    if (op != AOU_DEACT_REQ) return 1'b0;
    if (spec_rev == AOU_SPEC_V08) return rsvd == 29'h1000_0000;
    return property_req && rsvd == 0;
  endfunction

  // Basic Profile: every ProfileID/Rev/Opt is zero (v0.8 11.1).
  function bit profile_nonzero();
    if (!v08_req()) return 1'b0;
    for (int unsigned r = 0; r < AOU_RP_MAX; r++) begin
      if (profile_id[r] != 0 || profile_rev[r] != 0 || profile_opt[r] != 0) return 1'b1;
    end
    return 1'b0;
  endfunction

  static function string op_name(bit [3:0] o);
    case (o)
      AOU_ACT_REQ:   return "ActivateReq";
      AOU_ACT_ACK:   return "ActivateAck";
      AOU_DEACT_REQ: return "DeactivateReq";
      AOU_DEACT_ACK: return "DeactivateAck";
      default:       return $sformatf("ActivationOp%0d", o);
    endcase
  endfunction

  virtual function string kind();
    return op_name(op);
  endfunction

  virtual function string fields2string();
    return $sformatf("prop=%0d", property_req);
  endfunction

  virtual function void do_copy(uvm_object rhs);
    aou_msg_act r;
    super.do_copy(rhs);
    if (!$cast(r, rhs)) `uvm_fatal(get_type_name(), "do_copy: type mismatch")
    op = r.op;
    property_req = r.property_req;
    rsvd = r.rsvd;
    profile_id = r.profile_id;
    profile_rev = r.profile_rev;
    profile_opt = r.profile_opt;
    rsvd_rp = r.rsvd_rp;
  endfunction
endclass

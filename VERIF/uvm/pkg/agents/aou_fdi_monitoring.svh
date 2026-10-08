// *****************************************************************************
// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2026 VNCHIPLabs
// *****************************************************************************
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
// *****************************************************************************
//
//  File        : aou_fdi_monitoring.svh
//  Author     : Vinh Trieu, Quang Le
//
// *****************************************************************************
  // -------------------------------------------------------------------
  // aou_flit_decoder -- pure (vif-free, component-free) FDI flit decoder
  // with persistent inter-flit message reassembly across cycles.
  //
  // A message whose granule count exceeds the granules remaining in the
  // current flit is held as continuation state (type, DLENGTH, granules
  // collected so far) and completed from the next flit's G0 onward --
  // only then is the fully reassembled message unpacked and published.
  // Completed messages are appended to out_q as immutable objects; the
  // caller (aou_fdi_tx_monitor, or a unit test) drains the queue.
  //
  // Malformed-continuation detection: a MsgStart bit inside the granule
  // region still owed to an in-flight continuation is a UVM_ERROR; the
  // partial message is dropped and normal decode resumes at that granule.
  // flush() (reset/epoch) invalidates any partial state, with a warning
  // if a partial message is discarded.
  // -------------------------------------------------------------------
  class aou_flit_decoder extends uvm_object;
    `uvm_object_utils(aou_flit_decoder)

    aou_fdi_msg_item out_q[$];
    string tag = "FDIDEC";

    // continuation state (valid while pend_active)
    local bit          pend_active;
    local logic [3:0]  pend_mt;
    local logic [1:0]  pend_dlength;
    local int unsigned pend_need;   // total granules of the spanning message
    local int unsigned pend_have;   // granules collected so far
    local int unsigned pend_start_granule;
    local int unsigned pend_continuation_flits;
    local logic [39:0] pend_garr[aou_pkg::NUM_GRANULES];

    // statistics for callers/tests
    longint unsigned n_reassembled;   // messages completed across a boundary
    longint unsigned n_malformed;     // dropped malformed continuations

    function new(string name = "aou_flit_decoder");
      super.new(name);
    endfunction

    function bit reassembly_pending();
      return pend_active;
    endfunction

    // Reset/epoch invalidation: drop any partial reassembly.
    function void flush(string reason);
      if (pend_active)
        uvm_report_warning(tag, $sformatf(
            "flush(%s): dropping partial reassembly (MSGTYPE=0x%0h, %0d/%0d granules collected)",
            reason, pend_mt, pend_have, pend_need), uvm_pkg::UVM_NONE);
      pend_active = 1'b0;
      pend_have   = 0;
      pend_start_granule = 0;
      pend_continuation_flits = 0;
    endfunction

    // Granule count for a message whose first granule (wire order) is g0.
    // Returns 0 for undecodable types (caller reports and advances by 1).
    local function int unsigned msg_granules(input logic [39:0] g0);
      logic [3:0] mt      = g0[39:36];
      logic [1:0] dlength = g0[33:32];
      logic [2:0] miscop  = g0[35:33];
      case (mt)
        aou_pkg::MSGTYPE_WRITEREQ, aou_pkg::MSGTYPE_READREQ: return 3;
        aou_pkg::MSGTYPE_WRITERESP:                          return 1;
        aou_pkg::MSGTYPE_WRITEDATA, aou_pkg::MSGTYPE_WRITEDATAFULL,
        aou_pkg::MSGTYPE_READDATA:
          return aou_pkg::data_msg_granules(mt, dlength);
        aou_pkg::MSGTYPE_MISC:
          return (miscop == aou_pkg::MISCOP_CRDTGRANT) ? 2 : 1;
        default:                                             return 0;
      endcase
    endfunction

    // Unpack a COMPLETE message from its collected granules and publish.
    local function void publish_msg(input logic [39:0] garr[aou_pkg::NUM_GRANULES],
                                    input int unsigned ng,
                                    input int unsigned start_g = 0,
                                    input bit spans = 1'b0,
                                    input int unsigned continuation_flits = 0);
      logic [3:0] mt      = garr[0][39:36];
      logic [1:0] dlength = garr[0][33:32];
      aou_fdi_msg_item m;
      m = null;
      case (mt)
        aou_pkg::MSGTYPE_WRITEREQ, aou_pkg::MSGTYPE_READREQ: begin
          logic [2:0][39:0] g3;
          logic [3:0] msgtype_o; logic [1:0] rp_o; logic lock_o; logic [9:0] id_o;
          logic [2:0] size_o, prot_o; logic [7:0] len_o; logic [3:0] cache_o, qos_o;
          logic [63:0] addr_o;
          g3[0] = garr[0]; g3[1] = garr[1]; g3[2] = garr[2];
          aou_pkg::unpack_req(g3, msgtype_o, rp_o, lock_o, id_o, size_o, prot_o,
                              len_o, cache_o, qos_o, addr_o);
          m = aou_fdi_msg_item::type_id::create("m");
          m.msgtype = aou_pkg::msgtype_e'(mt);
          m.rp = rp_o; m.id = id_o; m.addr = addr_o; m.len = len_o; m.size = size_o;
          m.lock = lock_o; m.prot = prot_o; m.cache = cache_o; m.qos = qos_o;
          m.req_rsvd_zero = (g3[0][33] === 1'b0);
          m.profextlen = g3[0][31:28];
          m.prof = g3[0][27:16];
          out_q.push_back(m);
        end
        aou_pkg::MSGTYPE_WRITEDATA: begin
          logic [1:0] rp_o; logic [1023:0] wdata_o; logic [127:0] wstrb_o;
          aou_pkg::unpack_writedata(garr, dlength, rp_o, wdata_o, wstrb_o);
          m = aou_fdi_msg_item::type_id::create("m");
          m.msgtype = aou_pkg::MSGTYPE_WRITEDATA;
          m.rp = rp_o; m.data = wdata_o[aou_pkg::AXI_DATA_W-1:0]; m.strb = wstrb_o[aou_pkg::AXI_DATA_BYTES-1:0];
          out_q.push_back(m);
        end
        aou_pkg::MSGTYPE_WRITEDATAFULL: begin
          logic [1:0] rp_o; logic [1023:0] wdata_o;
          aou_pkg::unpack_writedatafull(garr, dlength, rp_o, wdata_o);
          m = aou_fdi_msg_item::type_id::create("m");
          // Classified as WRITEDATA for handle_msg's benefit -- "full"
          // only means WSTRB was all-1s, which the WriteData consumer
          // treats identically (it always stores the whole word).
          m.msgtype = aou_pkg::MSGTYPE_WRITEDATA;
          m.rp = rp_o; m.data = wdata_o[aou_pkg::AXI_DATA_W-1:0]; m.strb = '1;
          out_q.push_back(m);
        end
        aou_pkg::MSGTYPE_WRITERESP: begin
          logic [1:0] rp_o; logic [9:0] bid_o; logic [1:0] bresp_o;
          aou_pkg::unpack_writeresp(garr[0], rp_o, bid_o, bresp_o);
          m = aou_fdi_msg_item::type_id::create("m");
          m.msgtype = aou_pkg::MSGTYPE_WRITERESP;
          m.rp = rp_o; m.id = bid_o; m.resp = bresp_o;
          out_q.push_back(m);
        end
        aou_pkg::MSGTYPE_READDATA: begin
          logic [1:0] rp_o; logic [9:0] rid_o; logic [1:0] rresp_o; logic rlast_o;
          logic [1023:0] rdata_o;
          aou_pkg::unpack_readdata(garr, dlength, rp_o, rid_o, rresp_o, rlast_o, rdata_o);
          m = aou_fdi_msg_item::type_id::create("m");
          m.msgtype = aou_pkg::MSGTYPE_READDATA;
          m.rp = rp_o; m.id = rid_o; m.resp = rresp_o; m.rlast = rlast_o;
          m.data = rdata_o[aou_pkg::AXI_DATA_W-1:0];
          m.full_data = rdata_o;
          m.full_data_valid = 1'b1;
          out_q.push_back(m);
        end
        aou_pkg::MSGTYPE_MISC: begin
          logic [2:0] miscop = garr[0][35:33];
          if (miscop == aou_pkg::MISCOP_ACTIVATION) begin
            logic [3:0] msgtype_o; logic [2:0] miscop_o; logic [3:0] actop_o; logic propreq_o;
            aou_pkg::unpack_activation(garr[0], msgtype_o, miscop_o, actop_o, propreq_o);
            m = aou_fdi_msg_item::type_id::create("m");
            m.msgtype = aou_pkg::MSGTYPE_MISC; m.miscop = miscop_o; m.actop = actop_o;
            out_q.push_back(m);
          end else if (miscop == aou_pkg::MISCOP_CRDTGRANT) begin
            // See pack_crdtgrant's byte-reversal/granule-swap derivation.
            int unsigned wreq_n[4], rreq_n[4];
            int unsigned wdata_n[4], rdata_n[4];
            int unsigned wresp_n[4];
            logic [2:0] wreq_e[4], rreq_e[4], wdata_e[4], rdata_e[4];
            logic [1:0] wresp_e[4];
            bit rsvd_zero;
            logic [1:0][39:0] grant_g;
            m = aou_fdi_msg_item::type_id::create("m");
            m.msgtype = aou_pkg::MSGTYPE_MISC; m.miscop = miscop;
            grant_g[0] = garr[0]; grant_g[1] = garr[1];
            aou_pkg::unpack_crdtgrant(grant_g, wreq_n, rreq_n, wdata_n,
                                      rdata_n, wresp_n, rsvd_zero,
                                      wreq_e, rreq_e, wdata_e, rdata_e, wresp_e);
            for (int r = 0; r < 4; r++) begin
              m.crdt_wreqcred[r] = wreq_n[r];
              m.crdt_rreqcred[r] = rreq_n[r];
              m.crdt_wdatacred[r] = wdata_n[r];
              m.crdt_rdatacred[r] = rdata_n[r];
              m.crdt_wrespcred[r] = wresp_n[r];
              m.crdt_wreqcred_enc[r] = wreq_e[r];
              m.crdt_rreqcred_enc[r] = rreq_e[r];
              m.crdt_wdatacred_enc[r] = wdata_e[r];
              m.crdt_rdatacred_enc[r] = rdata_e[r];
              m.crdt_wrespcred_enc[r] = wresp_e[r];
            end
            m.crdt_rreqcred0  = rreq_n[0];
            m.crdt_rdatacred0 = rdata_n[0];
            m.crdt_rsvd_zero  = rsvd_zero;
            out_q.push_back(m);
          end else begin
            uvm_report_warning(tag, $sformatf("unhandled MISCOP=%0d", miscop), uvm_pkg::UVM_NONE);
          end
        end
        default: ; // caller already reported the unexpected MSGTYPE
      endcase
      if (m != null) begin
        m.wire_msgtype = mt;
        m.dlength = (mt inside {aou_pkg::MSGTYPE_WRITEDATA,
                                aou_pkg::MSGTYPE_WRITEDATAFULL,
                                aou_pkg::MSGTYPE_READDATA}) ? dlength : 2'b00;
        m.granule_cost = ng;
        m.start_granule = start_g;
        m.spans_flit = spans;
        m.continuation_flits = continuation_flits;
      end
    endfunction

    function void decode_flit(input logic [7:0] flit[aou_pkg::FLIT_BYTES]);
      logic [1:0]  fdid;
      logic [47:0] msg_start;
      logic [15:0] msg_credit;
      int unsigned g_start;

      aou_pkg::flit_get_header(flit, fdid, msg_start, msg_credit);
      uvm_report_info(tag, $sformatf("flit decoded: fdid=%0d msg_start=%048b msg_credit=%0h",
                      fdid, msg_start, msg_credit), uvm_pkg::UVM_LOW);

      // Protocol-header MsgCredit (spec Section 6.3.1, Table 17): an
      // independent credit channel present in every flit header, applied
      // unconditionally, separate from the granule-indexed loop below.
      if (msg_credit != 16'h0) begin
        automatic aou_fdi_msg_item hc = aou_fdi_msg_item::type_id::create("hc");
        hc.msgtype        = aou_pkg::MSGTYPE_HDRCREDIT;
        hc.wire_msgtype   = aou_pkg::MSGTYPE_HDRCREDIT;
        hc.hdr_msg_credit_raw = msg_credit;
        hc.rp              = msg_credit[15:14];
        hc.hdr_wreqcred    = aou_pkg::credit_dec3(msg_credit[2:0]);
        hc.hdr_rreqcred    = aou_pkg::credit_dec3(msg_credit[5:3]);
        hc.hdr_wdatacred   = aou_pkg::credit_dec3(msg_credit[8:6]);
        hc.hdr_rdatacred   = aou_pkg::credit_dec3(msg_credit[11:9]);
        hc.hdr_wrespcred   = aou_pkg::credit_dec3({1'b0, msg_credit[13:12]});
        out_q.push_back(hc);
      end

      // ---- continuation consumption: owed granules occupy G0 onward ----
      g_start = 0;
      if (pend_active) begin
        automatic int unsigned owed = pend_need - pend_have;
        automatic int unsigned take = (owed > aou_pkg::NUM_GRANULES) ? aou_pkg::NUM_GRANULES : owed;
        automatic int unsigned bad_g;
        automatic bit          malformed = 1'b0;
        for (int unsigned i = 0; i < take; i++) begin
          if (msg_start[i]) begin
            malformed = 1'b1; bad_g = i;
            break;
          end
        end
        if (malformed) begin
          uvm_report_error(tag, $sformatf(
              "malformed continuation: new MsgStart at G%0d while %0d granule(s) of a MSGTYPE=0x%0h continuation still expected -- dropping partial message",
              bad_g, owed, pend_mt), uvm_pkg::UVM_NONE);
          n_malformed++;
          pend_active = 1'b0;
          pend_have   = 0;
          g_start     = 0; // resume normal decode from G0 (incl. the new MsgStart)
        end else begin
          automatic logic [39:0] tmp[aou_pkg::NUM_GRANULES];
          aou_pkg::flit_get_granules(flit, 0, take, tmp);
          for (int unsigned i = 0; i < take; i++) pend_garr[pend_have + i] = tmp[i];
          pend_have += take;
          g_start = take;
          if (pend_have == pend_need) begin
            publish_msg(pend_garr, pend_need, pend_start_granule, 1'b1,
                        pend_continuation_flits);
            n_reassembled++;
            pend_active = 1'b0;
            pend_have   = 0;
          end else begin
            return; // entire flit consumed by the continuation
          end
        end
      end

      // ---- normal granule-indexed message decode ----
      for (int unsigned g = g_start; g < aou_pkg::NUM_GRANULES; g++) begin
        if (msg_start[g]) begin
          automatic int unsigned bpos = aou_pkg::granule_byte_pos(g);
          automatic logic [39:0] garr[aou_pkg::NUM_GRANULES];
          automatic logic [39:0] first_g;
          automatic int unsigned ng, avail;
          aou_pkg::flit_get_granules(flit, g, 1, garr);
          first_g = garr[0];
          ng = msg_granules(first_g);
          if (ng == 0) begin
            if (first_g[39:36] inside {aou_pkg::MSGTYPE_WRITEDATA,
                                        aou_pkg::MSGTYPE_WRITEDATAFULL,
                                        aou_pkg::MSGTYPE_READDATA})
              uvm_report_error(tag, $sformatf(
                  "MSGTYPE=0x%0h DLENGTH=%0d unrecognized at G%0d -- skipping one granule",
                  first_g[39:36], first_g[33:32], g), uvm_pkg::UVM_NONE);
            else
              uvm_report_error(tag, $sformatf(
                  "unexpected MSGTYPE=0x%0h at G%0d -- not decodable, skipping one granule",
                  first_g[39:36], g), uvm_pkg::UVM_NONE);
            continue; // loop's g++ advances past it
          end
          avail = aou_pkg::NUM_GRANULES - g;
          if (ng <= avail) begin
            aou_pkg::flit_get_granules(flit, g, ng, garr);
            // Preserve the passive wire start position for every normal
            // message.  The default start_g=0 is correct only for G0; using
            // it here silently collapsed observed non-G0 messages into G0
            // coverage and hid the actual MsgStart boundary.
            publish_msg(garr, ng, g, 1'b0, 0);
            g += ng - 1;
          end else begin
            // message crosses into the next flit -- hold as continuation
            pend_active  = 1'b1;
            pend_mt      = first_g[39:36];
            pend_dlength = first_g[33:32];
            pend_need    = ng;
            pend_have    = avail;
            pend_start_granule = g;
            pend_continuation_flits = 1;
            aou_pkg::flit_get_granules(flit, g, avail, garr);
            for (int unsigned i = 0; i < avail; i++) pend_garr[i] = garr[i];
            break; // a crossing message is by construction the last start in this flit
          end
        end
      end
    endfunction
  endclass

  // Passive observer for complete fixed-width FDI transfers from the DUT.
  class aou_fdi_tx_monitor extends uvm_monitor;
    `uvm_component_utils(aou_fdi_tx_monitor)

    virtual aou_fdi_if #(.DATA_W(aou_pkg::FDI_DATA_W)) vif;
    uvm_analysis_port #(aou_fdi_msg_item) ap;
    local aou_flit_decoder decoder;
    local int unsigned epoch;
    local longint unsigned message_order;
    localparam int BEAT_BYTES = aou_pkg::FDI_DATA_BYTES;
    localparam int BEAT_COUNT = aou_pkg::FLIT_BYTES / BEAT_BYTES;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      ap = new("ap", this);
      epoch = 1;
      message_order = 0;
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual aou_fdi_if #(.DATA_W(aou_pkg::FDI_DATA_W)))::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", "aou_fdi_tx_monitor: no aou_fdi_if in config_db")
    endfunction

    task run_phase(uvm_phase phase);
      logic [7:0] flit[aou_pkg::FLIT_BYTES];
      int unsigned beat;
      beat = 0;
      fork
        forever begin
          @(negedge vif.resetn);
          epoch++;
          beat = 0;
          if (decoder != null) decoder.flush("reset asserted");
        end
      join_none
      forever begin
        @(vif.tx_cb);
        if (vif.tx_cb.lp_valid && vif.pl_trdy) begin
          for (int unsigned byte_i = 0; byte_i < BEAT_BYTES; byte_i++)
            flit[beat*BEAT_BYTES+byte_i] = vif.tx_cb.lp_data[byte_i*8 +: 8];
          beat++;
          if (beat == BEAT_COUNT) begin
            decode_and_publish(flit);
            beat = 0;
          end
        end
      end
    endtask

    task decode_and_publish(logic [7:0] flit[aou_pkg::FLIT_BYTES]);
      logic [1:0] fdid;
      logic [47:0] msg_start;
      logic [15:0] msg_credit;
      if (decoder == null) begin
        decoder = aou_flit_decoder::type_id::create("decoder");
        decoder.tag = "FDI_TX";
      end
      aou_pkg::flit_get_header(flit, fdid, msg_start, msg_credit);
      decoder.decode_flit(flit);
      while (decoder.out_q.size() != 0) begin
        aou_fdi_msg_item msg;
        msg = decoder.out_q.pop_front();
        msg.observed_cycle = $time;
        msg.endpoint_id = 0;
        msg.fdid = fdid;
        msg.epoch = epoch;
        msg.observation_direction = "FDI_TX";
        msg.source_message_order = ++message_order;
        msg.source_message_order_valid = 1'b1;
        ap.write(msg);
      end
    endtask
  endclass

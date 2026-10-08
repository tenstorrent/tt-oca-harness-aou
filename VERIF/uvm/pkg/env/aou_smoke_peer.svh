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
//  File        : aou_smoke_peer.svh
//  Author     : Vinh Trieu, Quang Le
//
// *****************************************************************************
  // Minimal remote link partner for the deterministic multi-RP smoke.
  // It answers activation, stores one AXI beat per address, and returns the
  // corresponding write and read responses. The FDI monitor supplies only
  // decoded messages observed on the DUT transmit interface.
  class aou_smoke_peer extends uvm_component;
    `uvm_component_utils(aou_smoke_peer)

    virtual aou_fdi_if #(.DATA_W(aou_pkg::FDI_DATA_W)) vif;
    uvm_analysis_imp #(aou_fdi_msg_item, aou_smoke_peer) msg_imp;
    mailbox #(aou_fdi_msg_item) inbox;
    mailbox #(aou_fdi_msg_item) write_responses;
    mailbox #(aou_fdi_msg_item) read_responses;
    semaphore tx_lock;

    localparam int RP_COUNT = 4;
    local bit [63:0] pending_addr[RP_COUNT];
    local bit [9:0] pending_id[RP_COUNT];
    local bit pending_write[RP_COUNT];
    local bit [aou_pkg::AXI_DATA_W-1:0] memory[RP_COUNT][bit [63:0]];
    local int unsigned write_response_credit[RP_COUNT];
    local int unsigned read_response_credit[RP_COUNT];
    localparam int BEAT_BYTES = aou_pkg::FDI_DATA_BYTES;
    localparam int BEAT_COUNT = aou_pkg::FLIT_BYTES / aou_pkg::FDI_DATA_BYTES;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      msg_imp = new("msg_imp", this);
      inbox = new();
      write_responses = new();
      read_responses = new();
      tx_lock = new(1);
      foreach (pending_write[rp]) begin
        pending_addr[rp] = '0;
        pending_id[rp] = '0;
        pending_write[rp] = 1'b0;
        write_response_credit[rp] = 0;
        read_response_credit[rp] = 0;
      end
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual aou_fdi_if #(.DATA_W(aou_pkg::FDI_DATA_W)))::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", "aou_smoke_peer: no aou_fdi_if in config_db")
    endfunction

    function void write(aou_fdi_msg_item msg);
      if (msg == null) return;
      if (inbox.try_put(msg) == 0)
        `uvm_error("FDIPEER", "unable to queue decoded FDI message")
    endfunction

    task run_phase(uvm_phase phase);
      vif.rx_cb.pl_valid <= 1'b0;
      vif.rx_cb.pl_flit_cancel <= 1'b0;
      vif.tx_cb.pl_trdy <= 1'b1;
      vif.tx_cb.pl_stallreq <= 1'b0;
      vif.tx_cb.pl_state_sts <= vif.STATE_STS_ACTIVE;
      wait (vif.resetn === 1'b1);
      repeat (10) @(vif.rx_cb);
      fork
        message_loop();
        write_response_loop();
        read_response_loop();
      join_none
      send_activation(aou_pkg::ACTOP_ACTIVATE_REQ);
      send_credit_grant();
    endtask

    task message_loop();
      forever begin
        aou_fdi_msg_item msg;
        inbox.get(msg);
        if (vif.resetn !== 1'b1) continue;
        case (msg.msgtype)
          aou_pkg::MSGTYPE_MISC: begin
            if (msg.miscop == aou_pkg::MISCOP_ACTIVATION &&
                msg.actop == aou_pkg::ACTOP_ACTIVATE_REQ) begin
              send_activation(aou_pkg::ACTOP_ACTIVATE_ACK);
              send_credit_grant();
            end else if (msg.miscop == aou_pkg::MISCOP_CRDTGRANT) begin
              foreach (write_response_credit[rp]) begin
                write_response_credit[rp] += msg.crdt_wrespcred[rp];
                read_response_credit[rp] += msg.crdt_rdatacred[rp];
              end
            end
          end
          aou_pkg::MSGTYPE_HDRCREDIT: begin
            write_response_credit[msg.rp] += msg.hdr_wrespcred;
            read_response_credit[msg.rp] += msg.hdr_rdatacred;
          end
          aou_pkg::MSGTYPE_WRITEREQ: begin
            check_request_metadata(msg, 1'b1);
            pending_addr[msg.rp] = {msg.addr[63:int'(aou_pkg::AXI_SIZE)], {aou_pkg::AXI_SIZE{1'b0}}};
            pending_id[msg.rp] = msg.id;
            pending_write[msg.rp] = 1'b1;
          end
          aou_pkg::MSGTYPE_WRITEDATA: begin
            if (!pending_write[msg.rp]) begin
              `uvm_error("FDIPEER", $sformatf("WriteData without WriteReq on RP%0d", msg.rp))
            end else begin
              memory[msg.rp][pending_addr[msg.rp]] = msg.data;
              begin
                aou_fdi_msg_item response;
                response = aou_fdi_msg_item::type_id::create("write_response");
                response.rp = msg.rp;
                response.id = pending_id[msg.rp];
                write_responses.put(response);
              end
              pending_write[msg.rp] = 1'b0;
            end
          end
          aou_pkg::MSGTYPE_READREQ: begin
            aou_fdi_msg_item response;
            check_request_metadata(msg, 1'b0);
            response = aou_fdi_msg_item::type_id::create("read_response");
            response.rp = msg.rp;
            response.id = msg.id;
            response.addr = {msg.addr[63:int'(aou_pkg::AXI_SIZE)], {aou_pkg::AXI_SIZE{1'b0}}};
            response.data = memory[msg.rp].exists(response.addr) ? memory[msg.rp][response.addr] : '0;
            read_responses.put(response);
          end
          default: ;
        endcase
      end
    endtask

    task write_response_loop();
      forever begin
        aou_fdi_msg_item response;
        write_responses.get(response);
        wait (write_response_credit[response.rp] != 0 || vif.resetn !== 1'b1);
        if (vif.resetn !== 1'b1) continue;
        write_response_credit[response.rp]--;
        send_writeresp(response.rp, response.id);
      end
    endtask

    task read_response_loop();
      forever begin
        aou_fdi_msg_item response;
        read_responses.get(response);
        wait (read_response_credit[response.rp] != 0 || vif.resetn !== 1'b1);
        if (vif.resetn !== 1'b1) continue;
        read_response_credit[response.rp]--;
        send_readdata(response.rp, response.id, response.data);
      end
    endtask


    task check_request_metadata(aou_fdi_msg_item msg, bit is_write);
      bit [63:0] expected_addr;
      bit [9:0] expected_id;
      expected_addr = 64'h0000_0000_0000_0100 + (64'(msg.rp) << 12);
      expected_id = is_write ? 10'(10'h100 + msg.rp) : 10'(10'h200 + msg.rp);
      if (msg.addr !== expected_addr ||
          msg.id !== expected_id || msg.len !== 8'd0 ||
          msg.size !== aou_pkg::AXI_SIZE || msg.lock !== 1'b0 ||
          msg.cache !== 4'd0 || msg.prot !== 3'd0 || msg.qos !== 4'd0 ||
          msg.profextlen !== 4'd0 || msg.prof !== 12'd0 ||
          msg.req_rsvd_zero !== 1'b1) begin
        `uvm_error("FDIPEER", $sformatf(
          "%s request metadata mismatch RP%0d: addr=%h id=%h len=%0d size=%0d lock=%0b cache=%h prot=%h qos=%h profextlen=%h prof=%h reserved_zero=%b",
          is_write ? "WriteReq" : "ReadReq", msg.rp, msg.addr, msg.id,
          msg.len, msg.size, msg.lock, msg.cache, msg.prot, msg.qos,
          msg.profextlen, msg.prof, msg.req_rsvd_zero))
      end
    endtask

    task send_activation(aou_pkg::activationop_e op);
      logic [7:0] flit[aou_pkg::FLIT_BYTES];
      logic [39:0] granules[aou_pkg::NUM_GRANULES];
      logic [39:0] activation;
      logic [47:0] starts;
      aou_pkg::flit_clear(flit);
      aou_pkg::pack_activation(activation, op, 1'b0);
      granules[0] = activation;
      starts = '0;
      starts[0] = 1'b1;
      aou_pkg::flit_put_granules(flit, 0, 1, granules);
      aou_pkg::flit_put_header(flit, 2'b00, starts, 16'h0);
      send_flit(flit);
    endtask

    task send_credit_grant();
      logic [7:0] flit[aou_pkg::FLIT_BYTES];
      logic [39:0] granules[aou_pkg::NUM_GRANULES];
      logic [1:0][39:0] credit_granules;
      logic [47:0] starts;
      aou_pkg::flit_clear(flit);
      aou_pkg::pack_crdtgrant(credit_granules,
        32,32,32,32, 32,32,32,32, 32,32,32,32,
        32,32,32,32,  8, 8, 8, 8);
      granules[0] = credit_granules[0];
      granules[1] = credit_granules[1];
      starts = '0;
      starts[0] = 1'b1;
      aou_pkg::flit_put_granules(flit, 0, 2, granules);
      aou_pkg::flit_put_header(flit, 2'b00, starts, 16'h0);
      send_flit(flit);
    endtask

    task send_writeresp(logic [1:0] rp, logic [9:0] id);
      logic [7:0] flit[aou_pkg::FLIT_BYTES];
      logic [39:0] granules[aou_pkg::NUM_GRANULES];
      logic [47:0] starts;
      aou_pkg::flit_clear(flit);
      aou_pkg::pack_writeresp(granules[0], rp, id, 2'b00);
      starts = '0;
      starts[0] = 1'b1;
      aou_pkg::flit_put_granules(flit, 0, 1, granules);
      aou_pkg::flit_put_header(flit, 2'b00, starts, 16'h0);
      send_flit(flit);
    endtask

    task send_readdata(logic [1:0] rp, logic [9:0] id,
                       logic [aou_pkg::AXI_DATA_W-1:0] data);
      logic [7:0] flit[aou_pkg::FLIT_BYTES];
      logic [39:0] granules[aou_pkg::NUM_GRANULES];
      logic [47:0] starts;
      aou_pkg::pack_readdata(granules, rp, id, 2'b00, 1'b1,
                             1024'(data), aou_pkg::AXI_DLENGTH);
      aou_pkg::flit_clear(flit);
      starts = '0;
      starts[0] = 1'b1;
      aou_pkg::flit_put_granules(flit, 0,
        aou_pkg::data_msg_granules(aou_pkg::MSGTYPE_READDATA, aou_pkg::AXI_DLENGTH),
        granules);
      aou_pkg::flit_put_header(flit, 2'b00, starts, 16'h0);
      send_flit(flit);
    endtask

    task send_flit(logic [7:0] flit[aou_pkg::FLIT_BYTES]);
      tx_lock.get(1);
      @(vif.rx_cb);
      for (int unsigned beat = 0; beat < BEAT_COUNT; beat++) begin
        logic [BEAT_BYTES*8-1:0] data;
        for (int unsigned i = 0; i < BEAT_BYTES; i++)
          data[i*8 +: 8] = flit[beat*BEAT_BYTES+i];
        vif.rx_cb.pl_data <= data;
        vif.rx_cb.pl_valid <= 1'b1;
        @(vif.rx_cb);
      end
      vif.rx_cb.pl_valid <= 1'b0;
      vif.rx_cb.pl_flit_cancel <= 1'b0;
      repeat (2) @(vif.rx_cb);
      tx_lock.put(1);
    endtask
  endclass

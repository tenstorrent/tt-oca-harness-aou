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
//  File        : aou_axi_driver.svh
//  Author     : Vinh Trieu, Quang Le
//
// *****************************************************************************
  class aou_axi_seq extends uvm_sequence #(aou_axi_item);
    `uvm_object_utils(aou_axi_seq)

    axi_kind_e  kind;
    bit [9:0]   id;
    bit [63:0]  addr;
    bit [aou_pkg::AXI_DATA_W-1:0] wdata;
    bit [7:0]   len = 8'd0;
    bit [2:0]   size = aou_pkg::AXI_SIZE;
    bit [aou_pkg::AXI_DATA_BYTES-1:0] wstrb = '1;
    aou_axi_item rsp;

    function new(string name = "aou_axi_seq");
      super.new(name);
    endfunction

    task body();
      aou_axi_item req;
      req = aou_axi_item::type_id::create("req");
      start_item(req);
      req.kind  = kind;
      req.id    = id;
      req.addr  = addr;
      req.wdata = wdata;
      req.len   = len;
      req.size  = size;
      req.wstrb = wstrb;
      finish_item(req);
      rsp = req;
    endtask
  endclass

  // -------------------------------------------------------------------
  // AXI sequencer / driver / agent -- binds to the S-port
  // (I_AOU_TX_AXI_S_* / O_AOU_RX_AXI_S_*), i.e. the "local initiator"
  // side. Fully blocking, one transaction at a time -- no pipelining.
  // -------------------------------------------------------------------
  class aou_axi_sequencer extends uvm_sequencer #(aou_axi_item);
    `uvm_component_utils(aou_axi_sequencer)
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
  endclass

  class aou_axi_driver extends uvm_driver #(aou_axi_item);
    `uvm_component_utils(aou_axi_driver)

    virtual aou_axi_if #(.ID_W(10), .ADDR_W(64), .LEN_W(8),
                         .DATA_W(aou_pkg::AXI_DATA_W)) vif;
    local int unsigned driver_epoch;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      driver_epoch = 1;
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual aou_axi_if #(.ID_W(10), .ADDR_W(64),
                                               .LEN_W(8),
                                               .DATA_W(aou_pkg::AXI_DATA_W)))::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", "aou_axi_driver: no aou_axi_if in config_db")
    endfunction

    task run_phase(uvm_phase phase);
      fork
        begin
          forever begin
            @(negedge vif.resetn);
            driver_epoch++;
            vif.awvalid <= 1'b0;
            vif.wvalid  <= 1'b0;
            vif.bready  <= 1'b0;
            vif.arvalid <= 1'b0;
            vif.rready  <= 1'b0;
            `uvm_info("AXIDRV", $sformatf(
                "RESET_AXI_DRIVER_ABORT epoch=%0d", driver_epoch), UVM_LOW)
          end
        end
      join_none
      idle_signals();
      wait (vif.resetn === 1'b1);
      forever begin
        aou_axi_item req;
        wait (vif.resetn === 1'b1);
        seq_item_port.get_next_item(req);
        if (req.kind == AXI_WRITE) do_write(req);
        else                       do_read(req);
        seq_item_port.item_done();
      end
    endtask

    // Drive on the rising edge with nonblocking assignments so DUT sequential
    // logic samples the prior-cycle values and each payload stays stable for
    // the full cycle.
    task idle_signals();
      @(posedge vif.clk);
      vif.awvalid <= 1'b0;
      vif.wvalid  <= 1'b0;
      vif.bready  <= 1'b0;
      vif.arvalid <= 1'b0;
      vif.rready  <= 1'b0;
    endtask

    task do_write(aou_axi_item req);
      bit aw_done, w_done;
      int unsigned cyc;
      int unsigned local_epoch;
      local_epoch = driver_epoch;
      `uvm_info("AXIDRV", $sformatf("do_write: driving AW/W id=%0d addr=%0h", req.id, req.addr), UVM_LOW)
      @(posedge vif.clk);
      if (vif.resetn !== 1'b1 || driver_epoch != local_epoch)
        return;
      vif.awid    <= req.id;
      vif.awaddr  <= req.addr;
      vif.awlen   <= req.len;
      vif.awsize  <= req.size;
      vif.awburst <= 2'b01;
      vif.awlock  <= 1'b0;
      vif.awcache <= 4'h0;
      vif.awprot  <= 3'h0;
      vif.awqos   <= 4'h0;
      vif.awvalid <= 1'b1;
      vif.wdata   <= req.wdata;
      vif.wstrb   <= req.wstrb;
      vif.wlast   <= 1'b1;
      vif.wvalid  <= 1'b1;
      vif.bready  <= 1'b1;

      aw_done = 1'b0; w_done = 1'b0; cyc = 0;
      while (!aw_done || !w_done) begin
        @(posedge vif.clk);
        if (vif.resetn !== 1'b1 || driver_epoch != local_epoch) begin
          vif.awvalid <= 1'b0;
          vif.wvalid  <= 1'b0;
          vif.bready  <= 1'b0;
          `uvm_info("AXIDRV", $sformatf(
              "do_write: reset aborted AW/W id=%0d epoch=%0d", req.id, local_epoch), UVM_LOW)
          return;
        end
        cyc++;
        if (cyc % 200 == 0)
          `uvm_info("AXIDRV", $sformatf("do_write: still waiting after %0d cycles -- awvalid=%0b awready=%0b wvalid=%0b wready=%0b",
                     cyc, vif.awvalid, vif.awready, vif.wvalid, vif.wready), UVM_LOW)
        if (!aw_done && vif.awready) begin
          vif.awvalid <= 1'b0;
          aw_done = 1'b1;
        end
        if (!w_done && vif.wready) begin
          vif.wvalid <= 1'b0;
          w_done = 1'b1;
        end
      end

      cyc = 0;
      do begin
        @(posedge vif.clk);
        if (vif.resetn !== 1'b1 || driver_epoch != local_epoch) begin
          vif.bready <= 1'b0;
          `uvm_info("AXIDRV", $sformatf(
              "do_write: reset aborted waiting for B id=%0d epoch=%0d", req.id, local_epoch), UVM_LOW)
          return;
        end
        cyc++;
        if (cyc % 200 == 0)
          `uvm_info("AXIDRV", $sformatf("do_write: still waiting for B after %0d cycles -- bvalid=%0b", cyc, vif.bvalid), UVM_LOW)
      end while (!vif.bvalid);
      req.bresp = vif.bresp;
      if (vif.bid !== req.id)
        `uvm_error("AXIDRV", $sformatf("write response BID=%0h does not match AWID=%0h", vif.bid, req.id))
      vif.bready <= 1'b0;
      `uvm_info("AXIDRV", $sformatf("do_write: B received, bresp=%0d", req.bresp), UVM_LOW)
    endtask

    task do_read(aou_axi_item req);
      int unsigned local_epoch;
      local_epoch = driver_epoch;
      @(posedge vif.clk);
      if (vif.resetn !== 1'b1 || driver_epoch != local_epoch)
        return;
      vif.arid    <= req.id;
      vif.araddr  <= req.addr;
      vif.arlen   <= req.len;
      vif.arsize  <= req.size;
      vif.arburst <= 2'b01;
      vif.arlock  <= 1'b0;
      vif.arcache <= 4'h0;
      vif.arprot  <= 3'h0;
      vif.arqos   <= 4'h0;
      vif.arvalid <= 1'b1;
      vif.rready  <= 1'b1;

      do begin
        @(posedge vif.clk);
        if (vif.resetn !== 1'b1 || driver_epoch != local_epoch) begin
          vif.arvalid <= 1'b0;
          vif.rready  <= 1'b0;
          `uvm_info("AXIDRV", $sformatf(
              "do_read: reset aborted waiting for AR id=%0d epoch=%0d", req.id, local_epoch), UVM_LOW)
          return;
        end
      end while (!vif.arready);
      vif.arvalid <= 1'b0;

      do begin
        @(posedge vif.clk);
        if (vif.resetn !== 1'b1 || driver_epoch != local_epoch) begin
          vif.rready <= 1'b0;
          `uvm_info("AXIDRV", $sformatf(
              "do_read: reset aborted waiting for R id=%0d epoch=%0d", req.id, local_epoch), UVM_LOW)
          return;
        end
      end while (!vif.rvalid);
      req.rdata = vif.rdata;
      req.rresp = vif.rresp;
      if (vif.rid !== req.id)
        `uvm_error("AXIDRV", $sformatf("read response RID=%0h does not match ARID=%0h", vif.rid, req.id))
      if (vif.rlast !== 1'b1)
        `uvm_error("AXIDRV", $sformatf("single-beat read response RLAST=%b, expected 1", vif.rlast))
      vif.rready <= 1'b0;
    endtask
  endclass

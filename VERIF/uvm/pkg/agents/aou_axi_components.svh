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
//  File        : aou_axi_components.svh
//  Author     : Vinh Trieu, Quang Le
//
// *****************************************************************************
  // AXI initiator agent used by the smoke sequences.
  class aou_axi_agent extends uvm_agent;
    `uvm_component_utils(aou_axi_agent)
    aou_axi_sequencer sqr;
    aou_axi_driver drv;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      sqr = aou_axi_sequencer::type_id::create("sqr", this);
      drv = aou_axi_driver::type_id::create("drv", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction
  endclass

  // Single-beat AXI target for users who extend the environment to exercise
  // the downstream M port. The smoke itself validates the local S port.
  class aou_axi_target_driver extends uvm_component;
    `uvm_component_utils(aou_axi_target_driver)

    virtual aou_axi_if #(.ID_W(10), .ADDR_W(64), .LEN_W(8),
                         .DATA_W(aou_pkg::AXI_DATA_W)) vif;
    local bit [aou_pkg::AXI_DATA_W-1:0] memory[bit [63:0]];

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual aou_axi_if #(.ID_W(10), .ADDR_W(64),
                                               .LEN_W(8), .DATA_W(aou_pkg::AXI_DATA_W)))::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", "aou_axi_target_driver: no aou_axi_if in config_db")
    endfunction

    task run_phase(uvm_phase phase);
      idle_outputs();
      fork
        respond_to_writes();
        respond_to_reads();
      join
    endtask

    task idle_outputs();
      @(vif.target_cb);
      vif.target_cb.awready <= 1'b0;
      vif.target_cb.wready <= 1'b0;
      vif.target_cb.bvalid <= 1'b0;
      vif.target_cb.arready <= 1'b0;
      vif.target_cb.rvalid <= 1'b0;
    endtask

    task respond_to_writes();
      forever begin
        bit [9:0] id;
        bit [63:0] addr;
        bit [aou_pkg::AXI_DATA_W-1:0] data;
        bit [aou_pkg::AXI_DATA_BYTES-1:0] strobe;
        @(vif.target_cb);
        vif.target_cb.awready <= 1'b1;
        do @(vif.target_cb); while (!vif.target_cb.awvalid);
        id = vif.target_cb.awid;
        addr = {vif.target_cb.awaddr[63:int'(aou_pkg::AXI_SIZE)], {aou_pkg::AXI_SIZE{1'b0}}};
        @(vif.target_cb);
        vif.target_cb.awready <= 1'b0;
        vif.target_cb.wready <= 1'b1;
        do @(vif.target_cb); while (!vif.target_cb.wvalid);
        data = vif.target_cb.wdata;
        strobe = vif.target_cb.wstrb;
        @(vif.target_cb);
        vif.target_cb.wready <= 1'b0;
        if (memory.exists(addr)) begin
          for (int byte_i = 0; byte_i < aou_pkg::AXI_DATA_BYTES; byte_i++)
            if (strobe[byte_i]) memory[addr][byte_i*8 +: 8] = data[byte_i*8 +: 8];
        end else begin
          memory[addr] = '0;
          for (int byte_i = 0; byte_i < aou_pkg::AXI_DATA_BYTES; byte_i++)
            if (strobe[byte_i]) memory[addr][byte_i*8 +: 8] = data[byte_i*8 +: 8];
        end
        vif.target_cb.bid <= id;
        vif.target_cb.bresp <= 2'b00;
        vif.target_cb.bvalid <= 1'b1;
        do @(vif.target_cb); while (!vif.target_cb.bready);
        vif.target_cb.bvalid <= 1'b0;
      end
    endtask

    task respond_to_reads();
      forever begin
        bit [9:0] id;
        bit [63:0] addr;
        bit [aou_pkg::AXI_DATA_W-1:0] data;
        @(vif.target_cb);
        vif.target_cb.arready <= 1'b1;
        do @(vif.target_cb); while (!vif.target_cb.arvalid);
        id = vif.target_cb.arid;
        addr = {vif.target_cb.araddr[63:int'(aou_pkg::AXI_SIZE)], {aou_pkg::AXI_SIZE{1'b0}}};
        data = memory.exists(addr) ? memory[addr] : '0;
        @(vif.target_cb);
        vif.target_cb.arready <= 1'b0;
        vif.target_cb.rid <= id;
        vif.target_cb.rdata <= data;
        vif.target_cb.rresp <= 2'b00;
        vif.target_cb.rlast <= 1'b1;
        vif.target_cb.rvalid <= 1'b1;
        do @(vif.target_cb); while (!vif.target_cb.rready);
        vif.target_cb.rvalid <= 1'b0;
      end
    endtask
  endclass

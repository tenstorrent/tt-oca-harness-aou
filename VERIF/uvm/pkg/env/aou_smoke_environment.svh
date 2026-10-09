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
//  File        : aou_smoke_environment.svh
//  Author     : Vinh Trieu, Quang Le
//
// *****************************************************************************
  // APB helper for the smoke's single ACTIVATE_START control write.
  class aou_apb_activator extends uvm_component;
    `uvm_component_utils(aou_apb_activator)
    virtual aou_apb_if #(.ADDR_W(32), .DATA_W(32)) vif;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual aou_apb_if #(.ADDR_W(32), .DATA_W(32)))::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", "aou_apb_activator: no aou_apb_if in config_db")
    endfunction

    task activate();
      vif.psel = 1'b0;
      vif.penable = 1'b0;
      vif.pwrite = 1'b0;
      vif.paddr = '0;
      vif.pwdata = '0;
      wait (vif.presetn === 1'b1);
      repeat (5) @(vif.cb);
      @(vif.cb);
      vif.cb.psel <= 1'b1;
      vif.cb.penable <= 1'b0;
      vif.cb.pwrite <= 1'b1;
      vif.cb.paddr <= 32'h0000_0008;
      vif.cb.pwdata <= 32'h0000_0001;
      @(vif.cb);
      vif.cb.penable <= 1'b1;
      do @(vif.cb); while (vif.cb.pready !== 1'b1);
      if (vif.cb.pslverr !== 1'b0)
        `uvm_error("APB", $sformatf("activation APB transfer PSLVERR=%b", vif.cb.pslverr))
      vif.cb.psel <= 1'b0;
      vif.cb.penable <= 1'b0;
      vif.cb.pwrite <= 1'b0;
      vif.cb.paddr <= '0;
      vif.cb.pwdata <= '0;
    endtask
  endclass

  class aou_env extends uvm_env;
    `uvm_component_utils(aou_env)

    localparam int RP_COUNT = `AOU_RP_COUNT;
    aou_axi_agent axi_agt[RP_COUNT];
    aou_axi_target_driver m_drv[RP_COUNT];
    aou_fdi_tx_monitor fdi_tx_mon;
    aou_smoke_peer fdi_rx_drv;
    aou_apb_activator apb_act;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      for (int i = 0; i < RP_COUNT; i++) begin
        axi_agt[i] = aou_axi_agent::type_id::create($sformatf("axi_agt[%0d]", i), this);
        m_drv[i] = aou_axi_target_driver::type_id::create($sformatf("m_drv[%0d]", i), this);
      end
      fdi_tx_mon = aou_fdi_tx_monitor::type_id::create("fdi_tx_mon", this);
      fdi_rx_drv = aou_smoke_peer::type_id::create("fdi_rx_drv", this);
      apb_act = aou_apb_activator::type_id::create("apb_act", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      fdi_tx_mon.ap.connect(fdi_rx_drv.msg_imp);
    endfunction
  endclass

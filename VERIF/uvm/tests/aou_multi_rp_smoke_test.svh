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
//  File        : aou_multi_rp_smoke_test.svh
//  Author     : Vinh Trieu, Quang Le
//
// *****************************************************************************
  class aou_multi_rp_smoke_test extends uvm_test;
    `uvm_component_utils(aou_multi_rp_smoke_test)

    aou_env env;
    virtual aou_status_if.mon status_vif;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      env = aou_env::type_id::create("env", this);
      if (!uvm_config_db#(virtual aou_status_if.mon)::get(this, "", "status_vif", status_vif))
        `uvm_fatal("NOVIF", "aou_multi_rp_smoke_test: no aou_status_if in config_db")
    endfunction

    virtual task establish_link();
      env.apb_act.activate();
      `uvm_info("TEST", "APB activate_start written -- waiting for AoU ENABLED", UVM_LOW)
      fork : wait_for_link
        begin
          wait (status_vif.activate_st_enabled === 1'b1);
        end
        begin
          #10000;
          `uvm_fatal("LINK_TIMEOUT", "AoU did not report ENABLED within 10000 time units")
        end
      join_any
      disable wait_for_link;
      `uvm_info("TEST", "AoU interface reports ENABLED", UVM_LOW)
    endtask

    task check_clean_status(string checkpoint);
      if (status_vif.req_linkreset !== 1'b0 ||
          status_vif.o_aou_req_linkreset !== 1'b0 ||
          status_vif.int_si0_id_mismatch !== 1'b0 ||
          status_vif.int_mi0_id_mismatch !== 1'b0 ||
          status_vif.int_early_resp_err !== 1'b0)
        `uvm_error("CLEAN_STATUS", $sformatf(
          "%s: linkreset=%b req_linkreset=%b SI0_ID_MISMATCH=%b MI0_ID_MISMATCH=%b EARLY_RESP_ERR=%b",
          checkpoint, status_vif.req_linkreset, status_vif.o_aou_req_linkreset,
          status_vif.int_si0_id_mismatch, status_vif.int_mi0_id_mismatch,
          status_vif.int_early_resp_err))
    endtask

    task run_phase(uvm_phase phase);
      phase.raise_objection(this);
      fork : smoke_watchdog
        begin : watchdog
          #500us;
          `uvm_fatal("SMOKE_WATCHDOG", "AoU multi-RP smoke exceeded 500 us")
        end
        begin : smoke_body
          establish_link();
          check_clean_status("after link establishment");

          // One write and one read on each RP's local AXI interface.
          for (int rp = 0; rp < aou_env::RP_COUNT; rp++) begin
            aou_axi_seq wr, rd;
            bit [63:0] addr = 64'h0000_0000_0000_0100 + (64'(rp) << 12);
            bit [aou_pkg::AXI_DATA_W-1:0] wdata =
                aou_pkg::AXI_DATA_W'(256'hA5A5_A5A5_A5A5_A5A5_1234_5678_9ABC_DEF0_0F0F_0F0F_0F0F_0F0F_CAFE_BABE_0000_0001 + rp);

            `uvm_info("TEST", $sformatf("--- RP%0d: write/read round trip ---", rp), UVM_LOW)
            wr = aou_axi_seq::type_id::create($sformatf("wr_rp%0d", rp));
            wr.kind = AXI_WRITE; wr.id = 10'(10'h100 + rp); wr.addr = addr; wr.wdata = wdata;
            wr.start(env.axi_agt[rp].sqr);
            if (wr.rsp.bresp !== 2'b00)
              `uvm_error("TEST", $sformatf("RP%0d write BRESP=%0d, expected OKAY(0)", rp, wr.rsp.bresp))
            else
              `uvm_info("TEST", $sformatf("RP%0d write completed, BRESP=OKAY", rp), UVM_LOW)

            rd = aou_axi_seq::type_id::create($sformatf("rd_rp%0d", rp));
            rd.kind = AXI_READ; rd.id = 10'(10'h200 + rp); rd.addr = addr;
            rd.start(env.axi_agt[rp].sqr);
            if (rd.rsp.rresp !== 2'b00)
              `uvm_error("TEST", $sformatf("RP%0d read RRESP=%0d, expected OKAY(0)", rp, rd.rsp.rresp))
            else if (rd.rsp.rdata !== wdata)
              `uvm_error("TEST", $sformatf("RP%0d read-back MISMATCH: wrote %h, read %h", rp, wdata, rd.rsp.rdata))
            else
              `uvm_info("TEST", $sformatf("RP%0d read-back matches write data", rp), UVM_LOW)
            check_clean_status($sformatf("after RP%0d write/read round trip", rp));
          end

          #50;
          check_clean_status("before PASS");
          $display("AOU_MULTI_RP_SMOKE_RESULT=PASS rp_count=%0d", aou_env::RP_COUNT);
        end
      join_any
      disable smoke_watchdog;
      phase.drop_objection(this);
    endtask
  endclass

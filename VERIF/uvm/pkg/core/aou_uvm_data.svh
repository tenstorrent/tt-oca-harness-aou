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
//  File        : aou_uvm_data.svh
//  Author     : Vinh Trieu, Quang Le
//
// *****************************************************************************
  typedef enum { AXI_WRITE, AXI_READ } axi_kind_e;

  // One single-beat transaction used by the smoke's local AXI initiator.
  class aou_axi_item extends uvm_sequence_item;
    rand axi_kind_e kind;
    rand bit [9:0] id;
    rand bit [63:0] addr;
    bit [7:0] len = 0;
    bit [2:0] size = aou_pkg::AXI_SIZE;
    rand bit [aou_pkg::AXI_DATA_W-1:0] wdata;
    bit [aou_pkg::AXI_DATA_BYTES-1:0] wstrb = '1;
    bit [1:0] bresp;
    bit [aou_pkg::AXI_DATA_W-1:0] rdata;
    bit [1:0] rresp;

    `uvm_object_utils(aou_axi_item)

    function new(string name = "aou_axi_item");
      super.new(name);
    endfunction
  endclass

  // One decoded FDI message passed from the passive monitor to the peer.
  class aou_fdi_msg_item extends uvm_sequence_item;
    aou_pkg::msgtype_e msgtype;
    logic [3:0] wire_msgtype;
    logic [1:0] dlength;
    int unsigned granule_cost;
    int unsigned start_granule;
    int unsigned continuation_flits;
    bit spans_flit;
    bit [1:0] rp;
    bit [1:0] fdid;
    bit [2:0] miscop;
    bit [3:0] actop;
    bit [9:0] id;
    bit [63:0] addr;
    bit [7:0] len;
    bit [2:0] size;
    bit lock;
    bit [3:0] cache;
    bit [2:0] prot;
    bit [3:0] qos;
    bit [3:0] profextlen;
    bit [11:0] prof;
    bit req_rsvd_zero;
    bit [aou_pkg::AXI_DATA_W-1:0] data;
    logic [1023:0] full_data;
    bit full_data_valid;
    bit [aou_pkg::AXI_DATA_BYTES-1:0] strb;
    bit [1:0] resp;
    bit rlast;
    longint unsigned observed_cycle;
    longint unsigned source_message_order;
    bit source_message_order_valid;
    int unsigned endpoint_id;
    int unsigned epoch;
    string observation_direction;
    int unsigned crdt_rreqcred0;
    int unsigned crdt_rdatacred0;
    int unsigned crdt_wreqcred[4];
    int unsigned crdt_rreqcred[4];
    int unsigned crdt_wdatacred[4];
    int unsigned crdt_rdatacred[4];
    int unsigned crdt_wrespcred[4];
    logic [2:0] crdt_wreqcred_enc[4];
    logic [2:0] crdt_rreqcred_enc[4];
    logic [2:0] crdt_wdatacred_enc[4];
    logic [2:0] crdt_rdatacred_enc[4];
    logic [1:0] crdt_wrespcred_enc[4];
    bit crdt_rsvd_zero;
    logic [15:0] hdr_msg_credit_raw;
    int unsigned hdr_wreqcred, hdr_rreqcred, hdr_wdatacred, hdr_rdatacred, hdr_wrespcred;

    `uvm_object_utils(aou_fdi_msg_item)
    function new(string name = "aou_fdi_msg_item");
      super.new(name);
      for (int rp_i = 0; rp_i < 4; rp_i++) begin
        crdt_wreqcred[rp_i] = 0;
        crdt_rreqcred[rp_i] = 0;
        crdt_wdatacred[rp_i] = 0;
        crdt_rdatacred[rp_i] = 0;
        crdt_wrespcred[rp_i] = 0;
        crdt_wreqcred_enc[rp_i] = '0;
        crdt_rreqcred_enc[rp_i] = '0;
        crdt_wdatacred_enc[rp_i] = '0;
        crdt_rdatacred_enc[rp_i] = '0;
        crdt_wrespcred_enc[rp_i] = '0;
      end
    endfunction
  endclass

// *****************************************************************************
// SPDX-License-Identifier: Apache-2.0
// *****************************************************************************
//  Copyright (c) 2026 BOS Semiconductors
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
//  Module     : AOU_AXI4MUX_3X1_512
//  Version    : 1.00
//  Date       : 26-02-26
//  Author     : Soyoung Min, Jaeyun Lee, Hojun Lee, Kwanho Kim
//
// *****************************************************************************

`timescale 1ns/1ps

module AOU_AXI4MUX_3X1_512 #(
    parameter   DATA_WD   = 512,
    parameter   ADDR_WD   = 64,
    parameter   ID_WD     = 10,
    parameter   STRB_WD   = DATA_WD / 8,
    parameter   LEN_WD    = 8,

    parameter   RD_MO_CNT = 64,
    parameter   WR_MO_CNT = 64,

    localparam  RD_MO_IDX_WD = $clog2(RD_MO_CNT)
)
(
    input                               I_CLK,
    input                               I_RESETN,

    // CH0 Slave I/F (256 bit)
    input       [ ID_WD-1: 0]           I_S_ARID_0,
    input       [ ADDR_WD-1: 0]         I_S_ARADDR_0,
    input       [ 2: 0]                 I_S_ARSIZE_0,
    input       [ 1: 0]                 I_S_ARBURST_0,
    input       [ 3: 0]                 I_S_ARCACHE_0,
    input       [ 2: 0]                 I_S_ARPROT_0,
    input       [ LEN_WD-1: 0]          I_S_ARLEN_0,
    input                               I_S_ARLOCK_0,
    input       [ 3: 0]                 I_S_ARQOS_0,
    input       [15: 0]                 I_S_ARUSER_0,
    input                               I_S_ARVALID_0,
    output wire                         O_S_ARREADY_0,

    output wire [ ID_WD-1: 0]           O_S_RID_0,
    output wire [ 255: 0]               O_S_RDATA_0,
    output wire [ 1: 0]                 O_S_RRESP_0,
    output wire [15: 0]                 O_S_RUSER_0,
    output wire                         O_S_RLAST_0,
    output wire                         O_S_RVALID_0,
    input                               I_S_RREADY_0,
 
    input       [ ID_WD-1: 0]           I_S_AWID_0,
    input       [ ADDR_WD-1: 0]         I_S_AWADDR_0,
    input       [ LEN_WD-1: 0]          I_S_AWLEN_0,
    input       [ 2: 0]                 I_S_AWSIZE_0,
    input       [ 1: 0]                 I_S_AWBURST_0,
    input                               I_S_AWLOCK_0,
    input       [ 3: 0]                 I_S_AWCACHE_0,
    input       [ 2: 0]                 I_S_AWPROT_0,
    input       [ 3: 0]                 I_S_AWQOS_0,
    input       [15: 0]                 I_S_AWUSER_0,
    input                               I_S_AWVALID_0,
    output wire                         O_S_AWREADY_0,

    input       [ 255 : 0]              I_S_WDATA_0,
    input       [ 31  : 0]              I_S_WSTRB_0,
    input                               I_S_WLAST_0,
    input       [15: 0]                 I_S_WUSER_0,
    input                               I_S_WVALID_0,
    output                              O_S_WREADY_0,

    output wire [ ID_WD-1: 0]           O_S_BID_0,
    output wire [ 1: 0]                 O_S_BRESP_0,
    output wire [15: 0]                 O_S_BUSER_0,
    output wire                         O_S_BVALID_0,
    input                               I_S_BREADY_0,

    // CH1 Slave I/F (512bit)
    input       [ ID_WD-1: 0]           I_S_ARID_1,
    input       [ ADDR_WD-1: 0]         I_S_ARADDR_1,
    input       [ 2: 0]                 I_S_ARSIZE_1,
    input       [ 1: 0]                 I_S_ARBURST_1,
    input       [ 3: 0]                 I_S_ARCACHE_1,
    input       [ 2: 0]                 I_S_ARPROT_1,
    input       [ LEN_WD-1: 0]          I_S_ARLEN_1,
    input                               I_S_ARLOCK_1,
    input       [ 3: 0]                 I_S_ARQOS_1,
    input       [15: 0]                 I_S_ARUSER_1,
    input                               I_S_ARVALID_1,
    output wire                         O_S_ARREADY_1,

    output wire [ ID_WD-1: 0]           O_S_RID_1,
    output wire [ 511 : 0]              O_S_RDATA_1,
    output wire [ 1: 0]                 O_S_RRESP_1,
    output wire [15: 0]                 O_S_RUSER_1,
    output wire                         O_S_RLAST_1,
    output wire                         O_S_RVALID_1,
    input                               I_S_RREADY_1,       

    input       [ ID_WD-1: 0]           I_S_AWID_1,
    input       [ ADDR_WD-1: 0]         I_S_AWADDR_1,
    input       [ LEN_WD-1: 0]          I_S_AWLEN_1,
    input       [ 2: 0]                 I_S_AWSIZE_1,
    input       [ 1: 0]                 I_S_AWBURST_1,
    input                               I_S_AWLOCK_1,
    input       [ 3: 0]                 I_S_AWCACHE_1,
    input       [ 2: 0]                 I_S_AWPROT_1,
    input       [ 3: 0]                 I_S_AWQOS_1,
    input       [15: 0]                 I_S_AWUSER_1,
    input                               I_S_AWVALID_1,
    output wire                         O_S_AWREADY_1,

    input       [ 511: 0]               I_S_WDATA_1,
    input       [ 63: 0]                I_S_WSTRB_1,  //WSTRB width = wdata width / 8
    input                               I_S_WLAST_1,
    input       [15: 0]                 I_S_WUSER_1,
    input                               I_S_WVALID_1,
    output wire                         O_S_WREADY_1,

    output wire [ ID_WD-1: 0]           O_S_BID_1,
    output wire [ 1: 0]                 O_S_BRESP_1,
    output wire [15: 0]                 O_S_BUSER_1,
    output wire                         O_S_BVALID_1,       
    input                               I_S_BREADY_1,

    // CH2 Slave I/F (1024bit)
    input       [ ID_WD-1: 0]           I_S_ARID_2,
    input       [ ADDR_WD-1: 0]         I_S_ARADDR_2,
    input       [ 2: 0]                 I_S_ARSIZE_2,
    input       [ 1: 0]                 I_S_ARBURST_2,
    input       [ 3: 0]                 I_S_ARCACHE_2,
    input       [ 2: 0]                 I_S_ARPROT_2,
    input       [ LEN_WD-1: 0]          I_S_ARLEN_2,
    input                               I_S_ARLOCK_2,
    input       [ 3: 0]                 I_S_ARQOS_2,
    input       [15: 0]                 I_S_ARUSER_2,
    input                               I_S_ARVALID_2,
    output wire                         O_S_ARREADY_2,

    output wire [ ID_WD-1: 0]           O_S_RID_2,
    output wire [ 1023: 0]              O_S_RDATA_2,
    output wire [ 1: 0]                 O_S_RRESP_2,
    output wire [15: 0]                 O_S_RUSER_2,
    output wire                         O_S_RLAST_2,
    output wire                         O_S_RVALID_2,
    input                               I_S_RREADY_2,       

    input       [ ID_WD-1: 0]           I_S_AWID_2,
    input       [ ADDR_WD-1: 0]         I_S_AWADDR_2,
    input       [ LEN_WD-1: 0]          I_S_AWLEN_2,
    input       [ 2: 0]                 I_S_AWSIZE_2,
    input       [ 1: 0]                 I_S_AWBURST_2,
    input                               I_S_AWLOCK_2,
    input       [ 3: 0]                 I_S_AWCACHE_2,
    input       [ 2: 0]                 I_S_AWPROT_2,
    input       [ 3: 0]                 I_S_AWQOS_2,
    input       [15: 0]                 I_S_AWUSER_2,
    input                               I_S_AWVALID_2,
    output wire                         O_S_AWREADY_2,

    input       [ 1023: 0]              I_S_WDATA_2,
    input       [ 127: 0]               I_S_WSTRB_2,
    input                               I_S_WLAST_2,
    input       [15: 0]                 I_S_WUSER_2,
    input                               I_S_WVALID_2,
    output wire                         O_S_WREADY_2,

    output wire [ ID_WD-1: 0]           O_S_BID_2,
    output wire [ 1: 0]                 O_S_BRESP_2,
    output wire [15: 0]                 O_S_BUSER_2,
    output wire                         O_S_BVALID_2,       
    input                               I_S_BREADY_2,

    // Master I/F (512bit)
    output wire [ ID_WD+1: 0]           O_M_ARID,
    output wire [ ADDR_WD-1: 0]         O_M_ARADDR,
    output wire [ 2: 0]                 O_M_ARSIZE,
    output wire [ 1: 0]                 O_M_ARBURST,
    output wire [ 3: 0]                 O_M_ARCACHE,
    output wire [ 2: 0]                 O_M_ARPROT,
    output wire [ LEN_WD-1: 0]          O_M_ARLEN,
    output wire                         O_M_ARLOCK,
    output wire [ 3: 0]                 O_M_ARQOS,
    output wire [15: 0]                 O_M_ARUSER,
    output wire                         O_M_ARVALID,
    input                               I_M_ARREADY,

    input       [ ID_WD+1: 0]           I_M_RID,
    input       [ DATA_WD-1: 0]         I_M_RDATA,
    input       [ 1: 0]                 I_M_RRESP,
    input       [15: 0]                 I_M_RUSER,
    input                               I_M_RLAST,
    input       [ ADDR_WD-1: 0]         I_M_ADDR_CNT,
    input                               I_M_RVALID,
    output wire                         O_M_RREADY,

    output wire [ ID_WD+1: 0]           O_M_AWID,
    output wire [ ADDR_WD-1: 0]         O_M_AWADDR,
    output wire [ LEN_WD-1: 0]          O_M_AWLEN,
    output wire [ 2: 0]                 O_M_AWSIZE,
    output wire [ 1: 0]                 O_M_AWBURST,
    output wire                         O_M_AWLOCK,
    output wire [ 3: 0]                 O_M_AWCACHE,
    output wire [ 2: 0]                 O_M_AWPROT,
    output wire [ 3: 0]                 O_M_AWQOS,
    output wire [15: 0]                 O_M_AWUSER,
    output wire                         O_M_AWVALID,
    input                               I_M_AWREADY,      

    output wire [ DATA_WD-1: 0]         O_M_WDATA,
    output wire [ STRB_WD-1: 0]         O_M_WSTRB,
    output wire                         O_M_WLAST,
    output wire [15: 0]                 O_M_WUSER,
    output wire                         O_M_WVALID,
    input                               I_M_WREADY,

    input       [ ID_WD+1: 0]           I_M_BID,
    input       [ 1: 0]                 I_M_BRESP,
    input       [15: 0]                 I_M_BUSER,
    input                               I_M_BVALID,
    output wire                         O_M_BREADY,

    output      [ ID_WD-1: 0]           O_DOWN1024_MISMATCH_RID,
    output                              O_DOWN1024_RID_MISMATCH_ERROR
);

localparam W_WD = DATA_WD + STRB_WD + 1 + 16; // WLAST + WUSER
localparam AXI_AWCH_PAYLOAD_WD = ID_WD+2 + ADDR_WD + LEN_WD + 3 + 2 + 1 + 4+ 3 + 4 + 16; // + AWUSER

wire [ ID_WD-1: 0]           up_s_awid_0;
wire [ ADDR_WD-1: 0]         up_s_awaddr_0;
wire [ LEN_WD-1: 0]          up_s_awlen_0;
wire [ 2: 0]                 up_s_awsize_0;
wire [ 1: 0]                 up_s_awburst_0;
wire                         up_s_awlock_0;
wire [ 3: 0]                 up_s_awcache_0;
wire [ 2: 0]                 up_s_awprot_0;
wire [ 4-1: 0]               up_s_awqos_0;
wire [15: 0]                 up_s_awuser_0;
wire                         up_s_awvalid_0;
wire                         up_s_awready_0;

wire [ DATA_WD-1: 0]         up_s_wdata_0;
wire [ STRB_WD-1: 0]         up_s_wstrb_0;
wire                         up_s_wlast_0;
wire [15: 0]                 up_s_wuser_0;
wire                         up_s_wvalid_0;
wire                         up_s_wready_0;

wire [ ID_WD-1: 0]           up_s_bid_0;
wire [ 1: 0]                 up_s_bresp_0;
wire [15: 0]                 up_s_buser_0;
wire                         up_s_bvalid_0;       
wire                         up_s_bready_0;

wire [ ID_WD-1: 0]           up_s_arid_0;
wire [ ADDR_WD-1: 0]         up_s_araddr_0;
wire [ 2: 0]                 up_s_arsize_0;
wire [ 1: 0]                 up_s_arburst_0;
wire [ 3: 0]                 up_s_arcache_0;
wire [ 2: 0]                 up_s_arprot_0;
wire [ LEN_WD-1: 0]          up_s_arlen_0;
wire                         up_s_arlock_0;
wire [ 4-1: 0]               up_s_arqos_0;
wire [15: 0]                 up_s_aruser_0;
wire                         up_s_arvalid_0;
wire                         up_s_arready_0;

wire [ ID_WD-1: 0]           up_s_rid_0;
wire [ DATA_WD-1: 0]         up_s_rdata_0;
wire [ 1: 0]                 up_s_rresp_0;
wire [15: 0]                 up_s_ruser_0;
wire                         up_s_rlast_0;
wire [ ADDR_WD-1: 0]         up_s_addr_cnt_0;
wire                         up_s_rvalid_0;
wire                         up_s_rready_0;       


wire [ ID_WD-1: 0]           dn_s_awid_2;
wire [ ADDR_WD-1: 0]         dn_s_awaddr_2;
wire [ LEN_WD-1: 0]          dn_s_awlen_2;
wire [ 2: 0]                 dn_s_awsize_2;
wire [ 1: 0]                 dn_s_awburst_2;
wire                         dn_s_awlock_2;
wire [ 3: 0]                 dn_s_awcache_2;
wire [ 2: 0]                 dn_s_awprot_2;
wire [ 4-1: 0]               dn_s_awqos_2;
wire [15: 0]                 dn_s_awuser_2;
wire                         dn_s_awvalid_2;
wire                         dn_s_awready_2;

wire [ DATA_WD-1: 0]         dn_s_wdata_2;
wire [ STRB_WD-1: 0]         dn_s_wstrb_2;
wire                         dn_s_wlast_2;
wire [15: 0]                 dn_s_wuser_2;
wire                         dn_s_wvalid_2;
wire                         dn_s_wready_2;

wire [ ID_WD-1: 0]           dn_s_bid_2;
wire [ 1: 0]                 dn_s_bresp_2;
wire [15: 0]                 dn_s_buser_2;
wire                         dn_s_bvalid_2;       
wire                         dn_s_bready_2;

wire [ ID_WD-1: 0]           dn_s_arid_2;
wire [ ADDR_WD-1: 0]         dn_s_araddr_2;
wire [ 2: 0]                 dn_s_arsize_2;
wire [ 1: 0]                 dn_s_arburst_2;
wire [ 3: 0]                 dn_s_arcache_2;
wire [ 2: 0]                 dn_s_arprot_2;
wire [ LEN_WD-1: 0]          dn_s_arlen_2;
wire                         dn_s_arlock_2;
wire [ 3:0]                  dn_s_arqos_2;
wire [15: 0]                 dn_s_aruser_2;
wire                         dn_s_arvalid_2;
wire                         dn_s_arready_2;

wire [ ID_WD-1: 0]           dn_s_rid_2;
wire [ DATA_WD-1: 0]         dn_s_rdata_2;
wire [ 1: 0]                 dn_s_rresp_2;
wire [15: 0]                 dn_s_ruser_2;
wire                         dn_s_rlast_2;
wire                         dn_s_rvalid_2;
wire                         dn_s_rready_2;       

AOU_AXI_UP #(
    .I_DATA_WD     ( 256             ),
    .O_DATA_WD     ( DATA_WD         ),
    .ADDR_WD       ( ADDR_WD         ),
    .ID_WD         ( ID_WD           ),
    .LEN_WD        ( LEN_WD          )
) u_axi_up_256_512 
(
    .I_CLK         ( I_CLK           ),
    .I_RESETN      ( I_RESETN        ),

    .I_S_ARID      ( I_S_ARID_0      ),
    .I_S_ARADDR    ( I_S_ARADDR_0    ),
    .I_S_ARSIZE    ( I_S_ARSIZE_0    ),
    .I_S_ARBURST   ( I_S_ARBURST_0   ),
    .I_S_ARCACHE   ( I_S_ARCACHE_0   ),
    .I_S_ARPROT    ( I_S_ARPROT_0    ),
    .I_S_ARLEN     ( I_S_ARLEN_0     ),
    .I_S_ARLOCK    ( I_S_ARLOCK_0    ),
    .I_S_ARQOS     ( I_S_ARQOS_0     ),
    .I_S_ARUSER    ( I_S_ARUSER_0    ),
    .I_S_ARVALID   ( I_S_ARVALID_0   ),
    .O_S_ARREADY   ( O_S_ARREADY_0   ),

    .O_S_RID       ( O_S_RID_0       ),
    .O_S_RDATA     ( O_S_RDATA_0     ),
    .O_S_RRESP     ( O_S_RRESP_0     ),
    .O_S_RUSER     ( O_S_RUSER_0     ),
    .O_S_RLAST     ( O_S_RLAST_0     ),
    .O_S_RVALID    ( O_S_RVALID_0    ),
    .I_S_RREADY    ( I_S_RREADY_0    ),

    .I_S_AWID      ( I_S_AWID_0      ),
    .I_S_AWADDR    ( I_S_AWADDR_0    ),
    .I_S_AWLEN     ( I_S_AWLEN_0     ),
    .I_S_AWSIZE    ( I_S_AWSIZE_0    ),
    .I_S_AWBURST   ( I_S_AWBURST_0   ),
    .I_S_AWLOCK    ( I_S_AWLOCK_0    ),
    .I_S_AWCACHE   ( I_S_AWCACHE_0   ),
    .I_S_AWPROT    ( I_S_AWPROT_0    ),
    .I_S_AWQOS     ( I_S_AWQOS_0     ),
    .I_S_AWUSER    ( I_S_AWUSER_0    ),
    .I_S_AWVALID   ( I_S_AWVALID_0   ),
    .O_S_AWREADY   ( O_S_AWREADY_0   ),

    .I_S_WDATA     ( I_S_WDATA_0     ),
    .I_S_WSTRB     ( I_S_WSTRB_0     ),  
    .I_S_WLAST     ( I_S_WLAST_0     ),
    .I_S_WUSER     ( I_S_WUSER_0     ),
    .I_S_WVALID    ( I_S_WVALID_0    ),
    .O_S_WREADY    ( O_S_WREADY_0    ),

    .O_S_BID       ( O_S_BID_0       ),
    .O_S_BRESP     ( O_S_BRESP_0     ),
    .O_S_BUSER     ( O_S_BUSER_0     ),
    .O_S_BVALID    ( O_S_BVALID_0    ),
    .I_S_BREADY    ( I_S_BREADY_0    ),

    .O_M_ARID      ( up_s_arid_0     ),
    .O_M_ARADDR    ( up_s_araddr_0   ),
    .O_M_ARSIZE    ( up_s_arsize_0   ),
    .O_M_ARBURST   ( up_s_arburst_0  ),
    .O_M_ARCACHE   ( up_s_arcache_0  ),
    .O_M_ARPROT    ( up_s_arprot_0   ),
    .O_M_ARLEN     ( up_s_arlen_0    ),
    .O_M_ARLOCK    ( up_s_arlock_0   ),
    .O_M_ARQOS     ( up_s_arqos_0    ),
    .O_M_ARUSER    ( up_s_aruser_0   ),
    .O_M_ARVALID   ( up_s_arvalid_0  ),
    .I_M_ARREADY   ( up_s_arready_0  ),

    .I_M_RID       ( up_s_rid_0      ),
    .I_M_RDATA     ( up_s_rdata_0    ),
    .I_M_RRESP     ( up_s_rresp_0    ),
    .I_M_RUSER     ( up_s_ruser_0    ),
    .I_M_RLAST     ( up_s_rlast_0    ),
    .I_M_ADDR_CNT  ( up_s_addr_cnt_0 ),
    .I_M_RVALID    ( up_s_rvalid_0   ),
    .O_M_RREADY    ( up_s_rready_0   ),

    .O_M_AWID      ( up_s_awid_0     ),
    .O_M_AWADDR    ( up_s_awaddr_0   ),
    .O_M_AWLEN     ( up_s_awlen_0    ),
    .O_M_AWSIZE    ( up_s_awsize_0   ),
    .O_M_AWBURST   ( up_s_awburst_0  ),
    .O_M_AWLOCK    ( up_s_awlock_0   ),
    .O_M_AWCACHE   ( up_s_awcache_0  ),
    .O_M_AWPROT    ( up_s_awprot_0   ),
    .O_M_AWQOS     ( up_s_awqos_0    ),
    .O_M_AWUSER    ( up_s_awuser_0   ),
    .O_M_AWVALID   ( up_s_awvalid_0  ),
    .I_M_AWREADY   ( up_s_awready_0  ),

    .O_M_WDATA     ( up_s_wdata_0    ),
    .O_M_WSTRB     ( up_s_wstrb_0    ),
    .O_M_WLAST     ( up_s_wlast_0    ),
    .O_M_WUSER     ( up_s_wuser_0    ),
    .O_M_WVALID    ( up_s_wvalid_0   ),
    .I_M_WREADY    ( up_s_wready_0   ),

    .I_M_BID       ( up_s_bid_0      ),
    .I_M_BRESP     ( up_s_bresp_0    ),
    .I_M_BUSER     ( up_s_buser_0    ),
    .I_M_BVALID    ( up_s_bvalid_0   ),
    .O_M_BREADY    ( up_s_bready_0   )

);

AOU_AXI_DOWN #(
    .I_DATA_WD     ( 1024            ),
    .O_DATA_WD     ( DATA_WD         ),
    .ADDR_WD       ( ADDR_WD         ),
    .ID_WD         ( ID_WD           ),
    .LEN_WD        ( LEN_WD          ),

    .RD_MO_CNT     ( RD_MO_CNT        ),
    .WR_MO_CNT     ( WR_MO_CNT        )
) u_axi_dn_1024_512 
(
    .I_CLK         ( I_CLK           ),
    .I_RESETN      ( I_RESETN        ),

    .I_S_ARID      ( I_S_ARID_2      ),
    .I_S_ARADDR    ( I_S_ARADDR_2    ),
    .I_S_ARSIZE    ( I_S_ARSIZE_2    ),
    .I_S_ARBURST   ( I_S_ARBURST_2   ),
    .I_S_ARCACHE   ( I_S_ARCACHE_2   ),
    .I_S_ARPROT    ( I_S_ARPROT_2    ),
    .I_S_ARLEN     ( I_S_ARLEN_2     ),
    .I_S_ARLOCK    ( I_S_ARLOCK_2    ),
    .I_S_ARQOS     ( I_S_ARQOS_2     ),
    .I_S_ARUSER    ( I_S_ARUSER_2    ),
    .I_S_ARVALID   ( I_S_ARVALID_2   ),
    .O_S_ARREADY   ( O_S_ARREADY_2   ),

    .O_S_RID       ( O_S_RID_2       ),
    .O_S_RDATA     ( O_S_RDATA_2     ),
    .O_S_RRESP     ( O_S_RRESP_2     ),
    .O_S_RUSER     ( O_S_RUSER_2     ),
    .O_S_RLAST     ( O_S_RLAST_2     ),
    .O_S_RVALID    ( O_S_RVALID_2    ),
    .I_S_RREADY    ( I_S_RREADY_2    ),

    .I_S_AWID      ( I_S_AWID_2      ),
    .I_S_AWADDR    ( I_S_AWADDR_2    ),
    .I_S_AWLEN     ( I_S_AWLEN_2     ),
    .I_S_AWSIZE    ( I_S_AWSIZE_2    ),
    .I_S_AWBURST   ( I_S_AWBURST_2   ),
    .I_S_AWLOCK    ( I_S_AWLOCK_2    ),
    .I_S_AWCACHE   ( I_S_AWCACHE_2   ),
    .I_S_AWPROT    ( I_S_AWPROT_2    ),
    .I_S_AWQOS     ( I_S_AWQOS_2     ),
    .I_S_AWUSER    ( I_S_AWUSER_2    ),
    .I_S_AWVALID   ( I_S_AWVALID_2   ),
    .O_S_AWREADY   ( O_S_AWREADY_2   ),

    .I_S_WDATA     ( I_S_WDATA_2     ),
    .I_S_WSTRB     ( I_S_WSTRB_2     ),  
    .I_S_WLAST     ( I_S_WLAST_2     ),
    .I_S_WUSER     ( I_S_WUSER_2     ),
    .I_S_WVALID    ( I_S_WVALID_2    ),
    .O_S_WREADY    ( O_S_WREADY_2    ),

    .O_S_BID       ( O_S_BID_2       ),
    .O_S_BRESP     ( O_S_BRESP_2     ),
    .O_S_BUSER     ( O_S_BUSER_2     ),
    .O_S_BVALID    ( O_S_BVALID_2    ),
    .I_S_BREADY    ( I_S_BREADY_2    ),

    .O_M_ARID      ( dn_s_arid_2     ),
    .O_M_ARADDR    ( dn_s_araddr_2   ),
    .O_M_ARLEN     ( dn_s_arlen_2    ),
    .O_M_ARLOCK    ( dn_s_arlock_2   ),
    .O_M_ARSIZE    ( dn_s_arsize_2   ),
    .O_M_ARBURST   ( dn_s_arburst_2  ),
    .O_M_ARCACHE   ( dn_s_arcache_2  ),
    .O_M_ARPROT    ( dn_s_arprot_2   ),
    .O_M_ARQOS     ( dn_s_arqos_2    ),
    .O_M_ARUSER    ( dn_s_aruser_2   ),
    .O_M_ARVALID   ( dn_s_arvalid_2  ),
    .I_M_ARREADY   ( dn_s_arready_2  ),

    .I_M_RID       ( dn_s_rid_2      ),
    .I_M_RDATA     ( dn_s_rdata_2    ),
    .I_M_RRESP     ( dn_s_rresp_2    ),
    .I_M_RUSER     ( dn_s_ruser_2    ),
    .I_M_RLAST     ( dn_s_rlast_2    ),
    .I_M_RVALID    ( dn_s_rvalid_2   ),
    .O_M_RREADY    ( dn_s_rready_2   ),

    .O_M_AWID      ( dn_s_awid_2     ),
    .O_M_AWADDR    ( dn_s_awaddr_2   ),
    .O_M_AWLEN     ( dn_s_awlen_2    ),
    .O_M_AWSIZE    ( dn_s_awsize_2   ),
    .O_M_AWBURST   ( dn_s_awburst_2  ),
    .O_M_AWLOCK    ( dn_s_awlock_2   ),
    .O_M_AWCACHE   ( dn_s_awcache_2  ),
    .O_M_AWPROT    ( dn_s_awprot_2   ),
    .O_M_AWQOS     ( dn_s_awqos_2    ),
    .O_M_AWUSER    ( dn_s_awuser_2   ),
    .O_M_AWVALID   ( dn_s_awvalid_2  ),
    .I_M_AWREADY   ( dn_s_awready_2  ),

    .O_M_WDATA     ( dn_s_wdata_2    ),
    .O_M_WSTRB     ( dn_s_wstrb_2    ),
    .O_M_WLAST     ( dn_s_wlast_2    ),
    .O_M_WUSER     ( dn_s_wuser_2    ),
    .O_M_WVALID    ( dn_s_wvalid_2   ),
    .I_M_WREADY    ( dn_s_wready_2   ),

    .I_M_BID       ( dn_s_bid_2      ),
    .I_M_BRESP     ( dn_s_bresp_2    ),
    .I_M_BUSER     ( dn_s_buser_2    ),
    .I_M_BVALID    ( dn_s_bvalid_2   ),
    .O_M_BREADY    ( dn_s_bready_2   ),

    .O_DOWN_MISMATCH_RID    (O_DOWN1024_MISMATCH_RID),
    .O_DEST_TABLE_RID_ERR   (O_DOWN1024_RID_MISMATCH_ERROR)
    
);


wire [AXI_AWCH_PAYLOAD_WD - 1 : 0] w_awch_fwd_rs_sdata;
wire [AXI_AWCH_PAYLOAD_WD - 1 : 0] w_awch_fwd_rs_mdata;
wire                               w_awch_fwd_rs_sready;

wire [ ID_WD+1: 0]           O_M_AWID_tmp;
wire [ ADDR_WD-1: 0]         O_M_AWADDR_tmp;
wire [ LEN_WD-1: 0]          O_M_AWLEN_tmp;
wire [ 2: 0]                 O_M_AWSIZE_tmp;
wire [ 1: 0]                 O_M_AWBURST_tmp;
wire                         O_M_AWLOCK_tmp;
wire [ 3: 0]                 O_M_AWCACHE_tmp;
wire [ 2: 0]                 O_M_AWPROT_tmp;
wire [ 3: 0]                 O_M_AWQOS_tmp;
wire [15: 0]                 O_M_AWUSER_tmp;
wire                         O_M_AWVALID_tmp;


wire                         I_SS_WVALID_0  ;
wire                         O_SS_WREADY_0  ;

wire [ DATA_WD-1: 0]         I_SS_WDATA_0   ;
wire [ STRB_WD-1: 0]         I_SS_WSTRB_0   ;
wire                         I_SS_WLAST_0   ;
wire [15: 0]                 I_SS_WUSER_0   ;

wire [W_WD - 1:0]     w_s_w_payload_0;
wire [W_WD - 1:0]     w_m_w_payload_0;


wire                         I_SS_WVALID_1  ;
wire                         O_SS_WREADY_1  ;

wire [ DATA_WD-1: 0]         I_SS_WDATA_1   ;
wire [ STRB_WD-1: 0]         I_SS_WSTRB_1   ;
wire                         I_SS_WLAST_1   ;
wire [15: 0]                 I_SS_WUSER_1   ;

wire [W_WD - 1:0]     w_s_w_payload_1;
wire [W_WD - 1:0]     w_m_w_payload_1;


wire                         I_SS_WVALID_2  ;
wire                         O_SS_WREADY_2  ;

wire [ DATA_WD-1: 0]         I_SS_WDATA_2   ;
wire [ STRB_WD-1: 0]         I_SS_WSTRB_2   ;
wire                         I_SS_WLAST_2   ;
wire [15: 0]                 I_SS_WUSER_2   ;

wire [W_WD - 1:0]     w_s_w_payload_2;
wire [W_WD - 1:0]     w_m_w_payload_2;


wire [ 3: 0]     ar_grant, aw_grant;

AOU_4X1_ARBITER ar_arbiter(
    .I_CLK              (I_CLK                          ),
    .I_RESETN           (I_RESETN                       ),
    
    .I_REQ              ({1'b0, dn_s_arvalid_2, I_S_ARVALID_1, up_s_arvalid_0} ),
    .I_ARB_EN           (O_M_ARVALID & I_M_ARREADY      ),
    
    .O_GRANTED_AGENT    (ar_grant                       )
);

AOU_4X1_ARBITER aw_arbiter(
    .I_CLK              (I_CLK                          ),
    .I_RESETN           (I_RESETN                       ),
    
    .I_REQ              ({1'b0, dn_s_awvalid_2, I_S_AWVALID_1, up_s_awvalid_0} ),
    .I_ARB_EN           (O_M_AWVALID_tmp & w_awch_fwd_rs_sready      ),
    
    .O_GRANTED_AGENT    (aw_grant                       )
);

//==============================================================
//                          ADDR_WD
//============================================================== 
assign  O_M_ARID    = (ar_grant[0])? {up_s_arid_0, 2'b00}: (ar_grant[1])? {I_S_ARID_1, 2'b01}:(ar_grant[2])? {dn_s_arid_2, 2'b10} : 'd0;
assign  O_M_ARVALID = (ar_grant[0])? up_s_arvalid_0      : (ar_grant[1])? I_S_ARVALID_1      :(ar_grant[2])? dn_s_arvalid_2       : 'd0;
assign  O_M_ARADDR  = (ar_grant[0])? up_s_araddr_0       : (ar_grant[1])? I_S_ARADDR_1       :(ar_grant[2])? dn_s_araddr_2        : 'd0;
assign  O_M_ARSIZE  = (ar_grant[0])? up_s_arsize_0       : (ar_grant[1])? I_S_ARSIZE_1       :(ar_grant[2])? dn_s_arsize_2        : 'd0;
assign  O_M_ARBURST = (ar_grant[0])? up_s_arburst_0      : (ar_grant[1])? I_S_ARBURST_1      :(ar_grant[2])? dn_s_arburst_2       : 'd0;
assign  O_M_ARCACHE = (ar_grant[0])? up_s_arcache_0      : (ar_grant[1])? I_S_ARCACHE_1      :(ar_grant[2])? dn_s_arcache_2       : 'd0;
assign  O_M_ARPROT  = (ar_grant[0])? up_s_arprot_0       : (ar_grant[1])? I_S_ARPROT_1       :(ar_grant[2])? dn_s_arprot_2        : 'd0;
assign  O_M_ARLEN   = (ar_grant[0])? up_s_arlen_0        : (ar_grant[1])? I_S_ARLEN_1        :(ar_grant[2])? dn_s_arlen_2         : 'd0;
assign  O_M_ARLOCK  = (ar_grant[0])? up_s_arlock_0       : (ar_grant[1])? I_S_ARLOCK_1       :(ar_grant[2])? dn_s_arlock_2        : 'd0;
assign  O_M_ARQOS   = (ar_grant[0])? up_s_arqos_0        : (ar_grant[1])? I_S_ARQOS_1        :(ar_grant[2])? dn_s_arqos_2         : 'd0;
assign  O_M_ARUSER  = (ar_grant[0])? up_s_aruser_0        : (ar_grant[1])? I_S_ARUSER_1        :(ar_grant[2])? dn_s_aruser_2         : 'd0;

assign  up_s_arready_0   = (ar_grant[0])? I_M_ARREADY   : 1'b0;
assign  O_S_ARREADY_1   = (ar_grant[1])? I_M_ARREADY   : 1'b0;
assign  dn_s_arready_2   = (ar_grant[2])? I_M_ARREADY   : 1'b0;

//==============================================================
//                          R(add assign without switching?)
//==============================================================
assign  up_s_rid_0      = I_M_RID[ID_WD+1:2];
assign  O_S_RID_1       = I_M_RID[ID_WD+1:2];
assign  dn_s_rid_2      = I_M_RID[ID_WD+1:2];
assign  up_s_rdata_0    = I_M_RDATA;
assign  O_S_RDATA_1     = I_M_RDATA;
assign  dn_s_rdata_2    = I_M_RDATA;
assign  up_s_rresp_0    = I_M_RRESP;
assign  up_s_ruser_0    = I_M_RUSER;
assign  O_S_RRESP_1     = I_M_RRESP;
assign  O_S_RUSER_1     = I_M_RUSER;
assign  dn_s_rresp_2    = I_M_RRESP;
assign  dn_s_ruser_2    = I_M_RUSER;
assign  up_s_rlast_0    = I_M_RLAST;
assign  O_S_RLAST_1     = I_M_RLAST;
assign  dn_s_rlast_2    = I_M_RLAST;
assign  up_s_addr_cnt_0 = I_M_ADDR_CNT;
assign  up_s_rvalid_0   = (I_M_RID[1:0] == 2'b00) & I_M_RVALID;
assign  O_S_RVALID_1    = (I_M_RID[1:0] == 2'b01) & I_M_RVALID;
assign  dn_s_rvalid_2   = (I_M_RID[1:0] == 2'b10) & I_M_RVALID;

assign  O_M_RREADY  = ~I_M_RVALID | 
                          ((I_M_RID[1:0] == 2'b00)? up_s_rready_0 : 
                           (I_M_RID[1:0] == 2'b01)? I_S_RREADY_1 : 
                                                    dn_s_rready_2) ;

//==============================================================
//                          AW
//==============================================================
wire        w_awfifo_svalid ;
wire [1:0]  w_awfifo_sdata  ;
wire        w_awfifo_sready ;

wire        w_awfifo_mvalid;
wire [1:0]  w_awfifo_mdata ;

wire        w_granted_wch0;
wire        w_granted_wch1;
wire        w_granted_wch2;

assign w_awfifo_svalid = ((aw_grant[0] & up_s_awvalid_0) | (aw_grant[1] & I_S_AWVALID_1) | (aw_grant[2] & dn_s_awvalid_2)) & w_awch_fwd_rs_sready;
assign w_awfifo_sdata  = aw_grant[0] ? 2'b00 : aw_grant[1] ? 2'b01 : aw_grant[2] ? 2'b10 : 2'b11;

assign w_granted_wch0 = w_awfifo_mvalid & (w_awfifo_mdata == 2'b00);
assign w_granted_wch1 = w_awfifo_mvalid & (w_awfifo_mdata == 2'b01);
assign w_granted_wch2 = w_awfifo_mvalid & (w_awfifo_mdata == 2'b10);

wire w_awfifo_mready = (w_granted_wch0 & I_SS_WVALID_0 & I_SS_WLAST_0 & I_M_WREADY) | 
                       (w_granted_wch1 & I_SS_WVALID_1 & I_SS_WLAST_1 & I_M_WREADY) |
                       (w_granted_wch2 & I_SS_WVALID_2 & I_SS_WLAST_2 & I_M_WREADY) ;

wire    w_no_awvalid     ;
assign  w_no_awvalid     = ~(up_s_awvalid_0 | I_S_AWVALID_1 | dn_s_awvalid_2);

assign  up_s_awready_0  = ((aw_grant[0]) ? (w_awch_fwd_rs_sready & w_awfifo_sready) : 1'b0) | w_no_awvalid ;
assign  O_S_AWREADY_1   = ((aw_grant[1]) ? (w_awch_fwd_rs_sready & w_awfifo_sready) : 1'b0) | w_no_awvalid ;
assign  dn_s_awready_2  = ((aw_grant[2]) ? (w_awch_fwd_rs_sready & w_awfifo_sready) : 1'b0) | w_no_awvalid ;

//----------------------------------------------------------------

assign  O_M_AWID_tmp        = (aw_grant[0]) ? {up_s_awid_0, 2'b00}: (aw_grant[1]) ? {I_S_AWID_1, 2'b01}: (aw_grant[2]) ? {dn_s_awid_2, 2'b10} : 'd0;
assign  O_M_AWADDR_tmp      = (aw_grant[0]) ? up_s_awaddr_0       : (aw_grant[1]) ? I_S_AWADDR_1       : (aw_grant[2]) ? dn_s_awaddr_2        : 'd0;
assign  O_M_AWLEN_tmp       = (aw_grant[0]) ? up_s_awlen_0        : (aw_grant[1]) ? I_S_AWLEN_1        : (aw_grant[2]) ? dn_s_awlen_2         : 'd0;
assign  O_M_AWSIZE_tmp      = (aw_grant[0]) ? up_s_awsize_0       : (aw_grant[1]) ? I_S_AWSIZE_1       : (aw_grant[2]) ? dn_s_awsize_2        : 'd0;
assign  O_M_AWBURST_tmp     = (aw_grant[0]) ? up_s_awburst_0      : (aw_grant[1]) ? I_S_AWBURST_1      : (aw_grant[2]) ? dn_s_awburst_2       : 'd0;
assign  O_M_AWLOCK_tmp      = (aw_grant[0]) ? up_s_awlock_0       : (aw_grant[1]) ? I_S_AWLOCK_1       : (aw_grant[2]) ? dn_s_awlock_2        : 'd0;
assign  O_M_AWCACHE_tmp     = (aw_grant[0]) ? up_s_awcache_0      : (aw_grant[1]) ? I_S_AWCACHE_1      : (aw_grant[2]) ? dn_s_awcache_2       : 'd0;
assign  O_M_AWPROT_tmp      = (aw_grant[0]) ? up_s_awprot_0       : (aw_grant[1]) ? I_S_AWPROT_1       : (aw_grant[2]) ? dn_s_awprot_2        : 'd0;
assign  O_M_AWQOS_tmp       = (aw_grant[0]) ? up_s_awqos_0        : (aw_grant[1]) ? I_S_AWQOS_1        : (aw_grant[2]) ? dn_s_awqos_2         : 'd0;
assign  O_M_AWUSER_tmp      = (aw_grant[0]) ? up_s_awuser_0        : (aw_grant[1]) ? I_S_AWUSER_1        : (aw_grant[2]) ? dn_s_awuser_2         : 'd0;
assign  O_M_AWVALID_tmp     = (aw_grant[0]) ? (up_s_awvalid_0 & w_awfifo_sready) : 
                              (aw_grant[1]) ? (I_S_AWVALID_1 & w_awfifo_sready) : 
                                              (dn_s_awvalid_2 & w_awfifo_sready) ;

assign w_awch_fwd_rs_sdata = {
    O_M_AWID_tmp,
    O_M_AWADDR_tmp,
    O_M_AWLEN_tmp,
    O_M_AWSIZE_tmp,
    O_M_AWBURST_tmp,
    O_M_AWLOCK_tmp,
    O_M_AWCACHE_tmp,
    O_M_AWPROT_tmp,
    O_M_AWQOS_tmp,
    O_M_AWUSER_tmp };

AOU_FWD_RS #(
    .DATA_WIDTH ( AXI_AWCH_PAYLOAD_WD  )
) u_aou_fwd_rs
(
   // global interconnect inputs
   .I_RESETN( I_RESETN                      ),
   .I_CLK   ( I_CLK                         ),

   // inputs
   .I_SVALID( O_M_AWVALID_tmp           ),
   .O_SREADY( w_awch_fwd_rs_sready          ),
   .I_SDATA ( w_awch_fwd_rs_sdata           ),

   // outputs
   .I_MREADY( I_M_AWREADY               ),
   .O_MVALID( O_M_AWVALID               ),
   .O_MDATA ( w_awch_fwd_rs_mdata           )
);

assign {O_M_AWID,
        O_M_AWADDR,
        O_M_AWLEN,
        O_M_AWSIZE,
        O_M_AWBURST,
        O_M_AWLOCK,
        O_M_AWCACHE,
        O_M_AWPROT,
        O_M_AWQOS,
        O_M_AWUSER } = w_awch_fwd_rs_mdata;

AOU_SYNC_FIFO_REG  #
(
    .FIFO_WIDTH (2),
    .FIFO_DEPTH (4)
) sync_fifo
(
    .I_CLK           ( I_CLK           ),
    .I_RESETN        ( I_RESETN        ),

    .I_SVALID        ( w_awfifo_svalid ),
    .I_SDATA         ( w_awfifo_sdata  ),
    .O_SREADY        ( w_awfifo_sready ),

    .I_MREADY        ( w_awfifo_mready ),
    .O_MDATA         ( w_awfifo_mdata  ), // DATA + VALID signals are same INPUT or OUTPUT
    .O_MVALID        ( w_awfifo_mvalid ),

    .O_EMPTY_CNT     (                 ),
    .O_FULL_CNT      (                 )
);

//==============================================================
//                          W
//==============================================================

assign w_s_w_payload_0 = {up_s_wdata_0, up_s_wstrb_0, up_s_wlast_0, up_s_wuser_0};
assign {I_SS_WDATA_0, I_SS_WSTRB_0, I_SS_WLAST_0, I_SS_WUSER_0} = w_m_w_payload_0;


// W channel
AOU_SYNC_FIFO_REG 
#(
        .FIFO_WIDTH  ( W_WD            ),
        .FIFO_DEPTH  ( 2               )
)
u_wch_aximux_4x1_sync_fifo_0
(
        .I_CLK       ( I_CLK           ),
        .I_RESETN    ( I_RESETN        ),

        .I_SVALID    ( up_s_wvalid_0    ),
        .I_SDATA     ( w_s_w_payload_0 ),
        .O_SREADY    ( up_s_wready_0    ),

        .I_MREADY    ( O_SS_WREADY_0   ),
        .O_MDATA     ( w_m_w_payload_0 ),
        .O_MVALID    ( I_SS_WVALID_0   ),

        .O_EMPTY_CNT (                 ),
        .O_FULL_CNT  (                 )
);

//==============================================================

assign w_s_w_payload_1 = {I_S_WDATA_1, I_S_WSTRB_1, I_S_WLAST_1, I_S_WUSER_1};
assign {I_SS_WDATA_1, I_SS_WSTRB_1, I_SS_WLAST_1, I_SS_WUSER_1} = w_m_w_payload_1;


// W channel
AOU_SYNC_FIFO_REG 
#(
        .FIFO_WIDTH  ( W_WD            ),
        .FIFO_DEPTH  ( 2               )
)
u_wch_aximux_4x1_sync_fifo_1
(
        .I_CLK       ( I_CLK           ),
        .I_RESETN    ( I_RESETN        ),

        .I_SVALID    ( I_S_WVALID_1    ),
        .I_SDATA     ( w_s_w_payload_1 ),
        .O_SREADY    ( O_S_WREADY_1    ),

        .I_MREADY    ( O_SS_WREADY_1   ),
        .O_MDATA     ( w_m_w_payload_1 ),
        .O_MVALID    ( I_SS_WVALID_1   ),

        .O_EMPTY_CNT (                 ),
        .O_FULL_CNT  (                 )
);

//==============================================================

assign w_s_w_payload_2 = {dn_s_wdata_2, dn_s_wstrb_2, dn_s_wlast_2, dn_s_wuser_2};
assign {I_SS_WDATA_2, I_SS_WSTRB_2, I_SS_WLAST_2, I_SS_WUSER_2} = w_m_w_payload_2;


// W channel
AOU_SYNC_FIFO_REG 
#(
        .FIFO_WIDTH  ( W_WD            ),
        .FIFO_DEPTH  ( 2               )
)
u_wch_aximux_4x1_sync_fifo_2
(
        .I_CLK       ( I_CLK           ),
        .I_RESETN    ( I_RESETN        ),

        .I_SVALID    ( dn_s_wvalid_2    ),
        .I_SDATA     ( w_s_w_payload_2 ),
        .O_SREADY    ( dn_s_wready_2    ),

        .I_MREADY    ( O_SS_WREADY_2   ),
        .O_MDATA     ( w_m_w_payload_2 ),
        .O_MVALID    ( I_SS_WVALID_2   ),

        .O_EMPTY_CNT (                 ),
        .O_FULL_CNT  (                 )
);

//==============================================================

wire    w_no_wvalid     ;
assign  w_no_wvalid     = ~(I_SS_WVALID_0 | I_SS_WVALID_1 | I_SS_WVALID_2);

assign  O_SS_WREADY_0    = ((w_granted_wch0)? I_M_WREADY   : 1'b0) | w_no_wvalid;
assign  O_SS_WREADY_1    = ((w_granted_wch1)? I_M_WREADY   : 1'b0) | w_no_wvalid;
assign  O_SS_WREADY_2    = ((w_granted_wch2)? I_M_WREADY   : 1'b0) | w_no_wvalid;
assign  O_M_WDATA       = (w_granted_wch0)? I_SS_WDATA_0  : (w_granted_wch1)? I_SS_WDATA_1  : (w_granted_wch2)? I_SS_WDATA_2  : 'd0;
assign  O_M_WSTRB       = (w_granted_wch0)? I_SS_WSTRB_0  : (w_granted_wch1)? I_SS_WSTRB_1  : (w_granted_wch2)? I_SS_WSTRB_2  : 'd0;
assign  O_M_WLAST       = (w_granted_wch0)? I_SS_WLAST_0  : (w_granted_wch1)? I_SS_WLAST_1  : (w_granted_wch2)? I_SS_WLAST_2  : 'd0;
assign  O_M_WUSER       = (w_granted_wch0)? I_SS_WUSER_0  : (w_granted_wch1)? I_SS_WUSER_1  : (w_granted_wch2)? I_SS_WUSER_2  : 'd0;
assign  O_M_WVALID      = ((w_granted_wch0)? (I_SS_WVALID_0) : 
                           (w_granted_wch1)? (I_SS_WVALID_1) : 
                           (w_granted_wch2)? (I_SS_WVALID_2) : 'b0) & w_awfifo_mvalid;

//==============================================================
//                          B
//==============================================================
assign  up_s_bid_0      = I_M_BID[ID_WD+1:2];
assign  O_S_BID_1       = I_M_BID[ID_WD+1:2];
assign  dn_s_bid_2      = I_M_BID[ID_WD+1:2];
assign  up_s_bresp_0    = I_M_BRESP;
assign  up_s_buser_0    = I_M_BUSER;
assign  O_S_BRESP_1     = I_M_BRESP;
assign  O_S_BUSER_1     = I_M_BUSER;
assign  dn_s_bresp_2    = I_M_BRESP;
assign  dn_s_buser_2    = I_M_BUSER;
assign  up_s_bvalid_0   = (I_M_BID[1:0] == 2'b00) & I_M_BVALID;
assign  O_S_BVALID_1    = (I_M_BID[1:0] == 2'b01) & I_M_BVALID;
assign  dn_s_bvalid_2   = (I_M_BID[1:0] == 2'b10) & I_M_BVALID;

assign  O_M_BREADY      = ~I_M_BVALID | 
                          ((I_M_BID[1:0] == 2'b00)? up_s_bready_0 : 
                           (I_M_BID[1:0] == 2'b01)? I_S_BREADY_1  : 
                                                    dn_s_bready_2) ; 

endmodule

// *****************************************************************************
// SPDX-License-Identifier: Apache-2.0
// *****************************************************************************
//  Copyright (c) 2026 BOS Semiconductors
//  Copyright (c) 2026 Tenstorrent USA Inc
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
//  Module     : AOU_CORE_SFR
//  Version    : 1.00
//  Date       : 26-02-26
//  Author     : Soyoung Min, Jaeyun Lee, Hojun Lee, Kwanho Kim
//
// *****************************************************************************

`timescale 1ns/1ps

module AOU_CORE_SFR #(
    parameter APB_ADDR_WD   = 32
)
(

    //APB slave
    input                               I_PCLK,
    input                               I_PRESETN,

    input                               I_PSEL,
    input                               I_PENABLE,
    input        [APB_ADDR_WD-1:0]      I_PADDR,
    input                               I_PWRITE,
    input        [31:0]                 I_PWDATA,

    output wire  [31:0]                 O_PRDATA,
    output wire                         O_PREADY,
    output wire                         O_PSLVERR,

    //SFR I/F
    input       [15:0]      I_IP_VERSION_MAJOR_VERSION,
    input       [15:0]      I_IP_VERSION_MINOR_VERSION,
    output                  O_AOU_CON0_RP3_ERROR_INFO_ACCESS_EN,
    output                  O_AOU_CON0_RP2_ERROR_INFO_ACCESS_EN,
    output                  O_AOU_CON0_RP1_ERROR_INFO_ACCESS_EN,
    output                  O_AOU_CON0_RP0_ERROR_INFO_ACCESS_EN,
    output                  O_AOU_CON0_RP3_AXI_AGGREGATOR_EN,
    output                  O_AOU_CON0_RP2_AXI_AGGREGATOR_EN,
    output                  O_AOU_CON0_RP1_AXI_AGGREGATOR_EN,
    output                  O_AOU_CON0_RP0_AXI_AGGREGATOR_EN,
    output      [7:0]       O_AOU_CON0_TX_LP_MODE_THRESHOLD,
    output                  O_AOU_CON0_TX_LP_MODE,
    output                  O_AOU_CON0_AOU_SW_RESET,
    output                  O_AOU_CON0_CREDIT_MANAGE,
    output                  O_AOU_CON0_DEACTIVATE_FORCE,
    input                   I_AOU_INIT_INT_DEACTIVATE_PROPERTY,    
    input                   I_AOU_INIT_MST_TR_COMPLETE,
    input                   I_AOU_INIT_SLV_TR_COMPLETE,
    input                   I_AOU_INIT_INT_ACTIVATE_START_SET,
    input                   I_AOU_INIT_INT_DEACTIVATE_START_SET,
    output      [2:0]       O_AOU_INIT_DEACTIVATE_TIME_OUT_VALUE,
    input                   I_AOU_INIT_ACTIVATE_STATE_DISABLED,
    input                   I_AOU_INIT_ACTIVATE_STATE_ENABLED,
    output                  O_AOU_INIT_DEACTIVATE_START,
    output                  O_AOU_INIT_ACTIVATE_START,
    output                  O_AOU_INTERRUPT_MASK_INT_REQ_LINKRESET_ACT_ACK_MASK,
    output                  O_AOU_INTERRUPT_MASK_INT_REQ_LINKRESET_DEACT_ACK_MASK,
    output                  O_AOU_INTERRUPT_MASK_INT_REQ_LINKRESET_INVALID_ACTMSG_MASK,
    output                  O_AOU_INTERRUPT_MASK_INT_REQ_LINKRESET_MSGCREDIT_TIMEOUT_MASK,
    output                  O_AOU_INTERRUPT_MASK_INT_EARLY_RESP_MASK,
    output                  O_AOU_INTERRUPT_MASK_INT_MI0_ID_MISMATCH_MASK,
    output                  O_AOU_INTERRUPT_MASK_INT_SI0_ID_MISMATCH_MASK,
    output      [2:0]       O_LP_LINKRESET_ACK_TIME_OUT_VALUE,
    output      [2:0]       O_LP_LINKRESET_MSGCREDIT_TIME_OUT_VALUE,
    input                   I_LP_LINKRESET_ACT_ACK_ERR_SET,
    input                   I_LP_LINKRESET_DEACT_ACK_ERR_SET,
    input       [3:0]       I_LP_LINKRESET_INVALID_ACTMSG_INFO,
    input                   I_LP_LINKRESET_INVALID_ACTMSG_ERR_SET,
    input                   I_LP_LINKRESET_MSGCREDIT_ERR_SET,
    output      [1:0]       O_DEST_RP_RP3_DEST,
    output      [1:0]       O_DEST_RP_RP2_DEST,
    output      [1:0]       O_DEST_RP_RP1_DEST,
    output      [1:0]       O_DEST_RP_RP0_DEST,
    output      [3:0]       O_PRIOR_RP_AXI_AXI_QOS_TO_NP,
    output      [3:0]       O_PRIOR_RP_AXI_AXI_QOS_TO_HP,
    output      [1:0]       O_PRIOR_RP_AXI_RP3_PRIOR,
    output      [1:0]       O_PRIOR_RP_AXI_RP2_PRIOR,
    output      [1:0]       O_PRIOR_RP_AXI_RP1_PRIOR,
    output      [1:0]       O_PRIOR_RP_AXI_RP0_PRIOR,
    output      [1:0]       O_PRIOR_RP_AXI_ARB_MODE,
    output      [15:0]      O_PRIOR_TIMER_TIMER_RESOLUTION,
    output      [15:0]      O_PRIOR_TIMER_TIMER_THRESHOLD,
    output      [7:0]       O_AXI_SPLIT_TR_RP0_MAX_AWBURSTLEN,
    output      [7:0]       O_AXI_SPLIT_TR_RP0_MAX_ARBURSTLEN,
    input       [9:0]       I_ERROR_INFO_RP0_SPLIT_BID_MISMATCH_INFO,
    input       [9:0]       I_ERROR_INFO_RP0_RID_MISMATCH_INFO,
    input                   I_ERROR_INFO_RP0_SPLIT_BID_MISMATCH_ERR_SET,
    input                   I_ERROR_INFO_RP0_RID_MISMATCH_ERR_SET,
    input                   I_WRITE_EARLY_RESPONSE_RP0_WRITE_RESP_DONE,
    input                   I_WRITE_EARLY_RESPONSE_RP0_WRITE_RESP_ERR_SET,
    input       [1:0]       I_WRITE_EARLY_RESPONSE_RP0_WRITE_RESP_ERR_TYPE_INFO,
    input       [9:0]       I_WRITE_EARLY_RESPONSE_RP0_WRITE_RESP_ERR_ID_INFO,
    output                  O_WRITE_EARLY_RESPONSE_RP0_EARLY_BRESP_EN,
    output      [31:0]      O_AXI_ERROR_INFO0_RP0_DEBUG_UPPER_ADDR,
    output      [31:0]      O_AXI_ERROR_INFO1_RP0_DEBUG_LOWER_ADDR,
    input       [9:0]       I_AXI_SLV_ID_MISMATCH_ERR_RP0_AXI_SLV_BID_MISMATCH_INFO,
    input       [9:0]       I_AXI_SLV_ID_MISMATCH_ERR_RP0_AXI_SLV_RID_MISMATCH_INFO,
    input                   I_AXI_SLV_ID_MISMATCH_ERR_RP0_AXI_SLV_BID_MISMATCH_ERR_SET,
    input                   I_AXI_SLV_ID_MISMATCH_ERR_RP0_AXI_SLV_RID_MISMATCH_ERR_SET,
    output      [7:0]       O_AXI_SPLIT_TR_RP1_MAX_AWBURSTLEN,
    output      [7:0]       O_AXI_SPLIT_TR_RP1_MAX_ARBURSTLEN,
    input       [9:0]       I_ERROR_INFO_RP1_SPLIT_BID_MISMATCH_INFO,
    input       [9:0]       I_ERROR_INFO_RP1_RID_MISMATCH_INFO,
    input                   I_ERROR_INFO_RP1_SPLIT_BID_MISMATCH_ERR_SET,
    input                   I_ERROR_INFO_RP1_RID_MISMATCH_ERR_SET,
    input                   I_WRITE_EARLY_RESPONSE_RP1_WRITE_RESP_DONE,
    input                   I_WRITE_EARLY_RESPONSE_RP1_WRITE_RESP_ERR_SET,
    input       [1:0]       I_WRITE_EARLY_RESPONSE_RP1_WRITE_RESP_ERR_TYPE_INFO,
    input       [9:0]       I_WRITE_EARLY_RESPONSE_RP1_WRITE_RESP_ERR_ID_INFO,
    output                  O_WRITE_EARLY_RESPONSE_RP1_EARLY_BRESP_EN,
    output      [31:0]      O_AXI_ERROR_INFO0_RP1_DEBUG_UPPER_ADDR,
    output      [31:0]      O_AXI_ERROR_INFO1_RP1_DEBUG_LOWER_ADDR,
    input       [9:0]       I_AXI_SLV_ID_MISMATCH_ERR_RP1_AXI_SLV_BID_MISMATCH_INFO,
    input       [9:0]       I_AXI_SLV_ID_MISMATCH_ERR_RP1_AXI_SLV_RID_MISMATCH_INFO,
    input                   I_AXI_SLV_ID_MISMATCH_ERR_RP1_AXI_SLV_BID_MISMATCH_ERR_SET,
    input                   I_AXI_SLV_ID_MISMATCH_ERR_RP1_AXI_SLV_RID_MISMATCH_ERR_SET,
    output      [7:0]       O_AXI_SPLIT_TR_RP2_MAX_AWBURSTLEN,
    output      [7:0]       O_AXI_SPLIT_TR_RP2_MAX_ARBURSTLEN,
    input       [9:0]       I_ERROR_INFO_RP2_SPLIT_BID_MISMATCH_INFO,
    input       [9:0]       I_ERROR_INFO_RP2_RID_MISMATCH_INFO,
    input                   I_ERROR_INFO_RP2_SPLIT_BID_MISMATCH_ERR_SET,
    input                   I_ERROR_INFO_RP2_RID_MISMATCH_ERR_SET,
    input                   I_WRITE_EARLY_RESPONSE_RP2_WRITE_RESP_DONE,
    input                   I_WRITE_EARLY_RESPONSE_RP2_WRITE_RESP_ERR_SET,
    input       [1:0]       I_WRITE_EARLY_RESPONSE_RP2_WRITE_RESP_ERR_TYPE_INFO,
    input       [9:0]       I_WRITE_EARLY_RESPONSE_RP2_WRITE_RESP_ERR_ID_INFO,
    output                  O_WRITE_EARLY_RESPONSE_RP2_EARLY_BRESP_EN,
    output      [31:0]      O_AXI_ERROR_INFO0_RP2_DEBUG_UPPER_ADDR,
    output      [31:0]      O_AXI_ERROR_INFO1_RP2_DEBUG_LOWER_ADDR,
    input       [9:0]       I_AXI_SLV_ID_MISMATCH_ERR_RP2_AXI_SLV_BID_MISMATCH_INFO,
    input       [9:0]       I_AXI_SLV_ID_MISMATCH_ERR_RP2_AXI_SLV_RID_MISMATCH_INFO,
    input                   I_AXI_SLV_ID_MISMATCH_ERR_RP2_AXI_SLV_BID_MISMATCH_ERR_SET,
    input                   I_AXI_SLV_ID_MISMATCH_ERR_RP2_AXI_SLV_RID_MISMATCH_ERR_SET,
    output      [7:0]       O_AXI_SPLIT_TR_RP3_MAX_AWBURSTLEN,
    output      [7:0]       O_AXI_SPLIT_TR_RP3_MAX_ARBURSTLEN,
    input       [9:0]       I_ERROR_INFO_RP3_SPLIT_BID_MISMATCH_INFO,
    input       [9:0]       I_ERROR_INFO_RP3_RID_MISMATCH_INFO,
    input                   I_ERROR_INFO_RP3_SPLIT_BID_MISMATCH_ERR_SET,
    input                   I_ERROR_INFO_RP3_RID_MISMATCH_ERR_SET,
    input                   I_WRITE_EARLY_RESPONSE_RP3_WRITE_RESP_DONE,
    input                   I_WRITE_EARLY_RESPONSE_RP3_WRITE_RESP_ERR_SET,
    input       [1:0]       I_WRITE_EARLY_RESPONSE_RP3_WRITE_RESP_ERR_TYPE_INFO,
    input       [9:0]       I_WRITE_EARLY_RESPONSE_RP3_WRITE_RESP_ERR_ID_INFO,
    output                  O_WRITE_EARLY_RESPONSE_RP3_EARLY_BRESP_EN,
    output      [31:0]      O_AXI_ERROR_INFO0_RP3_DEBUG_UPPER_ADDR,
    output      [31:0]      O_AXI_ERROR_INFO1_RP3_DEBUG_LOWER_ADDR,
    input       [9:0]       I_AXI_SLV_ID_MISMATCH_ERR_RP3_AXI_SLV_BID_MISMATCH_INFO,
    input       [9:0]       I_AXI_SLV_ID_MISMATCH_ERR_RP3_AXI_SLV_RID_MISMATCH_INFO,
    input                   I_AXI_SLV_ID_MISMATCH_ERR_RP3_AXI_SLV_BID_MISMATCH_ERR_SET,
    input                   I_AXI_SLV_ID_MISMATCH_ERR_RP3_AXI_SLV_RID_MISMATCH_ERR_SET,
    output                  O_AXI_SLV_ID_MISMATCH_RP0_EN,            
    output                  O_AXI_SLV_ID_MISMATCH_RP1_EN, 
    output                  O_AXI_SLV_ID_MISMATCH_RP2_EN, 
    output                  O_AXI_SLV_ID_MISMATCH_RP3_EN, 
    //Manual input, output

    output                  O_RID_MISMATCH_ERROR,
    output                  O_SPLIT_BID_MISMATCH_ERROR,
    output                  O_ACT_ACK_ERR,
    output                  O_DEACT_ACK_ERR,
    output                  O_INVALID_ACTMSG_ERR,
    output                  O_MSGCREDIT_ERR,
    output                  O_AXI_SLV_RID_MISMATCH_ERROR,
    output                  O_AXI_SLV_BID_MISMATCH_ERROR,
   
    output                  ERR_SLV_EARLY_RESP_ERR,
 
    output                  INT_ACTIVATE_START,
    output                  INT_DEACTIVATE_START

);


localparam SFR_IP_VERSION_ADDR                  = 16'h0000;
localparam SFR_AOU_CON0_ADDR                    = 16'h0004;
localparam SFR_AOU_INIT_ADDR                    = 16'h0008;
localparam SFR_AOU_INTERRUPT_MASK_ADDR          = 16'h000C;
localparam SFR_LP_LINKRESET_ADDR                = 16'h0010;
localparam SFR_DEST_RP_ADDR                     = 16'h0014;
localparam SFR_PRIOR_RP_AXI_ADDR                = 16'h0018;
localparam SFR_PRIOR_TIMER_ADDR                 = 16'h001C;
localparam SFR_AXI_SPLIT_TR_RP0_ADDR            = 16'h0020;
localparam SFR_ERROR_INFO_RP0_ADDR              = 16'h0024;
localparam SFR_WRITE_EARLY_RESPONSE_RP0_ADDR    = 16'h0028;
localparam SFR_AXI_ERROR_INFO0_RP0_ADDR         = 16'h002C;
localparam SFR_AXI_ERROR_INFO1_RP0_ADDR         = 16'h0030;
localparam SFR_AXI_SLV_ID_MISMATCH_ERR_RP0_ADDR = 16'h0034;
localparam SFR_AXI_SPLIT_TR_RP1_ADDR            = 16'h0038;
localparam SFR_ERROR_INFO_RP1_ADDR              = 16'h003C;
localparam SFR_WRITE_EARLY_RESPONSE_RP1_ADDR    = 16'h0040;
localparam SFR_AXI_ERROR_INFO0_RP1_ADDR         = 16'h0044;
localparam SFR_AXI_ERROR_INFO1_RP1_ADDR         = 16'h0048;
localparam SFR_AXI_SLV_ID_MISMATCH_ERR_RP1_ADDR = 16'h004C;
localparam SFR_AXI_SPLIT_TR_RP2_ADDR            = 16'h0050;
localparam SFR_ERROR_INFO_RP2_ADDR              = 16'h0054;
localparam SFR_WRITE_EARLY_RESPONSE_RP2_ADDR    = 16'h0058;
localparam SFR_AXI_ERROR_INFO0_RP2_ADDR         = 16'h005C;
localparam SFR_AXI_ERROR_INFO1_RP2_ADDR         = 16'h0060;
localparam SFR_AXI_SLV_ID_MISMATCH_ERR_RP2_ADDR = 16'h0064;
localparam SFR_AXI_SPLIT_TR_RP3_ADDR            = 16'h0068;
localparam SFR_ERROR_INFO_RP3_ADDR              = 16'h006C;
localparam SFR_WRITE_EARLY_RESPONSE_RP3_ADDR    = 16'h0070;
localparam SFR_AXI_ERROR_INFO0_RP3_ADDR         = 16'h0074;
localparam SFR_AXI_ERROR_INFO1_RP3_ADDR         = 16'h0078;
localparam SFR_AXI_SLV_ID_MISMATCH_ERR_RP3_ADDR = 16'h007C;

//Error set
reg [9:0]           r_error_info_rp0_split_mismatch_bid;
reg [9:0]           r_error_info_rp0_mismatch_rid;

reg [9:0]           r_error_info_rp1_split_mismatch_bid;
reg [9:0]           r_error_info_rp1_mismatch_rid;

reg [9:0]           r_error_info_rp2_split_mismatch_bid;
reg [9:0]           r_error_info_rp2_mismatch_rid;

reg [9:0]           r_error_info_rp3_split_mismatch_bid;
reg [9:0]           r_error_info_rp3_mismatch_rid;

reg [3:0]           r_lp_linkreset_invalid_actmsg_info;

reg [9:0]           r_axi_slv_id_mismatch_err_rp0_bid;
reg [9:0]           r_axi_slv_id_mismatch_err_rp0_rid;

reg [9:0]           r_axi_slv_id_mismatch_err_rp1_bid;
reg [9:0]           r_axi_slv_id_mismatch_err_rp1_rid;

reg [9:0]           r_axi_slv_id_mismatch_err_rp2_bid;
reg [9:0]           r_axi_slv_id_mismatch_err_rp2_rid;

reg [9:0]           r_axi_slv_id_mismatch_err_rp3_bid;
reg [9:0]           r_axi_slv_id_mismatch_err_rp3_rid;

reg                 r_axi_slv_id_mismatch_rp0_en;
reg                 r_axi_slv_id_mismatch_rp1_en;
reg                 r_axi_slv_id_mismatch_rp2_en;
reg                 r_axi_slv_id_mismatch_rp3_en;

reg [9:0]           r_write_early_response_rp0_write_resp_err_id_info;
reg [1:0]           r_write_early_response_rp0_write_resp_err_type_info;

reg [9:0]           r_write_early_response_rp1_write_resp_err_id_info;
reg [1:0]           r_write_early_response_rp1_write_resp_err_type_info;

reg [9:0]           r_write_early_response_rp2_write_resp_err_id_info;
reg [1:0]           r_write_early_response_rp2_write_resp_err_type_info;

reg [9:0]           r_write_early_response_rp3_write_resp_err_id_info;
reg [1:0]           r_write_early_response_rp3_write_resp_err_type_info;

reg                 r_aou_con0_rp3_error_info_access_en;
reg                 r_aou_con0_rp2_error_info_access_en;
reg                 r_aou_con0_rp1_error_info_access_en;
reg                 r_aou_con0_rp0_error_info_access_en;
reg                 r_aou_con0_rp3_axi_aggregator_en;
reg                 r_aou_con0_rp2_axi_aggregator_en;
reg                 r_aou_con0_rp1_axi_aggregator_en;
reg                 r_aou_con0_rp0_axi_aggregator_en;
reg [7:0]           r_aou_con0_tx_lp_mode_threshold;
reg                 r_aou_con0_tx_lp_mode;
reg                 r_aou_con0_aou_sw_reset;
reg                 r_aou_con0_credit_manage;
reg                 r_aou_con0_deactivate_force;
reg                 r_aou_init_int_activate_start;
reg                 r_aou_init_int_deactivate_start;
reg [2:0]           r_aou_init_deactivate_time_out_value;
reg                 r_aou_init_deactivate_start;
reg                 r_aou_init_activate_start;
reg                 r_aou_interrupt_mask_int_req_linkreset_act_ack_mask;
reg                 r_aou_interrupt_mask_int_req_linkreset_deact_ack_mask;
reg                 r_aou_interrupt_mask_int_req_linkreset_invalid_actmsg_mask;
reg                 r_aou_interrupt_mask_int_req_linkreset_msgcredit_timeout_mask;
reg                 r_aou_interrupt_mask_int_early_resp_mask;
reg                 r_aou_interrupt_mask_int_mi0_id_mismatch_mask;
reg                 r_aou_interrupt_mask_int_si0_id_mismatch_mask;
reg [2:0]           r_lp_linkreset_ack_time_out_value;
reg [2:0]           r_lp_linkreset_msgcredit_time_out_value;
reg                 r_lp_linkreset_act_ack_err;
reg                 r_lp_linkreset_deact_ack_err;
reg                 r_lp_linkreset_invalid_actmsg_err;
reg                 r_lp_linkreset_msgcredit_err;
reg [1:0]           r_dest_rp_rp3_dest;
reg [1:0]           r_dest_rp_rp2_dest;
reg [1:0]           r_dest_rp_rp1_dest;
reg [1:0]           r_dest_rp_rp0_dest;
reg [3:0]           r_prior_rp_axi_axi_qos_to_np;
reg [3:0]           r_prior_rp_axi_axi_qos_to_hp;
reg [1:0]           r_prior_rp_axi_rp3_prior;
reg [1:0]           r_prior_rp_axi_rp2_prior;
reg [1:0]           r_prior_rp_axi_rp1_prior;
reg [1:0]           r_prior_rp_axi_rp0_prior;
reg [1:0]           r_prior_rp_axi_arb_mode;
reg [15:0]          r_prior_timer_timer_resolution;
reg [15:0]          r_prior_timer_timer_threshold;
reg [7:0]           r_axi_split_tr_rp0_max_awburstlen;
reg [7:0]           r_axi_split_tr_rp0_max_arburstlen;
reg                 r_error_info_rp0_split_bid_mismatch_err;
reg                 r_error_info_rp0_rid_mismatch_err;
reg                 r_write_early_response_rp0_write_resp_err;
reg                 r_write_early_response_rp0_early_bresp_en;
reg [31:0]          r_axi_error_info0_rp0_debug_upper_addr;
reg [31:0]          r_axi_error_info1_rp0_debug_lower_addr;
reg                 r_axi_slv_id_mismatch_err_rp0_axi_slv_bid_mismatch_err;
reg                 r_axi_slv_id_mismatch_err_rp0_axi_slv_rid_mismatch_err;
reg [7:0]           r_axi_split_tr_rp1_max_awburstlen;
reg [7:0]           r_axi_split_tr_rp1_max_arburstlen;
reg                 r_error_info_rp1_split_bid_mismatch_err;
reg                 r_error_info_rp1_rid_mismatch_err;
reg                 r_write_early_response_rp1_write_resp_err;
reg                 r_write_early_response_rp1_early_bresp_en;
reg [31:0]          r_axi_error_info0_rp1_debug_upper_addr;
reg [31:0]          r_axi_error_info1_rp1_debug_lower_addr;
reg                 r_axi_slv_id_mismatch_err_rp1_axi_slv_bid_mismatch_err;
reg                 r_axi_slv_id_mismatch_err_rp1_axi_slv_rid_mismatch_err;
reg [7:0]           r_axi_split_tr_rp2_max_awburstlen;
reg [7:0]           r_axi_split_tr_rp2_max_arburstlen;
reg                 r_error_info_rp2_split_bid_mismatch_err;
reg                 r_error_info_rp2_rid_mismatch_err;
reg                 r_write_early_response_rp2_write_resp_err;
reg                 r_write_early_response_rp2_early_bresp_en;
reg [31:0]          r_axi_error_info0_rp2_debug_upper_addr;
reg [31:0]          r_axi_error_info1_rp2_debug_lower_addr;
reg                 r_axi_slv_id_mismatch_err_rp2_axi_slv_bid_mismatch_err;
reg                 r_axi_slv_id_mismatch_err_rp2_axi_slv_rid_mismatch_err;
reg [7:0]           r_axi_split_tr_rp3_max_awburstlen;
reg [7:0]           r_axi_split_tr_rp3_max_arburstlen;
reg                 r_error_info_rp3_split_bid_mismatch_err;
reg                 r_error_info_rp3_rid_mismatch_err;
reg                 r_write_early_response_rp3_write_resp_err;
reg                 r_write_early_response_rp3_early_bresp_en;
reg [31:0]          r_axi_error_info0_rp3_debug_upper_addr;
reg [31:0]          r_axi_error_info1_rp3_debug_lower_addr;
reg                 r_axi_slv_id_mismatch_err_rp3_axi_slv_bid_mismatch_err;
reg                 r_axi_slv_id_mismatch_err_rp3_axi_slv_rid_mismatch_err;

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_aou_con0_rp3_error_info_access_en <= 1'h0;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_AOU_CON0_ADDR)) begin
        r_aou_con0_rp3_error_info_access_en <= I_PWDATA[27];
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_aou_con0_rp2_error_info_access_en <= 1'h0;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_AOU_CON0_ADDR)) begin
        r_aou_con0_rp2_error_info_access_en <= I_PWDATA[26];
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_aou_con0_rp1_error_info_access_en <= 1'h0;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_AOU_CON0_ADDR)) begin
        r_aou_con0_rp1_error_info_access_en <= I_PWDATA[25];
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_aou_con0_rp0_error_info_access_en <= 1'h0;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_AOU_CON0_ADDR)) begin
        r_aou_con0_rp0_error_info_access_en <= I_PWDATA[24];
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_aou_con0_rp3_axi_aggregator_en <= 1'h0;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_AOU_CON0_ADDR)) begin
        r_aou_con0_rp3_axi_aggregator_en <= I_PWDATA[23];
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_aou_con0_rp2_axi_aggregator_en <= 1'h0;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_AOU_CON0_ADDR)) begin
        r_aou_con0_rp2_axi_aggregator_en <= I_PWDATA[22];
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_aou_con0_rp1_axi_aggregator_en <= 1'h0;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_AOU_CON0_ADDR)) begin
        r_aou_con0_rp1_axi_aggregator_en <= I_PWDATA[21];
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_aou_con0_rp0_axi_aggregator_en <= 1'h0;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_AOU_CON0_ADDR)) begin
        r_aou_con0_rp0_axi_aggregator_en <= I_PWDATA[20];
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_aou_con0_tx_lp_mode_threshold <= 8'h4;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_AOU_CON0_ADDR)) begin
        r_aou_con0_tx_lp_mode_threshold <= I_PWDATA[19:12];
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_aou_con0_tx_lp_mode <= 1'h0;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_AOU_CON0_ADDR)) begin
        r_aou_con0_tx_lp_mode <= I_PWDATA[11];
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_aou_con0_aou_sw_reset <= 1'h0;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_AOU_CON0_ADDR)) begin
        r_aou_con0_aou_sw_reset <= I_PWDATA[4];
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_aou_con0_credit_manage <= 1'h1;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_AOU_CON0_ADDR)) begin
        r_aou_con0_credit_manage <= I_PWDATA[3];
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
       r_aou_con0_deactivate_force <= 1'h0;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_AOU_CON0_ADDR)) begin
        r_aou_con0_deactivate_force <= I_PWDATA[0];
    end else if (r_aou_con0_deactivate_force & I_AOU_INIT_ACTIVATE_STATE_DISABLED) begin
        r_aou_con0_deactivate_force <= 1'h0;
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_aou_init_int_activate_start <= 1'h0;
    end else if (I_AOU_INIT_INT_ACTIVATE_START_SET) begin
        r_aou_init_int_activate_start <= 1'b1;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_AOU_INIT_ADDR) & I_PWDATA[8]) begin
        r_aou_init_int_activate_start <= 1'b0;
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_aou_init_int_deactivate_start <= 1'h0;
    end else if (I_AOU_INIT_INT_DEACTIVATE_START_SET) begin
        r_aou_init_int_deactivate_start <= 1'b1;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_AOU_INIT_ADDR) & I_PWDATA[7]) begin
        r_aou_init_int_deactivate_start <= 1'b0;
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_aou_init_deactivate_time_out_value <= 3'h0;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_AOU_INIT_ADDR)) begin
        r_aou_init_deactivate_time_out_value <= I_PWDATA[6:4];
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_aou_init_deactivate_start <= 1'h0;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_AOU_INIT_ADDR)) begin
        r_aou_init_deactivate_start <= I_PWDATA[1];
    end else if (r_aou_init_deactivate_start & I_AOU_INIT_ACTIVATE_STATE_DISABLED) begin
        r_aou_init_deactivate_start <= 1'h0;
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_aou_init_activate_start <= 1'h0;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_AOU_INIT_ADDR)) begin
        r_aou_init_activate_start <= I_PWDATA[0];
    end else if (r_aou_init_activate_start && I_AOU_INIT_ACTIVATE_STATE_ENABLED) begin
        r_aou_init_activate_start <= 1'b0;
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_aou_interrupt_mask_int_req_linkreset_act_ack_mask <= 1'h0;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_AOU_INTERRUPT_MASK_ADDR)) begin
        r_aou_interrupt_mask_int_req_linkreset_act_ack_mask <= I_PWDATA[8];
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_aou_interrupt_mask_int_req_linkreset_deact_ack_mask <= 1'h0;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_AOU_INTERRUPT_MASK_ADDR)) begin
        r_aou_interrupt_mask_int_req_linkreset_deact_ack_mask <= I_PWDATA[7];
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_aou_interrupt_mask_int_req_linkreset_invalid_actmsg_mask <= 1'h0;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_AOU_INTERRUPT_MASK_ADDR)) begin
        r_aou_interrupt_mask_int_req_linkreset_invalid_actmsg_mask <= I_PWDATA[6];
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_aou_interrupt_mask_int_req_linkreset_msgcredit_timeout_mask <= 1'h0;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_AOU_INTERRUPT_MASK_ADDR)) begin
        r_aou_interrupt_mask_int_req_linkreset_msgcredit_timeout_mask <= I_PWDATA[5];
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_aou_interrupt_mask_int_early_resp_mask <= 1'h0;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_AOU_INTERRUPT_MASK_ADDR)) begin
        r_aou_interrupt_mask_int_early_resp_mask <= I_PWDATA[4];
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_aou_interrupt_mask_int_mi0_id_mismatch_mask <= 1'h0;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_AOU_INTERRUPT_MASK_ADDR)) begin
        r_aou_interrupt_mask_int_mi0_id_mismatch_mask <= I_PWDATA[3];
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_aou_interrupt_mask_int_si0_id_mismatch_mask <= 1'h0;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_AOU_INTERRUPT_MASK_ADDR)) begin
        r_aou_interrupt_mask_int_si0_id_mismatch_mask <= I_PWDATA[2];
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_lp_linkreset_ack_time_out_value <= 3'h4;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_LP_LINKRESET_ADDR)) begin
        r_lp_linkreset_ack_time_out_value <= I_PWDATA[13:11];
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_lp_linkreset_msgcredit_time_out_value <= 3'h4;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_LP_LINKRESET_ADDR)) begin
        r_lp_linkreset_msgcredit_time_out_value <= I_PWDATA[10:8];
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_lp_linkreset_act_ack_err <= 1'h0;
    end else if (I_LP_LINKRESET_ACT_ACK_ERR_SET) begin
        r_lp_linkreset_act_ack_err <= 1'b1;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_LP_LINKRESET_ADDR) & I_PWDATA[7]) begin
        r_lp_linkreset_act_ack_err <= 1'b0;
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_lp_linkreset_deact_ack_err <= 1'h0;
    end else if (I_LP_LINKRESET_DEACT_ACK_ERR_SET) begin
        r_lp_linkreset_deact_ack_err <= 1'b1;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_LP_LINKRESET_ADDR) & I_PWDATA[6]) begin
        r_lp_linkreset_deact_ack_err <= 1'b0;
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_lp_linkreset_invalid_actmsg_err <= 1'h0;
    end else if (I_LP_LINKRESET_INVALID_ACTMSG_ERR_SET) begin
        r_lp_linkreset_invalid_actmsg_err <= 1'b1;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_LP_LINKRESET_ADDR) & I_PWDATA[1]) begin
        r_lp_linkreset_invalid_actmsg_err <= 1'b0;
    end
end

always @ (posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_lp_linkreset_invalid_actmsg_info <= 4'b0;
    end else if ((~r_lp_linkreset_invalid_actmsg_err) && I_LP_LINKRESET_INVALID_ACTMSG_ERR_SET) begin
        r_lp_linkreset_invalid_actmsg_info <= I_LP_LINKRESET_INVALID_ACTMSG_INFO;
    end else if (~r_lp_linkreset_invalid_actmsg_err) begin
        r_lp_linkreset_invalid_actmsg_info <= 4'b0;
    end    
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_lp_linkreset_msgcredit_err <= 1'h0;
    end else if (I_LP_LINKRESET_MSGCREDIT_ERR_SET) begin
        r_lp_linkreset_msgcredit_err <= 1'b1;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_LP_LINKRESET_ADDR) & I_PWDATA[0]) begin
        r_lp_linkreset_msgcredit_err <= 1'b0;
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_dest_rp_rp3_dest <= 2'h3;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_DEST_RP_ADDR)) begin
        r_dest_rp_rp3_dest <= I_PWDATA[13:12];
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_dest_rp_rp2_dest <= 2'h2;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_DEST_RP_ADDR)) begin
        r_dest_rp_rp2_dest <= I_PWDATA[9:8];
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_dest_rp_rp1_dest <= 2'h1;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_DEST_RP_ADDR)) begin
        r_dest_rp_rp1_dest <= I_PWDATA[5:4];
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_dest_rp_rp0_dest <= 2'h0;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_DEST_RP_ADDR)) begin
        r_dest_rp_rp0_dest <= I_PWDATA[1:0];
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_prior_rp_axi_axi_qos_to_np <= 4'hA;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_PRIOR_RP_AXI_ADDR)) begin
        r_prior_rp_axi_axi_qos_to_np <= I_PWDATA[27:24];
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_prior_rp_axi_axi_qos_to_hp <= 4'h5;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_PRIOR_RP_AXI_ADDR)) begin
        r_prior_rp_axi_axi_qos_to_hp <= I_PWDATA[23:20];
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_prior_rp_axi_rp3_prior <= 2'h3;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_PRIOR_RP_AXI_ADDR)) begin
        r_prior_rp_axi_rp3_prior <= I_PWDATA[17:16];
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_prior_rp_axi_rp2_prior <= 2'h2;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_PRIOR_RP_AXI_ADDR)) begin
        r_prior_rp_axi_rp2_prior <= I_PWDATA[13:12];
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_prior_rp_axi_rp1_prior <= 2'h1;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_PRIOR_RP_AXI_ADDR)) begin
        r_prior_rp_axi_rp1_prior <= I_PWDATA[9:8];
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_prior_rp_axi_rp0_prior <= 2'h0;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_PRIOR_RP_AXI_ADDR)) begin
        r_prior_rp_axi_rp0_prior <= I_PWDATA[5:4];
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_prior_rp_axi_arb_mode <= 2'h0;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_PRIOR_RP_AXI_ADDR)) begin
        r_prior_rp_axi_arb_mode <= I_PWDATA[1:0];
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_prior_timer_timer_resolution <= 16'hF;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_PRIOR_TIMER_ADDR)) begin
        r_prior_timer_timer_resolution <= I_PWDATA[31:16];
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_prior_timer_timer_threshold <= 16'hF;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_PRIOR_TIMER_ADDR)) begin
        r_prior_timer_timer_threshold <= I_PWDATA[15:0];
    end
end

// MAX_AxBURSTLEN must be 2^n - 1 (0, 1, 3, 7, 15, 31, 63, 127, 255) because
// the transaction splitter derives its sub-burst count with a shift. Any other
// written value is replaced by 0xF (16 beats, the reset value) so an illegal
// configuration cannot reach the splitter.
function automatic [7:0] f_max_axburstlen;
    input [7:0] i_val;
    begin
        case (i_val)
            8'd0, 8'd1, 8'd3, 8'd7, 8'd15,
            8'd31, 8'd63, 8'd127, 8'd255:
                f_max_axburstlen = i_val;
            default:
                f_max_axburstlen = 8'hF;
        endcase
    end
endfunction

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_axi_split_tr_rp0_max_awburstlen <= 8'hF;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_AXI_SPLIT_TR_RP0_ADDR)) begin
        r_axi_split_tr_rp0_max_awburstlen <= f_max_axburstlen(I_PWDATA[15:8]);
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_axi_split_tr_rp0_max_arburstlen <= 8'hF;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_AXI_SPLIT_TR_RP0_ADDR)) begin
        r_axi_split_tr_rp0_max_arburstlen <= f_max_axburstlen(I_PWDATA[7:0]);
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_error_info_rp0_split_mismatch_bid <= 10'b0;
    end else if ((~r_error_info_rp0_split_bid_mismatch_err) && I_ERROR_INFO_RP0_SPLIT_BID_MISMATCH_ERR_SET) begin
        r_error_info_rp0_split_mismatch_bid <= I_ERROR_INFO_RP0_SPLIT_BID_MISMATCH_INFO;
    end else if (~r_error_info_rp0_split_bid_mismatch_err) begin
        r_error_info_rp0_split_mismatch_bid <= 10'b0;
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_error_info_rp0_mismatch_rid <= 10'b0;
    end else if ((~r_error_info_rp0_rid_mismatch_err) && I_ERROR_INFO_RP0_RID_MISMATCH_ERR_SET) begin
        r_error_info_rp0_mismatch_rid <= I_ERROR_INFO_RP0_RID_MISMATCH_INFO;
    end else if (~r_error_info_rp0_rid_mismatch_err) begin
        r_error_info_rp0_mismatch_rid <= 10'b0;
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_error_info_rp0_split_bid_mismatch_err <= 1'h0;
    end else if (I_ERROR_INFO_RP0_SPLIT_BID_MISMATCH_ERR_SET) begin
        r_error_info_rp0_split_bid_mismatch_err <= 1'b1;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_ERROR_INFO_RP0_ADDR) & I_PWDATA[1]) begin
        r_error_info_rp0_split_bid_mismatch_err <= 1'b0;
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_error_info_rp0_rid_mismatch_err <= 1'h0;
    end else if (I_ERROR_INFO_RP0_RID_MISMATCH_ERR_SET) begin
        r_error_info_rp0_rid_mismatch_err <= 1'b1;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_ERROR_INFO_RP0_ADDR) & I_PWDATA[0]) begin
        r_error_info_rp0_rid_mismatch_err <= 1'b0;
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_write_early_response_rp0_write_resp_err <= 1'h0;
    end else if (I_WRITE_EARLY_RESPONSE_RP0_WRITE_RESP_ERR_SET) begin
        r_write_early_response_rp0_write_resp_err <= 1'b1;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_WRITE_EARLY_RESPONSE_RP0_ADDR) & I_PWDATA[13]) begin
        r_write_early_response_rp0_write_resp_err <= 1'b0;
    end
end

always @ (posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_write_early_response_rp0_write_resp_err_id_info <= 10'b0;
        r_write_early_response_rp0_write_resp_err_type_info <= 2'b0;
    end else if ((~r_write_early_response_rp0_write_resp_err) && I_WRITE_EARLY_RESPONSE_RP0_WRITE_RESP_ERR_SET) begin
        r_write_early_response_rp0_write_resp_err_id_info <= I_WRITE_EARLY_RESPONSE_RP0_WRITE_RESP_ERR_ID_INFO;
        r_write_early_response_rp0_write_resp_err_type_info <= I_WRITE_EARLY_RESPONSE_RP0_WRITE_RESP_ERR_TYPE_INFO;
    end else if (~r_write_early_response_rp0_write_resp_err) begin
        r_write_early_response_rp0_write_resp_err_id_info <= 10'b0;
        r_write_early_response_rp0_write_resp_err_type_info <= 2'b0;
    end    
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_write_early_response_rp0_early_bresp_en <= 1'h0;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_WRITE_EARLY_RESPONSE_RP0_ADDR)) begin
        r_write_early_response_rp0_early_bresp_en <= I_PWDATA[0];
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_axi_error_info0_rp0_debug_upper_addr <= 32'h0;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_AXI_ERROR_INFO0_RP0_ADDR)) begin
        r_axi_error_info0_rp0_debug_upper_addr <= I_PWDATA[31:0];
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_axi_error_info1_rp0_debug_lower_addr <= 32'h0;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_AXI_ERROR_INFO1_RP0_ADDR)) begin
        r_axi_error_info1_rp0_debug_lower_addr <= I_PWDATA[31:0];
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_axi_slv_id_mismatch_rp0_en <= 1'h0;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_AXI_SLV_ID_MISMATCH_ERR_RP0_ADDR)) begin
        r_axi_slv_id_mismatch_rp0_en <= I_PWDATA[22];
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_axi_slv_id_mismatch_err_rp0_axi_slv_bid_mismatch_err <= 1'h0;
    end else if (I_AXI_SLV_ID_MISMATCH_ERR_RP0_AXI_SLV_BID_MISMATCH_ERR_SET) begin
        r_axi_slv_id_mismatch_err_rp0_axi_slv_bid_mismatch_err <= 1'b1;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_AXI_SLV_ID_MISMATCH_ERR_RP0_ADDR) & I_PWDATA[1]) begin
        r_axi_slv_id_mismatch_err_rp0_axi_slv_bid_mismatch_err <= 1'b0;
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_axi_slv_id_mismatch_err_rp0_axi_slv_rid_mismatch_err <= 1'h0;
    end else if (I_AXI_SLV_ID_MISMATCH_ERR_RP0_AXI_SLV_RID_MISMATCH_ERR_SET) begin
        r_axi_slv_id_mismatch_err_rp0_axi_slv_rid_mismatch_err <= 1'b1;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_AXI_SLV_ID_MISMATCH_ERR_RP0_ADDR) & I_PWDATA[0]) begin
        r_axi_slv_id_mismatch_err_rp0_axi_slv_rid_mismatch_err <= 1'b0;
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_axi_slv_id_mismatch_err_rp0_bid <= 10'b0;
    end else if ((~r_axi_slv_id_mismatch_err_rp0_axi_slv_bid_mismatch_err) && I_AXI_SLV_ID_MISMATCH_ERR_RP0_AXI_SLV_BID_MISMATCH_ERR_SET) begin
        r_axi_slv_id_mismatch_err_rp0_bid <= I_AXI_SLV_ID_MISMATCH_ERR_RP0_AXI_SLV_BID_MISMATCH_INFO;
    end else if (~r_axi_slv_id_mismatch_err_rp0_axi_slv_bid_mismatch_err) begin
        r_axi_slv_id_mismatch_err_rp0_bid <= 10'b0;
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_axi_slv_id_mismatch_err_rp0_rid <= 10'b0;
    end else if ((~r_axi_slv_id_mismatch_err_rp0_axi_slv_rid_mismatch_err) && I_AXI_SLV_ID_MISMATCH_ERR_RP0_AXI_SLV_RID_MISMATCH_ERR_SET) begin
        r_axi_slv_id_mismatch_err_rp0_rid <= I_AXI_SLV_ID_MISMATCH_ERR_RP0_AXI_SLV_RID_MISMATCH_INFO;
    end else if (~r_axi_slv_id_mismatch_err_rp0_axi_slv_rid_mismatch_err) begin
        r_axi_slv_id_mismatch_err_rp0_rid <= 10'b0;
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_axi_split_tr_rp1_max_awburstlen <= 8'hF;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_AXI_SPLIT_TR_RP1_ADDR)) begin
        r_axi_split_tr_rp1_max_awburstlen <= f_max_axburstlen(I_PWDATA[15:8]);
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_axi_split_tr_rp1_max_arburstlen <= 8'hF;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_AXI_SPLIT_TR_RP1_ADDR)) begin
        r_axi_split_tr_rp1_max_arburstlen <= f_max_axburstlen(I_PWDATA[7:0]);
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_error_info_rp1_split_mismatch_bid <= 10'b0;
    end else if ((~r_error_info_rp1_split_bid_mismatch_err) && I_ERROR_INFO_RP1_SPLIT_BID_MISMATCH_ERR_SET) begin
        r_error_info_rp1_split_mismatch_bid <= I_ERROR_INFO_RP1_SPLIT_BID_MISMATCH_INFO;
    end else if (~r_error_info_rp1_split_bid_mismatch_err) begin
        r_error_info_rp1_split_mismatch_bid <= 10'b0;
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_error_info_rp1_mismatch_rid <= 10'b0;
    end else if ((~r_error_info_rp1_rid_mismatch_err) && I_ERROR_INFO_RP1_RID_MISMATCH_ERR_SET) begin
        r_error_info_rp1_mismatch_rid <= I_ERROR_INFO_RP1_RID_MISMATCH_INFO;
    end else if (~r_error_info_rp1_rid_mismatch_err) begin
        r_error_info_rp1_mismatch_rid <= 10'b0;
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_error_info_rp1_split_bid_mismatch_err <= 1'h0;
    end else if (I_ERROR_INFO_RP1_SPLIT_BID_MISMATCH_ERR_SET) begin
        r_error_info_rp1_split_bid_mismatch_err <= 1'b1;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_ERROR_INFO_RP1_ADDR) & I_PWDATA[1]) begin
        r_error_info_rp1_split_bid_mismatch_err <= 1'b0;
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_error_info_rp1_rid_mismatch_err <= 1'h0;
    end else if (I_ERROR_INFO_RP1_RID_MISMATCH_ERR_SET) begin
        r_error_info_rp1_rid_mismatch_err <= 1'b1;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_ERROR_INFO_RP1_ADDR) & I_PWDATA[0]) begin
        r_error_info_rp1_rid_mismatch_err <= 1'b0;
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_write_early_response_rp1_write_resp_err <= 1'h0;
    end else if (I_WRITE_EARLY_RESPONSE_RP1_WRITE_RESP_ERR_SET) begin
        r_write_early_response_rp1_write_resp_err <= 1'b1;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_WRITE_EARLY_RESPONSE_RP1_ADDR) & I_PWDATA[13]) begin
        r_write_early_response_rp1_write_resp_err <= 1'b0;
    end
end

always @ (posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_write_early_response_rp1_write_resp_err_id_info <= 10'b0;
        r_write_early_response_rp1_write_resp_err_type_info <= 2'b0;
    end else if ((~r_write_early_response_rp1_write_resp_err) && I_WRITE_EARLY_RESPONSE_RP1_WRITE_RESP_ERR_SET) begin
        r_write_early_response_rp1_write_resp_err_id_info <= I_WRITE_EARLY_RESPONSE_RP1_WRITE_RESP_ERR_ID_INFO;
        r_write_early_response_rp1_write_resp_err_type_info <= I_WRITE_EARLY_RESPONSE_RP1_WRITE_RESP_ERR_TYPE_INFO;
    end else if (~r_write_early_response_rp1_write_resp_err) begin
        r_write_early_response_rp1_write_resp_err_id_info <= 10'b0;
        r_write_early_response_rp1_write_resp_err_type_info <= 2'b0;
    end    
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_write_early_response_rp1_early_bresp_en <= 1'h0;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_WRITE_EARLY_RESPONSE_RP1_ADDR)) begin
        r_write_early_response_rp1_early_bresp_en <= I_PWDATA[0];
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_axi_error_info0_rp1_debug_upper_addr <= 32'h0;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_AXI_ERROR_INFO0_RP1_ADDR)) begin
        r_axi_error_info0_rp1_debug_upper_addr <= I_PWDATA[31:0];
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_axi_error_info1_rp1_debug_lower_addr <= 32'h0;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_AXI_ERROR_INFO1_RP1_ADDR)) begin
        r_axi_error_info1_rp1_debug_lower_addr <= I_PWDATA[31:0];
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_axi_slv_id_mismatch_rp1_en <= 1'h0;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_AXI_SLV_ID_MISMATCH_ERR_RP1_ADDR)) begin
        r_axi_slv_id_mismatch_rp1_en <= I_PWDATA[22];
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_axi_slv_id_mismatch_err_rp1_axi_slv_bid_mismatch_err <= 1'h0;
    end else if (I_AXI_SLV_ID_MISMATCH_ERR_RP1_AXI_SLV_BID_MISMATCH_ERR_SET) begin
        r_axi_slv_id_mismatch_err_rp1_axi_slv_bid_mismatch_err <= 1'b1;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_AXI_SLV_ID_MISMATCH_ERR_RP1_ADDR) & I_PWDATA[1]) begin
        r_axi_slv_id_mismatch_err_rp1_axi_slv_bid_mismatch_err <= 1'b0;
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_axi_slv_id_mismatch_err_rp1_axi_slv_rid_mismatch_err <= 1'h0;
    end else if (I_AXI_SLV_ID_MISMATCH_ERR_RP1_AXI_SLV_RID_MISMATCH_ERR_SET) begin
        r_axi_slv_id_mismatch_err_rp1_axi_slv_rid_mismatch_err <= 1'b1;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_AXI_SLV_ID_MISMATCH_ERR_RP1_ADDR) & I_PWDATA[0]) begin
        r_axi_slv_id_mismatch_err_rp1_axi_slv_rid_mismatch_err <= 1'b0;
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_axi_slv_id_mismatch_err_rp1_bid <= 10'b0;
    end else if ((~r_axi_slv_id_mismatch_err_rp1_axi_slv_bid_mismatch_err) && I_AXI_SLV_ID_MISMATCH_ERR_RP1_AXI_SLV_BID_MISMATCH_ERR_SET) begin
        r_axi_slv_id_mismatch_err_rp1_bid <= I_AXI_SLV_ID_MISMATCH_ERR_RP1_AXI_SLV_BID_MISMATCH_INFO;
    end else if (~r_axi_slv_id_mismatch_err_rp1_axi_slv_bid_mismatch_err) begin
        r_axi_slv_id_mismatch_err_rp1_bid <= 10'b0;
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_axi_slv_id_mismatch_err_rp1_rid <= 10'b0;
    end else if ((~r_axi_slv_id_mismatch_err_rp1_axi_slv_rid_mismatch_err) && I_AXI_SLV_ID_MISMATCH_ERR_RP1_AXI_SLV_RID_MISMATCH_ERR_SET) begin
        r_axi_slv_id_mismatch_err_rp1_rid <= I_AXI_SLV_ID_MISMATCH_ERR_RP1_AXI_SLV_RID_MISMATCH_INFO;
    end else if (~r_axi_slv_id_mismatch_err_rp1_axi_slv_rid_mismatch_err) begin
        r_axi_slv_id_mismatch_err_rp1_rid <= 10'b0;
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_axi_split_tr_rp2_max_awburstlen <= 8'hF;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_AXI_SPLIT_TR_RP2_ADDR)) begin
        r_axi_split_tr_rp2_max_awburstlen <= f_max_axburstlen(I_PWDATA[15:8]);
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_axi_split_tr_rp2_max_arburstlen <= 8'hF;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_AXI_SPLIT_TR_RP2_ADDR)) begin
        r_axi_split_tr_rp2_max_arburstlen <= f_max_axburstlen(I_PWDATA[7:0]);
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_error_info_rp2_split_mismatch_bid <= 10'b0;
    end else if ((~r_error_info_rp2_split_bid_mismatch_err) && I_ERROR_INFO_RP2_SPLIT_BID_MISMATCH_ERR_SET) begin
        r_error_info_rp2_split_mismatch_bid <= I_ERROR_INFO_RP2_SPLIT_BID_MISMATCH_INFO;
    end else if (~r_error_info_rp2_split_bid_mismatch_err) begin
        r_error_info_rp2_split_mismatch_bid <= 10'b0;
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_error_info_rp2_mismatch_rid <= 10'b0;
    end else if ((~r_error_info_rp2_rid_mismatch_err) && I_ERROR_INFO_RP2_RID_MISMATCH_ERR_SET) begin
        r_error_info_rp2_mismatch_rid <= I_ERROR_INFO_RP2_RID_MISMATCH_INFO;
    end else if (~r_error_info_rp2_rid_mismatch_err) begin
        r_error_info_rp2_mismatch_rid <= 10'b0;
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_error_info_rp2_split_bid_mismatch_err <= 1'h0;
    end else if (I_ERROR_INFO_RP2_SPLIT_BID_MISMATCH_ERR_SET) begin
        r_error_info_rp2_split_bid_mismatch_err <= 1'b1;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_ERROR_INFO_RP2_ADDR) & I_PWDATA[1]) begin
        r_error_info_rp2_split_bid_mismatch_err <= 1'b0;
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_error_info_rp2_rid_mismatch_err <= 1'h0;
    end else if (I_ERROR_INFO_RP2_RID_MISMATCH_ERR_SET) begin
        r_error_info_rp2_rid_mismatch_err <= 1'b1;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_ERROR_INFO_RP2_ADDR) & I_PWDATA[0]) begin
        r_error_info_rp2_rid_mismatch_err <= 1'b0;
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_write_early_response_rp2_write_resp_err <= 1'h0;
    end else if (I_WRITE_EARLY_RESPONSE_RP2_WRITE_RESP_ERR_SET) begin
        r_write_early_response_rp2_write_resp_err <= 1'b1;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_WRITE_EARLY_RESPONSE_RP2_ADDR) & I_PWDATA[13]) begin
        r_write_early_response_rp2_write_resp_err <= 1'b0;
    end
end

always @ (posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_write_early_response_rp2_write_resp_err_id_info <= 10'b0;
        r_write_early_response_rp2_write_resp_err_type_info <= 2'b0;
    end else if ((~r_write_early_response_rp2_write_resp_err) && I_WRITE_EARLY_RESPONSE_RP2_WRITE_RESP_ERR_SET) begin
        r_write_early_response_rp2_write_resp_err_id_info <= I_WRITE_EARLY_RESPONSE_RP2_WRITE_RESP_ERR_ID_INFO;
        r_write_early_response_rp2_write_resp_err_type_info <= I_WRITE_EARLY_RESPONSE_RP2_WRITE_RESP_ERR_TYPE_INFO;
    end else if (~r_write_early_response_rp2_write_resp_err) begin
        r_write_early_response_rp2_write_resp_err_id_info <= 10'b0;
        r_write_early_response_rp2_write_resp_err_type_info <= 2'b0;
    end    
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_write_early_response_rp2_early_bresp_en <= 1'h0;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_WRITE_EARLY_RESPONSE_RP2_ADDR)) begin
        r_write_early_response_rp2_early_bresp_en <= I_PWDATA[0];
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_axi_error_info0_rp2_debug_upper_addr <= 32'h0;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_AXI_ERROR_INFO0_RP2_ADDR)) begin
        r_axi_error_info0_rp2_debug_upper_addr <= I_PWDATA[31:0];
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_axi_error_info1_rp2_debug_lower_addr <= 32'h0;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_AXI_ERROR_INFO1_RP2_ADDR)) begin
        r_axi_error_info1_rp2_debug_lower_addr <= I_PWDATA[31:0];
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_axi_slv_id_mismatch_rp2_en <= 1'h0;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_AXI_SLV_ID_MISMATCH_ERR_RP2_ADDR)) begin
        r_axi_slv_id_mismatch_rp2_en <= I_PWDATA[22];
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_axi_slv_id_mismatch_err_rp2_axi_slv_bid_mismatch_err <= 1'h0;
    end else if (I_AXI_SLV_ID_MISMATCH_ERR_RP2_AXI_SLV_BID_MISMATCH_ERR_SET) begin
        r_axi_slv_id_mismatch_err_rp2_axi_slv_bid_mismatch_err <= 1'b1;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_AXI_SLV_ID_MISMATCH_ERR_RP2_ADDR) & I_PWDATA[1]) begin
        r_axi_slv_id_mismatch_err_rp2_axi_slv_bid_mismatch_err <= 1'b0;
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_axi_slv_id_mismatch_err_rp2_axi_slv_rid_mismatch_err <= 1'h0;
    end else if (I_AXI_SLV_ID_MISMATCH_ERR_RP2_AXI_SLV_RID_MISMATCH_ERR_SET) begin
        r_axi_slv_id_mismatch_err_rp2_axi_slv_rid_mismatch_err <= 1'b1;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_AXI_SLV_ID_MISMATCH_ERR_RP2_ADDR) & I_PWDATA[0]) begin
        r_axi_slv_id_mismatch_err_rp2_axi_slv_rid_mismatch_err <= 1'b0;
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_axi_slv_id_mismatch_err_rp2_bid <= 10'b0;
    end else if ((~r_axi_slv_id_mismatch_err_rp2_axi_slv_bid_mismatch_err) && I_AXI_SLV_ID_MISMATCH_ERR_RP2_AXI_SLV_BID_MISMATCH_ERR_SET) begin
        r_axi_slv_id_mismatch_err_rp2_bid <= I_AXI_SLV_ID_MISMATCH_ERR_RP2_AXI_SLV_BID_MISMATCH_INFO;
    end else if (~r_axi_slv_id_mismatch_err_rp2_axi_slv_bid_mismatch_err) begin
        r_axi_slv_id_mismatch_err_rp2_bid <= 10'b0;
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_axi_slv_id_mismatch_err_rp2_rid <= 10'b0;
    end else if ((~r_axi_slv_id_mismatch_err_rp2_axi_slv_rid_mismatch_err) && I_AXI_SLV_ID_MISMATCH_ERR_RP2_AXI_SLV_RID_MISMATCH_ERR_SET) begin
        r_axi_slv_id_mismatch_err_rp2_rid <= I_AXI_SLV_ID_MISMATCH_ERR_RP2_AXI_SLV_RID_MISMATCH_INFO;
    end else if (~r_axi_slv_id_mismatch_err_rp2_axi_slv_rid_mismatch_err) begin
        r_axi_slv_id_mismatch_err_rp2_rid <= 10'b0;
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_axi_split_tr_rp3_max_awburstlen <= 8'hF;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_AXI_SPLIT_TR_RP3_ADDR)) begin
        r_axi_split_tr_rp3_max_awburstlen <= f_max_axburstlen(I_PWDATA[15:8]);
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_axi_split_tr_rp3_max_arburstlen <= 8'hF;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_AXI_SPLIT_TR_RP3_ADDR)) begin
        r_axi_split_tr_rp3_max_arburstlen <= f_max_axburstlen(I_PWDATA[7:0]);
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_error_info_rp3_split_mismatch_bid <= 10'b0;
    end else if ((~r_error_info_rp3_split_bid_mismatch_err) && I_ERROR_INFO_RP3_SPLIT_BID_MISMATCH_ERR_SET) begin
        r_error_info_rp3_split_mismatch_bid <= I_ERROR_INFO_RP3_SPLIT_BID_MISMATCH_INFO;
    end else if (~r_error_info_rp3_split_bid_mismatch_err) begin
        r_error_info_rp3_split_mismatch_bid <= 10'b0;
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_error_info_rp3_mismatch_rid <= 10'b0;
    end else if ((~r_error_info_rp3_rid_mismatch_err) && I_ERROR_INFO_RP3_RID_MISMATCH_ERR_SET) begin
        r_error_info_rp3_mismatch_rid <= I_ERROR_INFO_RP3_RID_MISMATCH_INFO;
    end else if (~r_error_info_rp3_rid_mismatch_err) begin
        r_error_info_rp3_mismatch_rid <= 10'b0;
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_error_info_rp3_split_bid_mismatch_err <= 1'h0;
    end else if (I_ERROR_INFO_RP3_SPLIT_BID_MISMATCH_ERR_SET) begin
        r_error_info_rp3_split_bid_mismatch_err <= 1'b1;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_ERROR_INFO_RP3_ADDR) & I_PWDATA[1]) begin
        r_error_info_rp3_split_bid_mismatch_err <= 1'b0;
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_error_info_rp3_rid_mismatch_err <= 1'h0;
    end else if (I_ERROR_INFO_RP3_RID_MISMATCH_ERR_SET) begin
        r_error_info_rp3_rid_mismatch_err <= 1'b1;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_ERROR_INFO_RP3_ADDR) & I_PWDATA[0]) begin
        r_error_info_rp3_rid_mismatch_err <= 1'b0;
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_write_early_response_rp3_write_resp_err <= 1'h0;
    end else if (I_WRITE_EARLY_RESPONSE_RP3_WRITE_RESP_ERR_SET) begin
        r_write_early_response_rp3_write_resp_err <= 1'b1;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_WRITE_EARLY_RESPONSE_RP3_ADDR) & I_PWDATA[13]) begin
        r_write_early_response_rp3_write_resp_err <= 1'b0;
    end
end

always @ (posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_write_early_response_rp3_write_resp_err_id_info <= 10'b0;
        r_write_early_response_rp3_write_resp_err_type_info <= 2'b0;
    end else if ((~r_write_early_response_rp3_write_resp_err) && I_WRITE_EARLY_RESPONSE_RP3_WRITE_RESP_ERR_SET) begin
        r_write_early_response_rp3_write_resp_err_id_info <= I_WRITE_EARLY_RESPONSE_RP3_WRITE_RESP_ERR_ID_INFO;
        r_write_early_response_rp3_write_resp_err_type_info <= I_WRITE_EARLY_RESPONSE_RP3_WRITE_RESP_ERR_TYPE_INFO;
    end else if (~r_write_early_response_rp3_write_resp_err) begin
        r_write_early_response_rp3_write_resp_err_id_info <= 10'b0;
        r_write_early_response_rp3_write_resp_err_type_info <= 2'b0;
    end    
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_write_early_response_rp3_early_bresp_en <= 1'h0;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_WRITE_EARLY_RESPONSE_RP3_ADDR)) begin
        r_write_early_response_rp3_early_bresp_en <= I_PWDATA[0];
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_axi_error_info0_rp3_debug_upper_addr <= 32'h0;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_AXI_ERROR_INFO0_RP3_ADDR)) begin
        r_axi_error_info0_rp3_debug_upper_addr <= I_PWDATA[31:0];
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_axi_error_info1_rp3_debug_lower_addr <= 32'h0;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_AXI_ERROR_INFO1_RP3_ADDR)) begin
        r_axi_error_info1_rp3_debug_lower_addr <= I_PWDATA[31:0];
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_axi_slv_id_mismatch_rp3_en <= 1'h0;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_AXI_SLV_ID_MISMATCH_ERR_RP3_ADDR)) begin
        r_axi_slv_id_mismatch_rp3_en <= I_PWDATA[22];
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_axi_slv_id_mismatch_err_rp3_axi_slv_bid_mismatch_err <= 1'h0;
    end else if (I_AXI_SLV_ID_MISMATCH_ERR_RP3_AXI_SLV_BID_MISMATCH_ERR_SET) begin
        r_axi_slv_id_mismatch_err_rp3_axi_slv_bid_mismatch_err <= 1'b1;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_AXI_SLV_ID_MISMATCH_ERR_RP3_ADDR) & I_PWDATA[1]) begin
        r_axi_slv_id_mismatch_err_rp3_axi_slv_bid_mismatch_err <= 1'b0;
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_axi_slv_id_mismatch_err_rp3_axi_slv_rid_mismatch_err <= 1'h0;
    end else if (I_AXI_SLV_ID_MISMATCH_ERR_RP3_AXI_SLV_RID_MISMATCH_ERR_SET) begin
        r_axi_slv_id_mismatch_err_rp3_axi_slv_rid_mismatch_err <= 1'b1;
    end else if (I_PSEL & ~I_PENABLE & I_PWRITE & (I_PADDR[15:0] == SFR_AXI_SLV_ID_MISMATCH_ERR_RP3_ADDR) & I_PWDATA[0]) begin
        r_axi_slv_id_mismatch_err_rp3_axi_slv_rid_mismatch_err <= 1'b0;
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_axi_slv_id_mismatch_err_rp3_bid <= 10'b0;
    end else if ((~r_axi_slv_id_mismatch_err_rp3_axi_slv_bid_mismatch_err) && I_AXI_SLV_ID_MISMATCH_ERR_RP3_AXI_SLV_BID_MISMATCH_ERR_SET) begin
        r_axi_slv_id_mismatch_err_rp3_bid <= I_AXI_SLV_ID_MISMATCH_ERR_RP3_AXI_SLV_BID_MISMATCH_INFO;
    end else if (~r_axi_slv_id_mismatch_err_rp3_axi_slv_bid_mismatch_err) begin
        r_axi_slv_id_mismatch_err_rp3_bid <= 10'b0;
    end
end

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_axi_slv_id_mismatch_err_rp3_rid <= 10'b0;
    end else if ((~r_axi_slv_id_mismatch_err_rp3_axi_slv_rid_mismatch_err) && I_AXI_SLV_ID_MISMATCH_ERR_RP3_AXI_SLV_RID_MISMATCH_ERR_SET) begin
        r_axi_slv_id_mismatch_err_rp3_rid <= I_AXI_SLV_ID_MISMATCH_ERR_RP3_AXI_SLV_RID_MISMATCH_INFO;
    end else if (~r_axi_slv_id_mismatch_err_rp3_axi_slv_rid_mismatch_err) begin
        r_axi_slv_id_mismatch_err_rp3_rid <= 10'b0;
    end
end

assign O_PREADY  = 1'b1;
assign O_PSLVERR = 1'b0;

reg [31:0] r_rdata;
assign O_PRDATA = r_rdata; 

always @(posedge I_PCLK or negedge I_PRESETN) begin
    if (!I_PRESETN) begin
        r_rdata <= 32'd0;
    end else if (I_PSEL & ~I_PENABLE & ~I_PWRITE) begin
        case (I_PADDR[15:0])
        SFR_IP_VERSION_ADDR : 
            r_rdata <= {I_IP_VERSION_MAJOR_VERSION, I_IP_VERSION_MINOR_VERSION};
        SFR_AOU_CON0_ADDR : 
            r_rdata <= { 4'd0, r_aou_con0_rp3_error_info_access_en, r_aou_con0_rp2_error_info_access_en, r_aou_con0_rp1_error_info_access_en, r_aou_con0_rp0_error_info_access_en, r_aou_con0_rp3_axi_aggregator_en, r_aou_con0_rp2_axi_aggregator_en, r_aou_con0_rp1_axi_aggregator_en, r_aou_con0_rp0_axi_aggregator_en, r_aou_con0_tx_lp_mode_threshold, r_aou_con0_tx_lp_mode,  6'd0, r_aou_con0_aou_sw_reset, r_aou_con0_credit_manage, 1'b0, 1'b0,  1'd0};
        SFR_AOU_INIT_ADDR : 
            r_rdata <= { 20'd0, I_AOU_INIT_INT_DEACTIVATE_PROPERTY, I_AOU_INIT_MST_TR_COMPLETE, I_AOU_INIT_SLV_TR_COMPLETE, r_aou_init_int_activate_start, r_aou_init_int_deactivate_start, r_aou_init_deactivate_time_out_value, I_AOU_INIT_ACTIVATE_STATE_DISABLED, I_AOU_INIT_ACTIVATE_STATE_ENABLED, r_aou_init_deactivate_start, r_aou_init_activate_start};
        SFR_AOU_INTERRUPT_MASK_ADDR : 
            r_rdata <= { 23'd0, r_aou_interrupt_mask_int_req_linkreset_act_ack_mask, r_aou_interrupt_mask_int_req_linkreset_deact_ack_mask, r_aou_interrupt_mask_int_req_linkreset_invalid_actmsg_mask, r_aou_interrupt_mask_int_req_linkreset_msgcredit_timeout_mask, r_aou_interrupt_mask_int_early_resp_mask, r_aou_interrupt_mask_int_mi0_id_mismatch_mask, r_aou_interrupt_mask_int_si0_id_mismatch_mask,  1'd0,  1'd0};
        SFR_LP_LINKRESET_ADDR : 
            r_rdata <= { 18'd0, r_lp_linkreset_ack_time_out_value, r_lp_linkreset_msgcredit_time_out_value, r_lp_linkreset_act_ack_err, r_lp_linkreset_deact_ack_err, r_lp_linkreset_invalid_actmsg_info, r_lp_linkreset_invalid_actmsg_err, r_lp_linkreset_msgcredit_err};
        SFR_DEST_RP_ADDR : 
            r_rdata <= { 18'd0, r_dest_rp_rp3_dest,  2'd0, r_dest_rp_rp2_dest,  2'd0, r_dest_rp_rp1_dest,  2'd0, r_dest_rp_rp0_dest};
        SFR_PRIOR_RP_AXI_ADDR : 
            r_rdata <= {4'd0, r_prior_rp_axi_axi_qos_to_np, r_prior_rp_axi_axi_qos_to_hp,  2'd0, r_prior_rp_axi_rp3_prior,  2'd0, r_prior_rp_axi_rp2_prior,  2'd0, r_prior_rp_axi_rp1_prior,  2'd0, r_prior_rp_axi_rp0_prior,  2'd0, r_prior_rp_axi_arb_mode};
        SFR_PRIOR_TIMER_ADDR : 
            r_rdata <= {r_prior_timer_timer_resolution, r_prior_timer_timer_threshold};
        SFR_AXI_SPLIT_TR_RP0_ADDR : 
            r_rdata <= { 16'd0, r_axi_split_tr_rp0_max_awburstlen, r_axi_split_tr_rp0_max_arburstlen};
        SFR_ERROR_INFO_RP0_ADDR : 
            r_rdata <= { 10'd0, r_error_info_rp0_split_mismatch_bid, r_error_info_rp0_mismatch_rid, r_error_info_rp0_split_bid_mismatch_err, r_error_info_rp0_rid_mismatch_err};
        SFR_WRITE_EARLY_RESPONSE_RP0_ADDR : 
            r_rdata <= { 17'd0, I_WRITE_EARLY_RESPONSE_RP0_WRITE_RESP_DONE, r_write_early_response_rp0_write_resp_err, r_write_early_response_rp0_write_resp_err_type_info, r_write_early_response_rp0_write_resp_err_id_info, r_write_early_response_rp0_early_bresp_en};
        SFR_AXI_ERROR_INFO0_RP0_ADDR : 
            r_rdata <= {r_axi_error_info0_rp0_debug_upper_addr};
        SFR_AXI_ERROR_INFO1_RP0_ADDR : 
            r_rdata <= {r_axi_error_info1_rp0_debug_lower_addr};
        SFR_AXI_SLV_ID_MISMATCH_ERR_RP0_ADDR :
            r_rdata <= { 9'd0, r_axi_slv_id_mismatch_rp0_en, r_axi_slv_id_mismatch_err_rp0_bid, r_axi_slv_id_mismatch_err_rp0_rid, r_axi_slv_id_mismatch_err_rp0_axi_slv_bid_mismatch_err, r_axi_slv_id_mismatch_err_rp0_axi_slv_rid_mismatch_err}; 
        SFR_AXI_SPLIT_TR_RP1_ADDR : 
            r_rdata <= { 16'd0, r_axi_split_tr_rp1_max_awburstlen, r_axi_split_tr_rp1_max_arburstlen};
        SFR_ERROR_INFO_RP1_ADDR : 
            r_rdata <= { 10'd0, r_error_info_rp1_split_mismatch_bid, r_error_info_rp1_mismatch_rid, r_error_info_rp1_split_bid_mismatch_err, r_error_info_rp1_rid_mismatch_err};
        SFR_WRITE_EARLY_RESPONSE_RP1_ADDR : 
            r_rdata <= { 17'd0, I_WRITE_EARLY_RESPONSE_RP1_WRITE_RESP_DONE, r_write_early_response_rp1_write_resp_err, r_write_early_response_rp1_write_resp_err_type_info, r_write_early_response_rp1_write_resp_err_id_info, r_write_early_response_rp1_early_bresp_en};
        SFR_AXI_ERROR_INFO0_RP1_ADDR : 
            r_rdata <= {r_axi_error_info0_rp1_debug_upper_addr};
        SFR_AXI_ERROR_INFO1_RP1_ADDR : 
            r_rdata <= {r_axi_error_info1_rp1_debug_lower_addr};
        SFR_AXI_SLV_ID_MISMATCH_ERR_RP1_ADDR : 
            r_rdata <= { 9'd0, r_axi_slv_id_mismatch_rp1_en, r_axi_slv_id_mismatch_err_rp1_bid, r_axi_slv_id_mismatch_err_rp1_rid, r_axi_slv_id_mismatch_err_rp1_axi_slv_bid_mismatch_err, r_axi_slv_id_mismatch_err_rp1_axi_slv_rid_mismatch_err};
        SFR_AXI_SPLIT_TR_RP2_ADDR : 
            r_rdata <= { 16'd0, r_axi_split_tr_rp2_max_awburstlen, r_axi_split_tr_rp2_max_arburstlen};
        SFR_ERROR_INFO_RP2_ADDR : 
            r_rdata <= { 10'd0, r_error_info_rp2_split_mismatch_bid, r_error_info_rp2_mismatch_rid, r_error_info_rp2_split_bid_mismatch_err, r_error_info_rp2_rid_mismatch_err};
        SFR_WRITE_EARLY_RESPONSE_RP2_ADDR : 
            r_rdata <= { 17'd0, I_WRITE_EARLY_RESPONSE_RP2_WRITE_RESP_DONE, r_write_early_response_rp2_write_resp_err, r_write_early_response_rp2_write_resp_err_type_info, r_write_early_response_rp2_write_resp_err_id_info, r_write_early_response_rp2_early_bresp_en};
        SFR_AXI_ERROR_INFO0_RP2_ADDR : 
            r_rdata <= {r_axi_error_info0_rp2_debug_upper_addr};
        SFR_AXI_ERROR_INFO1_RP2_ADDR : 
            r_rdata <= {r_axi_error_info1_rp2_debug_lower_addr};
        SFR_AXI_SLV_ID_MISMATCH_ERR_RP2_ADDR :
            r_rdata <= { 9'd0, r_axi_slv_id_mismatch_rp2_en, r_axi_slv_id_mismatch_err_rp2_bid, r_axi_slv_id_mismatch_err_rp2_rid, r_axi_slv_id_mismatch_err_rp2_axi_slv_bid_mismatch_err, r_axi_slv_id_mismatch_err_rp2_axi_slv_rid_mismatch_err};
        SFR_AXI_SPLIT_TR_RP3_ADDR : 
            r_rdata <= { 16'd0, r_axi_split_tr_rp3_max_awburstlen, r_axi_split_tr_rp3_max_arburstlen};
        SFR_ERROR_INFO_RP3_ADDR : 
            r_rdata <= { 10'd0, r_error_info_rp3_split_mismatch_bid, r_error_info_rp3_mismatch_rid, r_error_info_rp3_split_bid_mismatch_err, r_error_info_rp3_rid_mismatch_err};
        SFR_WRITE_EARLY_RESPONSE_RP3_ADDR : 
            r_rdata <= { 17'd0, I_WRITE_EARLY_RESPONSE_RP3_WRITE_RESP_DONE, r_write_early_response_rp3_write_resp_err, r_write_early_response_rp3_write_resp_err_type_info, r_write_early_response_rp3_write_resp_err_id_info, r_write_early_response_rp3_early_bresp_en};
        SFR_AXI_ERROR_INFO0_RP3_ADDR : 
            r_rdata <= {r_axi_error_info0_rp3_debug_upper_addr};
        SFR_AXI_ERROR_INFO1_RP3_ADDR : 
            r_rdata <= {r_axi_error_info1_rp3_debug_lower_addr};
        SFR_AXI_SLV_ID_MISMATCH_ERR_RP3_ADDR : 
            r_rdata <= { 9'd0, r_axi_slv_id_mismatch_rp3_en, r_axi_slv_id_mismatch_err_rp3_bid, r_axi_slv_id_mismatch_err_rp3_rid, r_axi_slv_id_mismatch_err_rp3_axi_slv_bid_mismatch_err, r_axi_slv_id_mismatch_err_rp3_axi_slv_rid_mismatch_err};
        default:
            r_rdata <= 32'd0;
        endcase
    end
end

assign O_AOU_CON0_RP3_ERROR_INFO_ACCESS_EN = r_aou_con0_rp3_error_info_access_en;
assign O_AOU_CON0_RP2_ERROR_INFO_ACCESS_EN = r_aou_con0_rp2_error_info_access_en;
assign O_AOU_CON0_RP1_ERROR_INFO_ACCESS_EN = r_aou_con0_rp1_error_info_access_en;
assign O_AOU_CON0_RP0_ERROR_INFO_ACCESS_EN = r_aou_con0_rp0_error_info_access_en;
assign O_AOU_CON0_RP3_AXI_AGGREGATOR_EN = r_aou_con0_rp3_axi_aggregator_en;
assign O_AOU_CON0_RP2_AXI_AGGREGATOR_EN = r_aou_con0_rp2_axi_aggregator_en;
assign O_AOU_CON0_RP1_AXI_AGGREGATOR_EN = r_aou_con0_rp1_axi_aggregator_en;
assign O_AOU_CON0_RP0_AXI_AGGREGATOR_EN = r_aou_con0_rp0_axi_aggregator_en;
assign O_AOU_CON0_TX_LP_MODE_THRESHOLD = r_aou_con0_tx_lp_mode_threshold;
assign O_AOU_CON0_TX_LP_MODE = r_aou_con0_tx_lp_mode;
assign O_AOU_CON0_AOU_SW_RESET = r_aou_con0_aou_sw_reset;
assign O_AOU_CON0_CREDIT_MANAGE = r_aou_con0_credit_manage;
assign O_AOU_CON0_DEACTIVATE_FORCE = r_aou_con0_deactivate_force;
assign O_AOU_INIT_DEACTIVATE_TIME_OUT_VALUE = r_aou_init_deactivate_time_out_value;
assign O_AOU_INIT_DEACTIVATE_START = r_aou_init_deactivate_start;
assign O_AOU_INIT_ACTIVATE_START = r_aou_init_activate_start;
assign O_AOU_INTERRUPT_MASK_INT_REQ_LINKRESET_ACT_ACK_MASK = r_aou_interrupt_mask_int_req_linkreset_act_ack_mask;
assign O_AOU_INTERRUPT_MASK_INT_REQ_LINKRESET_DEACT_ACK_MASK = r_aou_interrupt_mask_int_req_linkreset_deact_ack_mask;
assign O_AOU_INTERRUPT_MASK_INT_REQ_LINKRESET_INVALID_ACTMSG_MASK = r_aou_interrupt_mask_int_req_linkreset_invalid_actmsg_mask;
assign O_AOU_INTERRUPT_MASK_INT_REQ_LINKRESET_MSGCREDIT_TIMEOUT_MASK = r_aou_interrupt_mask_int_req_linkreset_msgcredit_timeout_mask;
assign O_AOU_INTERRUPT_MASK_INT_EARLY_RESP_MASK = r_aou_interrupt_mask_int_early_resp_mask;
assign O_AOU_INTERRUPT_MASK_INT_MI0_ID_MISMATCH_MASK = r_aou_interrupt_mask_int_mi0_id_mismatch_mask;
assign O_AOU_INTERRUPT_MASK_INT_SI0_ID_MISMATCH_MASK = r_aou_interrupt_mask_int_si0_id_mismatch_mask;
assign O_LP_LINKRESET_ACK_TIME_OUT_VALUE = r_lp_linkreset_ack_time_out_value;
assign O_LP_LINKRESET_MSGCREDIT_TIME_OUT_VALUE = r_lp_linkreset_msgcredit_time_out_value;
assign O_DEST_RP_RP3_DEST    = r_dest_rp_rp3_dest;
assign O_DEST_RP_RP2_DEST    = r_dest_rp_rp2_dest;
assign O_DEST_RP_RP1_DEST    = r_dest_rp_rp1_dest;
assign O_DEST_RP_RP0_DEST    = r_dest_rp_rp0_dest;
assign O_PRIOR_RP_AXI_AXI_QOS_TO_NP = r_prior_rp_axi_axi_qos_to_np;
assign O_PRIOR_RP_AXI_AXI_QOS_TO_HP = r_prior_rp_axi_axi_qos_to_hp;
assign O_PRIOR_RP_AXI_RP3_PRIOR = r_prior_rp_axi_rp3_prior;
assign O_PRIOR_RP_AXI_RP2_PRIOR = r_prior_rp_axi_rp2_prior;
assign O_PRIOR_RP_AXI_RP1_PRIOR = r_prior_rp_axi_rp1_prior;
assign O_PRIOR_RP_AXI_RP0_PRIOR = r_prior_rp_axi_rp0_prior;
assign O_PRIOR_RP_AXI_ARB_MODE = r_prior_rp_axi_arb_mode;
assign O_PRIOR_TIMER_TIMER_RESOLUTION = r_prior_timer_timer_resolution;
assign O_PRIOR_TIMER_TIMER_THRESHOLD = r_prior_timer_timer_threshold;
assign O_AXI_SPLIT_TR_RP0_MAX_AWBURSTLEN = r_axi_split_tr_rp0_max_awburstlen;
assign O_AXI_SPLIT_TR_RP0_MAX_ARBURSTLEN = r_axi_split_tr_rp0_max_arburstlen;
assign O_WRITE_EARLY_RESPONSE_RP0_EARLY_BRESP_EN = r_write_early_response_rp0_early_bresp_en;
assign O_AXI_ERROR_INFO0_RP0_DEBUG_UPPER_ADDR = r_axi_error_info0_rp0_debug_upper_addr;
assign O_AXI_ERROR_INFO1_RP0_DEBUG_LOWER_ADDR = r_axi_error_info1_rp0_debug_lower_addr;
assign O_AXI_SPLIT_TR_RP1_MAX_AWBURSTLEN = r_axi_split_tr_rp1_max_awburstlen;
assign O_AXI_SPLIT_TR_RP1_MAX_ARBURSTLEN = r_axi_split_tr_rp1_max_arburstlen;
assign O_WRITE_EARLY_RESPONSE_RP1_EARLY_BRESP_EN = r_write_early_response_rp1_early_bresp_en;
assign O_AXI_ERROR_INFO0_RP1_DEBUG_UPPER_ADDR = r_axi_error_info0_rp1_debug_upper_addr;
assign O_AXI_ERROR_INFO1_RP1_DEBUG_LOWER_ADDR = r_axi_error_info1_rp1_debug_lower_addr;
assign O_AXI_SPLIT_TR_RP2_MAX_AWBURSTLEN = r_axi_split_tr_rp2_max_awburstlen;
assign O_AXI_SPLIT_TR_RP2_MAX_ARBURSTLEN = r_axi_split_tr_rp2_max_arburstlen;
assign O_WRITE_EARLY_RESPONSE_RP2_EARLY_BRESP_EN = r_write_early_response_rp2_early_bresp_en;
assign O_AXI_ERROR_INFO0_RP2_DEBUG_UPPER_ADDR = r_axi_error_info0_rp2_debug_upper_addr;
assign O_AXI_ERROR_INFO1_RP2_DEBUG_LOWER_ADDR = r_axi_error_info1_rp2_debug_lower_addr;
assign O_AXI_SPLIT_TR_RP3_MAX_AWBURSTLEN = r_axi_split_tr_rp3_max_awburstlen;
assign O_AXI_SPLIT_TR_RP3_MAX_ARBURSTLEN = r_axi_split_tr_rp3_max_arburstlen;
assign O_WRITE_EARLY_RESPONSE_RP3_EARLY_BRESP_EN = r_write_early_response_rp3_early_bresp_en;
assign O_AXI_ERROR_INFO0_RP3_DEBUG_UPPER_ADDR = r_axi_error_info0_rp3_debug_upper_addr;
assign O_AXI_ERROR_INFO1_RP3_DEBUG_LOWER_ADDR = r_axi_error_info1_rp3_debug_lower_addr;
assign O_AXI_SLV_ID_MISMATCH_RP0_EN = r_axi_slv_id_mismatch_rp0_en; 
assign O_AXI_SLV_ID_MISMATCH_RP1_EN = r_axi_slv_id_mismatch_rp1_en;
assign O_AXI_SLV_ID_MISMATCH_RP2_EN = r_axi_slv_id_mismatch_rp2_en;
assign O_AXI_SLV_ID_MISMATCH_RP3_EN = r_axi_slv_id_mismatch_rp3_en;

assign O_SPLIT_BID_MISMATCH_ERROR = r_error_info_rp0_split_bid_mismatch_err | r_error_info_rp1_split_bid_mismatch_err | r_error_info_rp2_split_bid_mismatch_err | r_error_info_rp3_split_bid_mismatch_err;
assign O_RID_MISMATCH_ERROR = r_error_info_rp0_rid_mismatch_err | r_error_info_rp1_rid_mismatch_err | r_error_info_rp2_rid_mismatch_err | r_error_info_rp3_rid_mismatch_err;
assign O_ACT_ACK_ERR        = r_lp_linkreset_act_ack_err;
assign O_DEACT_ACK_ERR      = r_lp_linkreset_deact_ack_err;
assign O_INVALID_ACTMSG_ERR = r_lp_linkreset_invalid_actmsg_err;
assign O_MSGCREDIT_ERR      = r_lp_linkreset_msgcredit_err;
assign O_AXI_SLV_RID_MISMATCH_ERROR = r_axi_slv_id_mismatch_err_rp0_axi_slv_rid_mismatch_err | r_axi_slv_id_mismatch_err_rp1_axi_slv_bid_mismatch_err | r_axi_slv_id_mismatch_err_rp2_axi_slv_bid_mismatch_err | r_axi_slv_id_mismatch_err_rp3_axi_slv_bid_mismatch_err;
assign O_AXI_SLV_BID_MISMATCH_ERROR = r_axi_slv_id_mismatch_err_rp0_axi_slv_bid_mismatch_err | r_axi_slv_id_mismatch_err_rp1_axi_slv_rid_mismatch_err | r_axi_slv_id_mismatch_err_rp2_axi_slv_rid_mismatch_err | r_axi_slv_id_mismatch_err_rp3_axi_slv_rid_mismatch_err;
assign ERR_SLV_EARLY_RESP_ERR = r_write_early_response_rp0_write_resp_err | r_write_early_response_rp1_write_resp_err | r_write_early_response_rp2_write_resp_err | r_write_early_response_rp3_write_resp_err;
assign INT_ACTIVATE_START   = r_aou_init_int_activate_start;
assign INT_DEACTIVATE_START = r_aou_init_int_deactivate_start;

endmodule

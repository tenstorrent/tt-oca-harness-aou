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
//  Module     : AOU_ACTIVATION_CTRL
//  Version    : 1.00
//  Date       : 26-02-26
//  Author     : Soyoung Min, Jaeyun Lee, Hojun Lee, Kwanho Kim
//
// *****************************************************************************

`timescale 1ns/1ps

module AOU_ACTIVATION_CTRL
(
    input           I_CLK                           ,
    input           I_RESETN                        ,
    
    //initiate Activation Req
    input           I_UCIE_INIT_DONE                ,
    input           I_ACTIVATE_START                ,
    //input Activation message
    input   [3:0]   I_ACTMSG_ACTIVATION_OP          ,
    input           I_ACTMSG_PROPERTYREQ            ,
    input           I_ACTMSG_VALID                  ,
    
    //output Activation message
    output  [3:0]   O_ACTMSG_ACTIVATION_OP          ,
    output          O_ACTMSG_PROPERTYREQ            ,
    output          O_ACTMSG_VALID                  ,
    input           I_ACTMSG_READY                  ,

    //Signal to determine when to issue a Deactivate request
    input   [2:0]   I_DEACTIVATE_TIME_OUT_VALUE     ,
    input           I_DEACTIVATE_START              , 
    input           I_DEACTIVATE_FORCE              ,
    input           I_TX_PENDING                    ,//and check tx fifo count and ring buffer valid
    input           I_TX_AXI_TR_PENDING             ,

    input           I_SLV_BUS_CLEANY_COMPLETE       ,//from bus cleany
    input           I_AOU_RX_FIFO_PENDING           ,        
    
    input           I_CRDTGRANT_VALID               ,

    input   [2:0]   I_ACK_TIME_OUT_VALUE            ,
    input   [2:0]   I_MSGCREDIT_TIME_OUT_VALUE      ,

    output          O_ACT_ACK_ERR                   ,
    output          O_DEACT_ACK_ERR                 ,
    output  [3:0]   O_INVALID_ACTMSG_INFO           ,
    output          O_INVALID_ACTMSG_ERR            ,
    output          O_MSGCREDIT_ERR                 ,

    //output signal
    output          O_CRD_COUNT_EN                  ,
    output          O_REQ_CRD_ADVERTISE_EN          ,
    output          O_TX_REQ_CREDITED_MESSAGE_EN    ,
    output          O_RSP_CRD_ADVERTISE_EN          ,
    output          O_TX_RSP_CREDITED_MESSAGE_EN    ,

    output          O_STATUS_DISABLED               ,
    output          O_STATUS_ENABLED                ,
    output          O_STATUS_DEACTIVATE             ,    

    output          O_INT_ACTIVATE_START            ,
    output          O_INT_DEACTIVATE_START          ,
    output          O_INT_FDI_LINK_DOWN             ,
    output          O_DEACTIVATE_PROPERTY

);

localparam  DISABLED        = 4'b0001,
            ACTIVATE        = 4'b0010,
            ENABLED         = 4'b0100,
            DEACTIVATE      = 4'b1000;

localparam  ACTIVATE_REQ    = 4'b0000,
            ACTIVATE_ACK    = 4'b0001,
            DEACTIVATE_REQ  = 4'b0010,
            DEACTIVATE_ACK  = 4'b0011;

logic [3:0] r_cur_st;
logic [3:0] w_nxt_st;

logic       st_update;

logic       r_activate_start_1d;
logic       w_activate_start_rising_edge_detect;

logic       r_deactivate_start_1d;
logic       w_deactivate_start_rising_edge_detect;

logic       r_deactivate_force_1d;
logic       w_deactivate_force_rising_edge_detect;

logic       r_tx_deactivate_req;
logic       r_tx_deactivate_ack;
logic       r_rx_deactivate_req;
logic       r_rx_deactivate_ack;

logic       r_rx_deactivate_propertyreq;

logic       r_tx_activate_req;
logic       r_tx_activate_ack;
logic       r_rx_activate_req;
logic       r_rx_activate_ack;

logic       w_activate_related0;
logic       w_deactivate_related0;

logic       w_activate_related1;
logic       w_deactivate_related1;

logic       w_deactivate_reg_clear;
logic       w_activate_reg_clear;

logic       w_svalid0;
logic [4:0] w_sdata0;
logic       w_svalid1;
logic [4:0] w_sdata1;

logic [11:0]r_time_out;
logic       w_time_out_done;

logic [11:0]w_time_out_value;

logic       w_activate_en;
logic       w_deactivate_en;

logic       w_lp_linkerror_start;
logic       r_lp_linkerror_pending;

logic       r_ucie_init_done_1d;
logic       w_fdi_link_fell;
logic       w_act_req_pending;
logic       w_fdi_link_lost;
logic       w_fsm_abort;

assign      w_activate_en   = ((r_cur_st == DISABLED) | (r_cur_st == ACTIVATE  )) & ~(r_tx_activate_req | ((O_ACTMSG_ACTIVATION_OP == ACTIVATE_REQ) & O_ACTMSG_VALID))
                            & ~(r_lp_linkerror_pending | w_lp_linkerror_start);
assign      w_deactivate_en = ((r_cur_st == ENABLED)  | (r_cur_st == DEACTIVATE)) & ~(r_tx_deactivate_req | ((O_ACTMSG_ACTIVATION_OP == DEACTIVATE_REQ) & O_ACTMSG_VALID));

//-------------------------------------------------------------
//After a LinkReset request no new activation starts until software resets
//AOU_CORE (MAS 7.2.3, 7.3.6). The LinkReset condition is a one-cycle pulse that
//returns the FSM to DISABLED and clears the outstanding-request flag; with
//ACTIVATE_START still set, the start edge detector would otherwise see the
//enable return and send a second ActivateReq. This flag holds the activation
//enable (the start edge and INT_ACTIVATE_START) and the entry into ACTIVATE
//until the core reset, in the direction of the AoU v0.8 ERROR state (8.3.3,
//8.4). The enable also drops in the cycle of the condition itself: the
//invalid-message pulse is combinational from the received message, so a start
//edge in that cycle would otherwise queue an ActivateReq that nothing clears.
//Every LinkReset source is a detected partner error (time-out or invalid
//activation message), so a compliant partner never sets it.
always_ff @ (posedge I_CLK or negedge I_RESETN) begin
    if(~I_RESETN) begin
        r_lp_linkerror_pending <= 1'b0;
    end else if (w_lp_linkerror_start) begin
        r_lp_linkerror_pending <= 1'b1;
    end
end


//-------------------------------------------------------------
always_comb begin
    case(I_DEACTIVATE_TIME_OUT_VALUE)
        3'b000: w_time_out_value = 12'd8;
        3'b001: w_time_out_value = 12'd16;
        3'b010: w_time_out_value = 12'd32;
        3'b011: w_time_out_value = 12'd64;
        3'b100: w_time_out_value = 12'd128;
        3'b101: w_time_out_value = 12'd256;
        3'b110: w_time_out_value = 12'd512;
        3'b111: w_time_out_value = 12'd1024;
    endcase
end 
//-------------------------------------------------------------
//edge detect logic
always_ff @ (posedge I_CLK or negedge I_RESETN) begin
    if(~I_RESETN)begin
        r_activate_start_1d <= 1'b0;
    end else begin
        r_activate_start_1d <= I_UCIE_INIT_DONE & I_ACTIVATE_START & w_activate_en & (~I_AOU_RX_FIFO_PENDING);
    end
end

assign  w_activate_start_rising_edge_detect  =   ~r_activate_start_1d & (I_ACTIVATE_START & I_UCIE_INIT_DONE & w_activate_en & (~I_AOU_RX_FIFO_PENDING));

always_ff @ (posedge I_CLK or negedge I_RESETN) begin
    if(~I_RESETN)begin
        r_deactivate_start_1d <= 1'b0;
    end else begin
        r_deactivate_start_1d <= I_DEACTIVATE_START & w_time_out_done & w_deactivate_en & I_SLV_BUS_CLEANY_COMPLETE;        
    end
end

// AoU v0.8 8.4: DeactivateReq only once this die's own requests have completed.
// Responses this die still owes may follow it, so they do not hold it back.
assign  w_deactivate_start_rising_edge_detect   = ~r_deactivate_start_1d & (I_DEACTIVATE_START & w_time_out_done & w_deactivate_en & I_SLV_BUS_CLEANY_COMPLETE);

always_ff @ (posedge I_CLK or negedge I_RESETN) begin
    if(~I_RESETN) begin
        r_deactivate_force_1d <= 1'b0;
    end else begin
        r_deactivate_force_1d <= I_DEACTIVATE_FORCE & w_deactivate_en;
    end
end

assign w_deactivate_force_rising_edge_detect = ~r_deactivate_force_1d & (I_DEACTIVATE_FORCE & w_deactivate_en);


always_ff @ (posedge I_CLK or negedge I_RESETN) begin
    if (~I_RESETN) begin
        r_ucie_init_done_1d <= 1'b0;
    end else begin
        r_ucie_init_done_1d <= I_UCIE_INIT_DONE;
    end
end

// FDI link lost: the falling edge of the link-established indication. In
// every state it clears the handshake registers and time-out waits and holds
// the FSM in DISABLED (w_fsm_abort), so a request latched, accepted by the
// transmit path or arriving in that cycle cannot start a handshake on a link
// that is already down. It is reported (O_INT_FDI_LINK_DOWN) when a session
// or an activation handshake is outstanding: outside DISABLED, or in DISABLED
// with such a request. AoU spec v0.8 8.3.3: the activation FSM leaves for
// DISABLED on an error. A link that falls in DISABLED with nothing outstanding
// is no event of this FSM. Not a LinkReset request: the link is already down.
assign w_fdi_link_fell     = r_ucie_init_done_1d & ~I_UCIE_INIT_DONE;
assign w_act_req_pending   = r_tx_activate_req | r_rx_activate_req
                           | ((O_ACTMSG_ACTIVATION_OP == ACTIVATE_REQ) & O_ACTMSG_VALID & I_ACTMSG_READY)
                           | ((I_ACTMSG_ACTIVATION_OP == ACTIVATE_REQ) & I_ACTMSG_VALID);
assign w_fdi_link_lost     = w_fdi_link_fell & ((r_cur_st != DISABLED) | w_act_req_pending);
assign w_fsm_abort         = w_lp_linkerror_start | w_fdi_link_fell;
assign O_INT_FDI_LINK_DOWN = w_fdi_link_lost;

//-------------------------------------------------------------
//Deactivate Reqest, ack register 

always_ff @ (posedge I_CLK or negedge I_RESETN) begin
    if(~I_RESETN) begin
        r_tx_deactivate_req <= 1'b0;
    end else if (w_fsm_abort) begin
        r_tx_deactivate_req <= 1'b0;
    end else if((O_ACTMSG_ACTIVATION_OP == DEACTIVATE_REQ) & O_ACTMSG_VALID & I_ACTMSG_READY) begin
        r_tx_deactivate_req <= 1'b1;
    end else if (w_deactivate_reg_clear) begin
        r_tx_deactivate_req <= 1'b0;
    end
end

always_ff @ (posedge I_CLK or negedge I_RESETN) begin
    if(~I_RESETN) begin
        r_tx_deactivate_ack <= 1'b0;
    end else if (w_fsm_abort) begin
        r_tx_deactivate_ack <= 1'b0;
    end else if ((I_ACTMSG_ACTIVATION_OP == DEACTIVATE_ACK) & I_ACTMSG_VALID)begin
        r_tx_deactivate_ack <= 1'b1;
    end else if (w_deactivate_reg_clear) begin
        r_tx_deactivate_ack <= 1'b0;
    end
end

always_ff @ (posedge I_CLK or negedge I_RESETN) begin
    if(~I_RESETN) begin
        r_rx_deactivate_req <= 1'b0;
    end else if (w_fsm_abort) begin
        r_rx_deactivate_req <= 1'b0;
    end else if ((I_ACTMSG_ACTIVATION_OP == DEACTIVATE_REQ) & I_ACTMSG_VALID)begin
        r_rx_deactivate_req <= 1'b1;
    end else if (w_deactivate_reg_clear) begin
        r_rx_deactivate_req <= 1'b0;
    end
end

always_ff @ (posedge I_CLK or negedge I_RESETN) begin
    if(~I_RESETN) begin
        r_rx_deactivate_ack <= 1'b0;
    end else if (w_fsm_abort) begin
        r_rx_deactivate_ack <= 1'b0;
    end else if ((O_ACTMSG_ACTIVATION_OP == DEACTIVATE_ACK) & O_ACTMSG_VALID & I_ACTMSG_READY)begin
        r_rx_deactivate_ack <= 1'b1;
    end else if (w_deactivate_reg_clear) begin
        r_rx_deactivate_ack <= 1'b0;
    end
end

always_ff @ (posedge I_CLK or negedge I_RESETN) begin
    if(~I_RESETN) begin
        r_tx_activate_req <= 1'b0;
    end else if (w_fsm_abort) begin
        r_tx_activate_req <= 1'b0;
    end else if ((O_ACTMSG_ACTIVATION_OP == ACTIVATE_REQ) & O_ACTMSG_VALID & I_ACTMSG_READY) begin
        r_tx_activate_req <= 1'b1;
    end else if (w_activate_reg_clear) begin
        r_tx_activate_req <= 1'b0;
    end
end

//The received-Ack flag is state of the ACTIVATE handshake and is kept only in
//ACTIVATE: outside it the flag is held clear, so it is reset when the FSM
//leaves ACTIVATE and an ActivateAck received in any other state is not
//retained. Our own ActivateReq is outstanding only in ACTIVATE (the FSM
//enters it the cycle after the request is accepted), so an Ack in DISABLED
//answers nothing; kept, it completed the next handshake before the peer's
//real Ack, which then arrived in ENABLED and requested LinkReset.
always_ff @ (posedge I_CLK or negedge I_RESETN) begin
    if(~I_RESETN) begin
        r_tx_activate_ack <= 1'b0;
    end else if (w_fsm_abort | (r_cur_st != ACTIVATE)) begin
        r_tx_activate_ack <= 1'b0;
    end else if ((I_ACTMSG_ACTIVATION_OP == ACTIVATE_ACK) & I_ACTMSG_VALID) begin
        r_tx_activate_ack <= 1'b1;
    end else if (w_activate_reg_clear) begin
        r_tx_activate_ack <= 1'b0;
    end
end


//The abort has priority over every handshake register set: a request or Ack
//in the abort cycle would otherwise survive into DISABLED and restart the
//handshake (a request) or complete the next one early (an Ack). The one-cycle
//abort comes with a LinkReset request or a lost link, so software resets the
//core before the next session; a message accepted in that cycle is lost.
//An ActivateReq in ENABLED or DEACTIVATE is the invalid message that requests
//LinkReset (w_activate_related1 sends it no Ack); it must not be remembered
//either, or the FSM, DISABLED by that error, would re-enter ACTIVATE on it.
always_ff @ (posedge I_CLK or negedge I_RESETN) begin
    if(~I_RESETN) begin
        r_rx_activate_req <= 1'b0;
    end else if (w_fsm_abort) begin
        r_rx_activate_req <= 1'b0;
    end else if ((I_ACTMSG_ACTIVATION_OP == ACTIVATE_REQ) & I_ACTMSG_VALID
                 & ~((r_cur_st == ENABLED) | (r_cur_st == DEACTIVATE))) begin
        r_rx_activate_req <= 1'b1;
    end else if (w_activate_reg_clear) begin
        r_rx_activate_req <= 1'b0;
    end
end


always_ff @ (posedge I_CLK or negedge I_RESETN) begin
    if(~I_RESETN) begin
        r_rx_activate_ack <= 1'b0;
    end else if (w_fsm_abort) begin
        r_rx_activate_ack <= 1'b0;
    end else if ((O_ACTMSG_ACTIVATION_OP == ACTIVATE_ACK) & O_ACTMSG_VALID & I_ACTMSG_READY) begin
        r_rx_activate_ack <= 1'b1;
    end else if (w_activate_reg_clear) begin
        r_rx_activate_ack <= 1'b0;
    end
end

always_ff @ (posedge I_CLK or negedge I_RESETN) begin
    if(~I_RESETN) begin
        r_rx_deactivate_propertyreq <= 1'b0;
    end else if (w_fsm_abort) begin
        r_rx_deactivate_propertyreq <= 1'b0;
    end else if ((I_ACTMSG_ACTIVATION_OP == DEACTIVATE_REQ) & I_ACTMSG_VALID & I_ACTMSG_PROPERTYREQ)begin
        r_rx_deactivate_propertyreq <= 1'b1;
    end else if (w_deactivate_reg_clear) begin
        r_rx_deactivate_propertyreq <= 1'b0;
    end
end

//-------------------------------------------------------------
assign st_update = (r_cur_st != w_nxt_st);

always_ff @ (posedge I_CLK or negedge I_RESETN) begin
    if(~I_RESETN) begin
        r_cur_st <= DISABLED;
    end else if (st_update) begin
        r_cur_st <= w_nxt_st;
    end
end

//The abort (an error that requests LinkReset, or the FDI link lost) is a
//one-cycle pulse and has priority over a handshake step in the same cycle:
//the handshake registers are cleared by it (and not set in that cycle), so
//the state must not advance on them. In DISABLED it cancels a pending entry
//to ACTIVATE: the request that asked for it is cleared in the same cycle.
//After a LinkReset request the FSM stays in DISABLED until the core reset.
always_comb begin
    case(r_cur_st)
        DISABLED:begin
            if (w_fsm_abort) begin
                w_nxt_st = DISABLED;
            end else if((r_tx_activate_req | r_rx_activate_req) & ~r_lp_linkerror_pending)  begin
                w_nxt_st = ACTIVATE;
            end else begin
                w_nxt_st = DISABLED;
            end
        end
        ACTIVATE:begin
            if (w_fsm_abort) begin
                w_nxt_st = DISABLED;
            end else if(r_tx_activate_req & r_tx_activate_ack & r_rx_activate_req & r_rx_activate_ack) begin
                w_nxt_st = ENABLED;
            end else begin
                w_nxt_st = ACTIVATE;
            end
        end
        ENABLED:begin
            if (w_fsm_abort) begin
                w_nxt_st = DISABLED;
            end else if(r_tx_deactivate_req | r_rx_deactivate_req) begin
                w_nxt_st = DEACTIVATE;
            end else begin
                w_nxt_st = ENABLED;
            end
        end
        DEACTIVATE:begin
            if (w_fsm_abort) begin
                w_nxt_st = DISABLED;
            end else if(r_tx_deactivate_req & r_rx_deactivate_req & r_tx_deactivate_ack & r_rx_deactivate_ack) begin
                w_nxt_st = DISABLED;
            end else begin
                w_nxt_st = DEACTIVATE;
            end
        end
        default: w_nxt_st = DISABLED;
    endcase
end 
//-------------------------------------------------------------
assign w_activate_reg_clear   = ((r_cur_st == ACTIVATE)   & (w_nxt_st == ENABLED )); 
assign w_deactivate_reg_clear = ((r_cur_st == DEACTIVATE) & (w_nxt_st == DISABLED));
//-------------------------------------------------------------
assign  w_activate_related0      = w_activate_start_rising_edge_detect;
assign  w_deactivate_related0    = w_deactivate_start_rising_edge_detect | w_deactivate_force_rising_edge_detect;

//An ActivateReq in ENABLED or DEACTIVATE is an invalid activation message (ERROR in
//AoU v0.8 8.3.3, nothing transmitted, 8.4): no ActivateAck, only the LinkReset request
assign  w_activate_related1      = (I_ACTMSG_ACTIVATION_OP == ACTIVATE_REQ) & I_ACTMSG_VALID
                                 & ~((r_cur_st == ENABLED) | (r_cur_st == DEACTIVATE));
assign  w_deactivate_related1    = (I_ACTMSG_ACTIVATION_OP == DEACTIVATE_REQ) & I_ACTMSG_VALID;

//svalid 0 is for ACTIVATE_REQ & DEACTIVATE_REQ
//svalid 1 is for ACTIVATE_ACK & DEACTIVATE_ACK
assign  w_svalid0               = w_activate_related0 | w_deactivate_related0;
assign  w_sdata0                = w_activate_related0 ? {ACTIVATE_REQ, 1'b0} : w_deactivate_start_rising_edge_detect ? {DEACTIVATE_REQ, 1'b0} :  {DEACTIVATE_REQ, 1'b1};
assign  w_svalid1               = w_activate_related1 | w_deactivate_related1;
assign  w_sdata1                = w_activate_related1 ? {ACTIVATE_ACK, 1'b0} : {DEACTIVATE_ACK, 1'b0};

AOU_SYNC_FIFO_NS1M #(
    .FIFO_WIDTH      (4 + 1),   //ACTIVATION_OP + PROPERTYREQ
    .FIFO_DEPTH      (4),       //depth 3 is enough, never occur overflow    
    .ICH_CNT         (2)
) u_aou_sync_2s1m_activation
(
    .I_CLK           ( I_CLK                                            ),
    .I_RESETN        ( I_RESETN                                         ),

    .I_SVALID        ( {w_svalid1, w_svalid0}                           ),
    .I_SDATA         ( {w_sdata1, w_sdata0}                             ),
    .O_SREADY        (                                                  ),

    .I_MREADY        ( I_ACTMSG_READY                                   ),
    .O_MDATA         ( {O_ACTMSG_ACTIVATION_OP, O_ACTMSG_PROPERTYREQ}   ), 
    .O_MVALID        ( O_ACTMSG_VALID                                   ),
    
    .O_S_EMPTY_CNT   (                                                  ),
    .O_M_DATA_CNT    (                                                  )
);

//-------------------------------------------------------------
assign O_CRD_COUNT_EN           = ((r_cur_st == ACTIVATE) & (r_tx_activate_ack | ((I_ACTMSG_ACTIVATION_OP == ACTIVATE_ACK) & I_ACTMSG_VALID)))
                                  | (r_cur_st == ENABLED) 
                                  | (r_cur_st == DEACTIVATE) ; 
//Reqest and WriteData message
assign O_REQ_CRD_ADVERTISE_EN       = ((r_cur_st == ACTIVATE) & (r_rx_activate_ack | (((O_ACTMSG_ACTIVATION_OP == ACTIVATE_ACK) & O_ACTMSG_VALID & I_ACTMSG_READY))))
                                    | (((r_cur_st == DEACTIVATE) | (r_cur_st == ENABLED)) & ~(r_rx_deactivate_req));

assign O_TX_REQ_CREDITED_MESSAGE_EN = ((r_cur_st == ACTIVATE) & (r_tx_activate_req & r_rx_activate_ack & r_rx_activate_req & (((I_ACTMSG_ACTIVATION_OP == ACTIVATE_ACK) & I_ACTMSG_VALID)|r_tx_activate_ack)))
                                  | ((r_cur_st == ENABLED) & (~(r_tx_deactivate_req | ((O_ACTMSG_ACTIVATION_OP == DEACTIVATE_REQ) & O_ACTMSG_VALID & I_ACTMSG_READY))))
                                  | ((r_cur_st == DEACTIVATE) & (~(r_tx_deactivate_req | ((O_ACTMSG_ACTIVATION_OP == DEACTIVATE_REQ) & O_ACTMSG_VALID & I_ACTMSG_READY))));

//Read Data, Write response message
//AoU v0.8 8.4: responses are still sent after this die's DeactivateReq, and
//their credits are still advertised after its DeactivateAck while its own
//requests are outstanding; both stop once no further response can be owed.
assign O_RSP_CRD_ADVERTISE_EN       = ((r_cur_st == ACTIVATE) & (r_rx_activate_ack | (((O_ACTMSG_ACTIVATION_OP == ACTIVATE_ACK) & O_ACTMSG_VALID & I_ACTMSG_READY))))
                                  | (((r_cur_st == DEACTIVATE) | (r_cur_st == ENABLED)) & ~(r_tx_deactivate_req));

assign O_TX_RSP_CREDITED_MESSAGE_EN = ((r_cur_st == ACTIVATE) & (r_tx_activate_req & r_rx_activate_ack & r_rx_activate_req & (((I_ACTMSG_ACTIVATION_OP == ACTIVATE_ACK) & I_ACTMSG_VALID)|r_tx_activate_ack)))
                                  | ((r_cur_st == ENABLED) & (~(r_rx_deactivate_req | ((I_ACTMSG_ACTIVATION_OP == DEACTIVATE_REQ) & I_ACTMSG_VALID))))
                                  | ((r_cur_st == DEACTIVATE) & (~(r_rx_deactivate_req | ((I_ACTMSG_ACTIVATION_OP == DEACTIVATE_REQ) & I_ACTMSG_VALID))));

assign O_STATUS_DISABLED        = (r_cur_st == DISABLED);
assign O_STATUS_ENABLED         = (r_cur_st == ENABLED);
assign O_STATUS_DEACTIVATE      = (r_cur_st == DEACTIVATE);

assign O_INT_ACTIVATE_START   = (~I_ACTIVATE_START) & ((I_TX_AXI_TR_PENDING | (~I_SLV_BUS_CLEANY_COMPLETE) | r_rx_activate_req) & w_activate_en);
assign O_INT_DEACTIVATE_START = (r_cur_st == DEACTIVATE) & ~(r_tx_deactivate_req | ((O_ACTMSG_ACTIVATION_OP == DEACTIVATE_REQ) & O_ACTMSG_VALID)) & (((~I_DEACTIVATE_START) & (~r_rx_deactivate_propertyreq)) | ((~I_DEACTIVATE_FORCE) & r_rx_deactivate_propertyreq));
assign O_DEACTIVATE_PROPERTY  = r_rx_deactivate_propertyreq;
//-------------------------------------------------------------
assign  w_time_out_done = (r_time_out == w_time_out_value);

always_ff @ (posedge I_CLK or negedge I_RESETN) begin
    if(~I_RESETN) begin
        r_time_out <= 'd0;
    end else if ((r_cur_st == DISABLED) | (r_cur_st == ACTIVATE)) begin
        r_time_out <= 'd0;
    end else if (((r_cur_st == ENABLED)|(r_cur_st == DEACTIVATE)) & I_TX_PENDING)  begin
        r_time_out <= 'd0;
    end else if (~w_time_out_done) begin
        r_time_out <= r_time_out + 1;
    end
end


//-- LP_LINKERROR --------
// The three time-out waits below (Ack after a Req, MsgCredit after an Ack)
// are abandoned by the abort, with priority over starting one in the same
// cycle: the handshake they time is over, and a wait left running would
// report a second error (and request LinkReset) after the FSM has been
// DISABLED. The counters clear on the abort and on the awaited message as
// well: a count one below the limit would otherwise still step onto it on
// that edge (the enable is cleared on the same edge) and report a time-out
// for a cancelled wait, or for a response that arrived one cycle inside the
// deadline. Otherwise they clear themselves the cycle after their enable.
// Activation Ack timeout
logic [31:0]    r_act_req_to_ack_cnt;
logic           r_act_req_send;
logic           w_act_req_to_ack_error;

always_ff @ (posedge I_CLK or negedge I_RESETN) begin
    if (~I_RESETN) begin
        r_act_req_send <= 1'b0;
    end else if (w_fsm_abort) begin
        r_act_req_send <= 1'b0;
    end else if ((O_ACTMSG_ACTIVATION_OP == ACTIVATE_REQ) & O_ACTMSG_VALID & I_ACTMSG_READY) begin
        r_act_req_send <= 1'b1;
    end else if ((I_ACTMSG_ACTIVATION_OP == ACTIVATE_ACK) & I_ACTMSG_VALID) begin
        r_act_req_send <= 1'b0;
    end else if (w_act_req_to_ack_error) begin
        r_act_req_send <= 1'b0;
    end
end

always_ff @ (posedge I_CLK or negedge I_RESETN) begin
    if (~I_RESETN) begin
        r_act_req_to_ack_cnt <= 'b0;
    end else if (w_fsm_abort | ((I_ACTMSG_ACTIVATION_OP == ACTIVATE_ACK) & I_ACTMSG_VALID)) begin
        r_act_req_to_ack_cnt <= 'b0;
    end else if (r_act_req_send) begin
        r_act_req_to_ack_cnt <= r_act_req_to_ack_cnt + 1;
    end else if (|r_act_req_to_ack_cnt) begin//~r_act_req_send
        r_act_req_to_ack_cnt <= 'b0;
    end
end

always_comb begin
    w_act_req_to_ack_error = (r_act_req_to_ack_cnt == (1 << (I_ACK_TIME_OUT_VALUE + 18)));
end

// Deactivation Ack timeout
logic [31:0]    r_deact_req_to_ack_cnt;
logic           r_deact_req_send;
logic           w_deact_req_to_ack_error;

always_ff @ (posedge I_CLK or negedge I_RESETN) begin
    if (~I_RESETN) begin
        r_deact_req_send <= 1'b0;
    end else if (w_fsm_abort) begin
        r_deact_req_send <= 1'b0;
    end else if ((O_ACTMSG_ACTIVATION_OP == DEACTIVATE_REQ) & O_ACTMSG_VALID & I_ACTMSG_READY) begin
        r_deact_req_send <= 1'b1;
    end else if ((I_ACTMSG_ACTIVATION_OP == DEACTIVATE_ACK) & I_ACTMSG_VALID) begin
        r_deact_req_send <= 1'b0;
    end else if (w_deact_req_to_ack_error) begin
        r_deact_req_send <= 1'b0;
    end
end

always_ff @ (posedge I_CLK or negedge I_RESETN) begin
    if (~I_RESETN) begin
        r_deact_req_to_ack_cnt <= 'b0;
    end else if (w_fsm_abort | ((I_ACTMSG_ACTIVATION_OP == DEACTIVATE_ACK) & I_ACTMSG_VALID)) begin
        r_deact_req_to_ack_cnt <= 'b0;
    end else if (r_deact_req_send) begin
        r_deact_req_to_ack_cnt <= r_deact_req_to_ack_cnt + 1;
    end else if (|r_deact_req_to_ack_cnt) begin//~r_deact_req_send
        r_deact_req_to_ack_cnt <= 'b0;
    end
end

always_comb begin
    w_deact_req_to_ack_error = (r_deact_req_to_ack_cnt == (1 << (I_ACK_TIME_OUT_VALUE + 18)));
end

// Invalid ACTMSG
logic           w_invalid_msgtype;

always_comb begin
    case (r_cur_st)
        DISABLED : begin
            if ((I_ACTMSG_ACTIVATION_OP == DEACTIVATE_REQ) & I_ACTMSG_VALID) begin
                w_invalid_msgtype = 1'b1;
            end else if ((I_ACTMSG_ACTIVATION_OP == DEACTIVATE_ACK) & I_ACTMSG_VALID) begin
                w_invalid_msgtype = 1'b1;
            end else begin
                w_invalid_msgtype = 1'b0;
            end
        end
        ACTIVATE : begin
            if ((I_ACTMSG_ACTIVATION_OP == DEACTIVATE_REQ) & I_ACTMSG_VALID) begin
                w_invalid_msgtype = 1'b1;
            end else if ((I_ACTMSG_ACTIVATION_OP == DEACTIVATE_ACK) & I_ACTMSG_VALID) begin
                w_invalid_msgtype = 1'b1;
            end else begin
                w_invalid_msgtype = 1'b0;
            end
        end
        ENABLED : begin
            if ((I_ACTMSG_ACTIVATION_OP == ACTIVATE_REQ) & I_ACTMSG_VALID) begin
                w_invalid_msgtype = 1'b1;
            end else if ((I_ACTMSG_ACTIVATION_OP == ACTIVATE_ACK) & I_ACTMSG_VALID) begin
                w_invalid_msgtype = 1'b1;
            end else begin
                w_invalid_msgtype = 1'b0;
            end
        end
        DEACTIVATE : begin
            if ((I_ACTMSG_ACTIVATION_OP == ACTIVATE_REQ) & I_ACTMSG_VALID) begin
                w_invalid_msgtype = 1'b1;
            end else if ((I_ACTMSG_ACTIVATION_OP == ACTIVATE_ACK) & I_ACTMSG_VALID) begin
                w_invalid_msgtype = 1'b1;
            end else begin
                w_invalid_msgtype = 1'b0;
            end
        end
        default : w_invalid_msgtype = 1'b0;
    endcase
end


assign O_INVALID_ACTMSG_INFO = w_invalid_msgtype ? I_ACTMSG_ACTIVATION_OP : 'b0;
assign O_INVALID_ACTMSG_ERR  = w_invalid_msgtype;

// MsgCredit timeout
logic [31:0]    r_act_act_to_msgcredit_cnt;
logic           r_act_ack_receive;
logic           w_msgcredit_receive_err;

//The wait for MsgCredit is armed by the Ack to our own ActivateReq, which can
//only arrive in ACTIVATE; an Ack received in any other state is not an Ack to
//us and arms nothing. The wait itself outlives ACTIVATE: the handshake can
//complete before the peer's MsgCredit arrives.
always_ff @ (posedge I_CLK or negedge I_RESETN) begin
    if (~I_RESETN) begin
        r_act_ack_receive <= 1'b0;
    end else if (w_fsm_abort) begin
        r_act_ack_receive <= 1'b0;
    end else if ((I_ACTMSG_ACTIVATION_OP == ACTIVATE_ACK) & I_ACTMSG_VALID & (r_cur_st == ACTIVATE)) begin
        r_act_ack_receive <= 1'b1;
    end else if (I_CRDTGRANT_VALID) begin
        r_act_ack_receive <= 1'b0;
    end else if (w_msgcredit_receive_err) begin
        r_act_ack_receive <= 1'b0;
    end
end

always_ff @ (posedge I_CLK or negedge I_RESETN) begin
    if (~I_RESETN) begin
        r_act_act_to_msgcredit_cnt <= 'b0;
    end else if (w_fsm_abort | I_CRDTGRANT_VALID) begin
        r_act_act_to_msgcredit_cnt <= 'b0;
    end else if (r_act_ack_receive) begin
        r_act_act_to_msgcredit_cnt <= r_act_act_to_msgcredit_cnt + 1;
    end else if (|r_act_act_to_msgcredit_cnt) begin//~r_act_ack_receive
        r_act_act_to_msgcredit_cnt <= 'b0;
    end
end

always_comb begin
    w_msgcredit_receive_err = (r_act_act_to_msgcredit_cnt == (1 << (I_MSGCREDIT_TIME_OUT_VALUE + 18)));
end

assign w_lp_linkerror_start = O_ACT_ACK_ERR || O_DEACT_ACK_ERR || O_MSGCREDIT_ERR || O_INVALID_ACTMSG_ERR;

assign O_ACT_ACK_ERR   = w_act_req_to_ack_error;
assign O_DEACT_ACK_ERR = w_deact_req_to_ack_error;
assign O_MSGCREDIT_ERR = w_msgcredit_receive_err;

endmodule

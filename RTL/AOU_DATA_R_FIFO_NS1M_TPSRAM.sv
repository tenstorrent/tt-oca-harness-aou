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
//  Module     : AOU_DATA_R_FIFO_NS1M_TPSRAM
//  Version    : 1.00
//  Date       : 26-02-26
//  Author     : Soyoung Min, Jaeyun Lee, Hojun Lee, Kwanho Kim
//
// *****************************************************************************

`timescale 1ns/1ps

module AOU_DATA_R_FIFO_NS1M_TPSRAM
#(
    parameter   AXI_PEER_DIE_MAX_DATA_WD    = 1024,
    localparam  DATA_FIFO_WD                = 256,
    localparam  AXI_CON                     = AXI_PEER_DIE_MAX_DATA_WD/DATA_FIFO_WD,
    parameter   EXT_FIFO_WD                 = 10 + 2 + 1,//RID+RRESP+RLAST
    parameter   FIFO_DEPTH                  = 140,            // depth
    parameter   ICH_CNT                     = 8,          // input channel count
    parameter   DEC_MULTI                   = 2,

    localparam  REQ_CNT                     = (DEC_MULTI == 1) ? 6 : (DEC_MULTI == 2) ? 7 : 11,
    localparam  REQ_CNT_WD                  = $clog2(REQ_CNT+1),
    localparam  SRAM_DEPTH                  = (FIFO_DEPTH+REQ_CNT-1)/REQ_CNT,
    localparam  DATA_AW                     = $clog2(SRAM_DEPTH),
    
    localparam  REGFIFO_DEPTH               = (ICH_CNT > 3) ? ((DEC_MULTI == 1) ? 3 : (DEC_MULTI == 2) ? 4 : 8) : 3,
    localparam  REGFIFO_AW                  = $clog2(REGFIFO_DEPTH+1),

    localparam  CTRL_FIFO_DEPTH             = FIFO_DEPTH + REGFIFO_DEPTH,
    localparam  CTRL_FIFO_AW                = $clog2(CTRL_FIFO_DEPTH),
    localparam  CTRL_FIFO_WD                = 2,//DLEN
    parameter   ALWAYS_READY                = 0

)
(
    input                                                   I_CLK,
    input                                                   I_RESETN,

    input  [ICH_CNT-1:0]                                    I_SVALID,
    input  [ICH_CNT-1:0][AXI_PEER_DIE_MAX_DATA_WD-1:0]      I_SDATA,
    input  [ICH_CNT-1:0][EXT_FIFO_WD-1:0]                   I_EXT_SDATA,
    output                                                  O_SREADY,
    
    input                                                   I_MREADY,
    output [AXI_PEER_DIE_MAX_DATA_WD-1:0]                   O_MDATA,
    output [EXT_FIFO_WD-1:0]                                O_EXT_MDATA,
    output [1:0]                                            O_MDLEN,
    output                                                  O_MVALID,

    output  [REQ_CNT-1:0]                                   O_FIFO_SRAM_RD_ENB,
    output  [REQ_CNT-1:0][DATA_AW -1:0]                     O_FIFO_SRAM_RD_ADDR,
    input   [REQ_CNT-1:0][DATA_FIFO_WD+EXT_FIFO_WD-1:0]     I_FIFO_SRAM_RD_DATA,

    output  [REQ_CNT-1:0]                                   O_FIFO_SRAM_WR_ENB,
    output  [REQ_CNT-1:0][DATA_AW-1:0]                      O_FIFO_SRAM_WR_ADDR,
    output  [REQ_CNT-1:0][DATA_FIFO_WD+EXT_FIFO_WD-1:0]     O_FIFO_SRAM_WR_DATA

);
    
    logic [CTRL_FIFO_DEPTH-1:0][CTRL_FIFO_WD-1:0]                   ctrl_fifo;
    logic [REQ_CNT-1:0][CTRL_FIFO_WD-1:0]                           nxt_ctrl_data;
   
    logic [CTRL_FIFO_AW-1:0]                                        r_ctrl_ptr;
    logic [REQ_CNT_WD-1:0]                                          ctrl_req_cnt;
    logic [CTRL_FIFO_AW-1:0]                                        r_ctrl_sram_ptr;
    logic [CTRL_FIFO_AW-1:0]                                        w_ctrl_ptr;
    logic [CTRL_FIFO_AW-1:0]                                        nxt_r_ctrl_ptr;
    logic [CTRL_FIFO_AW-1:0]                                        nxt_r_ctrl_sram_ptr;
    logic [REQ_CNT-1:0][CTRL_FIFO_AW-1:0]                           nxt_w_ctrl_ptr;

    logic [REQ_CNT_WD-1:0]                                          wr_sram_idx;
    logic [REQ_CNT_WD-1:0]                                          write_req_cnt; 
    logic [REQ_CNT-1:0]                                             nxt_wr_sram_idx_valid;
    
    logic [REQ_CNT_WD-1:0]                                          rd_sram_idx;
    logic [REQ_CNT_WD-1:0]                                          rd_sram_idx_d1;
    logic [REQ_CNT_WD-1:0]                                          read_req_cnt;
    logic [REQ_CNT-1:0]                                             nxt_rd_sram_idx_valid;

    logic [REQ_CNT-1:0][DATA_AW-1:0]                                r_data_ptr;
    logic [REQ_CNT-1:0][DATA_AW-1:0]                                w_data_ptr;
    logic [REQ_CNT-1:0][DATA_AW-1:0]                                nxt_r_data_ptr;
    logic [REQ_CNT-1:0][DATA_AW-1:0]                                nxt_w_data_ptr;

    logic [REQ_CNT-1:0]                                             r_ex_data_ptr;
    logic [REQ_CNT-1:0]                                             w_ex_data_ptr;
    logic [REQ_CNT-1:0]                                             nxt_r_ex_data_ptr;
    logic [REQ_CNT-1:0]                                             nxt_w_ex_data_ptr;
    
    logic [1:0]                                                     o_mdlen;
    logic [1:0]                                                     o_mdlen_cen_a;
    logic [CTRL_FIFO_AW-1:0]                                        nxt_r_ctrl_sram_ptr_cen_a;

//--------------------sram-------------------------------------------
    logic [REQ_CNT-1:0][DATA_AW-1:0]                                addr_a;//read ptr
    logic                                                           cen_a_tmp;
    logic [REQ_CNT-1:0]                                             cen_a;
    logic                                                           r_cen_a_d1;

    logic [REQ_CNT-1:0][DATA_AW-1:0]                                addr_b;//write ptr
    logic [ICH_CNT-1:0]                                             cen_b_tmp;
    logic [REQ_CNT-1:0]                                             cen_b;
    logic [REQ_CNT-1:0][DATA_FIFO_WD+EXT_FIFO_WD-1:0]               sram_wr_data;
    
    logic                                                           w_sram_dout_valid;
    logic [REQ_CNT-1:0][DATA_FIFO_WD+EXT_FIFO_WD-1:0]               w_sram_dout;
    logic                                                           r_sram_dout_d1_valid;
    logic [REQ_CNT-1:0][DATA_FIFO_WD+EXT_FIFO_WD-1:0]               r_sram_dout_d1;

//-------------------sramfifo-------------------------------------
    logic [ICH_CNT-1:0]                                             bypass_sramfifo;
    logic [REQ_CNT-1:0]                                             w_sramfifo_empty_tmp;
    logic                                                           w_sramfifo_empty;
    logic                                                           w_sramfifo_full;
    logic                                                           w_sramfifo_mvalid;

//-------------------regfifo--------------------------------------
    logic [AXI_CON-1:0][DATA_FIFO_WD+EXT_FIFO_WD-1:0]               w_regfifo_input_data;

    logic [ICH_CNT-1:0]                                             w_regfifo_svalid;
    logic [ICH_CNT-1:0][AXI_PEER_DIE_MAX_DATA_WD+EXT_FIFO_WD-1:0]   w_regfifo_sdata;
    logic                                                           w_regfifo_sready;

    logic                                                           w_regfifo_mready;
    logic [AXI_PEER_DIE_MAX_DATA_WD+EXT_FIFO_WD-1:0]                w_regfifo_mdata;
    logic                                                           w_regfifo_mvalid;

    logic [REGFIFO_AW-1:0]                                          w_regfifo_empty_cnt;
    logic [REQ_CNT_WD-1:0]                                          regfifo_tmp_cnt;

//-------------sram flow control signals----------------------------
    logic [REQ_CNT_WD-1:0] next_wr_sram_idx;
    logic [REQ_CNT_WD-1:0] next_rd_sram_idx;
    always_comb begin
        nxt_wr_sram_idx_valid = 'd0;
        write_req_cnt = 'd0;
        nxt_rd_sram_idx_valid = 'd0;
        read_req_cnt = 'd0;
        sram_wr_data = 'd0;

        next_wr_sram_idx = 'd0;
        next_rd_sram_idx = 'd0;
        for(int dec_multi = 0; dec_multi < DEC_MULTI; dec_multi = dec_multi + 1) begin
            if(~cen_b_tmp[dec_multi*4+0]) begin
                for(int sram_cnt = 0; sram_cnt < 4; sram_cnt = sram_cnt + 1) begin
                    next_wr_sram_idx = ((wr_sram_idx + write_req_cnt) >= REQ_CNT) ? (wr_sram_idx + write_req_cnt - REQ_CNT) : (wr_sram_idx + write_req_cnt);
                    nxt_wr_sram_idx_valid[next_wr_sram_idx] = 1'b1;
                    sram_wr_data[next_wr_sram_idx] = {I_EXT_SDATA[dec_multi*4+0], I_SDATA[dec_multi*4+0][(DATA_FIFO_WD*sram_cnt) +: DATA_FIFO_WD]};
                    write_req_cnt = write_req_cnt + 1;
                end
            end else if(~cen_b_tmp[dec_multi*4+1]) begin
                for(int sram_cnt = 0; sram_cnt < 2; sram_cnt = sram_cnt + 1) begin
                    next_wr_sram_idx = ((wr_sram_idx + write_req_cnt) >= REQ_CNT) ? (wr_sram_idx + write_req_cnt - REQ_CNT) : (wr_sram_idx + write_req_cnt);
                    nxt_wr_sram_idx_valid[next_wr_sram_idx] = 1'b1;
                    sram_wr_data[next_wr_sram_idx] = {I_EXT_SDATA[dec_multi*4+1], I_SDATA[dec_multi*4+1][(DATA_FIFO_WD*sram_cnt) +: DATA_FIFO_WD]};
                    write_req_cnt = write_req_cnt + 1;
                end
            end
            if(~cen_b_tmp[dec_multi*4+2]) begin
                next_wr_sram_idx = ((wr_sram_idx + write_req_cnt) >= REQ_CNT) ? (wr_sram_idx + write_req_cnt - REQ_CNT) : (wr_sram_idx + write_req_cnt);
                nxt_wr_sram_idx_valid[next_wr_sram_idx] = 1'b1;
                sram_wr_data[next_wr_sram_idx] = {I_EXT_SDATA[dec_multi*4+2], I_SDATA[dec_multi*4+2][DATA_FIFO_WD-1:0]};
                write_req_cnt = write_req_cnt + 1;
            end
            if(~cen_b_tmp[dec_multi*4+3]) begin
                next_wr_sram_idx = ((wr_sram_idx + write_req_cnt) >= REQ_CNT) ? (wr_sram_idx + write_req_cnt - REQ_CNT) : (wr_sram_idx + write_req_cnt);
                nxt_wr_sram_idx_valid[next_wr_sram_idx] = 1'b1;
                sram_wr_data[next_wr_sram_idx] = {I_EXT_SDATA[dec_multi*4+3], I_SDATA[dec_multi*4+3][DATA_FIFO_WD-1:0]};
                write_req_cnt = write_req_cnt + 1; 
            end   
        end
        
        if(~cen_a_tmp) begin
            for(int read_cnt = 0; read_cnt < AXI_CON; read_cnt = read_cnt + 1) begin
                if(read_cnt < (1 << o_mdlen_cen_a)) begin
                    next_rd_sram_idx = ((rd_sram_idx + read_req_cnt) >= REQ_CNT) ? (rd_sram_idx + read_req_cnt - REQ_CNT) : (rd_sram_idx + read_req_cnt);
                    nxt_rd_sram_idx_valid[next_rd_sram_idx] = 1'b1;
                    read_req_cnt = read_req_cnt + 1;
                end
            end
        end
    end
    
    always_comb begin
        for(int sram_cnt = 0; sram_cnt < REQ_CNT; sram_cnt = sram_cnt + 1) begin
            nxt_w_data_ptr[sram_cnt] = w_data_ptr[sram_cnt];
            nxt_r_data_ptr[sram_cnt] = r_data_ptr[sram_cnt];      
        
            if(~cen_b[sram_cnt])
                nxt_w_data_ptr[sram_cnt] = (w_data_ptr[sram_cnt] == SRAM_DEPTH - 1) ? ({DATA_AW{1'b0}}) : (w_data_ptr[sram_cnt] + 1'b1);                    

            if(~cen_a[sram_cnt])
                nxt_r_data_ptr[sram_cnt] = (r_data_ptr[sram_cnt] == SRAM_DEPTH - 1) ? ({DATA_AW{1'b0}}) : (r_data_ptr[sram_cnt] + 1'b1);                    

        end
    end

    genvar sram_cnt;
    generate 
        for(sram_cnt = 0; sram_cnt < REQ_CNT; sram_cnt = sram_cnt + 1) begin
            assign nxt_w_ex_data_ptr[sram_cnt] = (~cen_b[sram_cnt] && (w_data_ptr[sram_cnt] == SRAM_DEPTH-1)) ? ~w_ex_data_ptr[sram_cnt] : w_ex_data_ptr[sram_cnt];
            assign nxt_r_ex_data_ptr[sram_cnt] = (nxt_rd_sram_idx_valid[sram_cnt] && (r_data_ptr[sram_cnt] == SRAM_DEPTH-1)) ? ~r_ex_data_ptr[sram_cnt] : r_ex_data_ptr[sram_cnt]; 
        end
    endgenerate

    always @(posedge I_CLK or negedge I_RESETN) begin
        if (!I_RESETN) begin
            w_data_ptr      <= 'd0;
            r_data_ptr      <= 'd0;
            w_ex_data_ptr   <= 'd0;
            r_ex_data_ptr   <= 'd0;
        
            rd_sram_idx     <= 'd0;
            rd_sram_idx_d1  <= 'd0;
            wr_sram_idx     <= 'd0;

        end else begin
            for(int sram_cnt = 0; sram_cnt < REQ_CNT; sram_cnt = sram_cnt + 1) begin
                if(~cen_b[sram_cnt]) begin
                    w_data_ptr[sram_cnt]    <= nxt_w_data_ptr[sram_cnt];
                    w_ex_data_ptr[sram_cnt] <= nxt_w_ex_data_ptr[sram_cnt];
                end
            end
                
            if(|cen_b)
                wr_sram_idx <= ((wr_sram_idx + write_req_cnt) >= REQ_CNT) ? (wr_sram_idx + write_req_cnt - REQ_CNT) : (wr_sram_idx + write_req_cnt);
            
            if(~cen_a_tmp) begin
                for(int sram_cnt = 0; sram_cnt < REQ_CNT; sram_cnt = sram_cnt + 1) begin
                    r_data_ptr[sram_cnt]    <= nxt_r_data_ptr[sram_cnt];
                    r_ex_data_ptr[sram_cnt] <= nxt_r_ex_data_ptr[sram_cnt];
                end
                rd_sram_idx <= ((rd_sram_idx + read_req_cnt) >= REQ_CNT) ? (rd_sram_idx + read_req_cnt - REQ_CNT) : (rd_sram_idx + read_req_cnt);
                rd_sram_idx_d1 <= rd_sram_idx;
            end
        end
    end

    generate
        for(sram_cnt = 0; sram_cnt < REQ_CNT; sram_cnt = sram_cnt + 1) begin  
            assign w_sramfifo_empty_tmp[sram_cnt] = ((w_data_ptr[sram_cnt] == r_data_ptr[sram_cnt]) && (w_ex_data_ptr[sram_cnt] == r_ex_data_ptr[sram_cnt]));
        end
    endgenerate

    assign w_sramfifo_empty     = &w_sramfifo_empty_tmp;
    assign w_sramfifo_full      = ((w_data_ptr[wr_sram_idx] == r_data_ptr[wr_sram_idx]) && (w_ex_data_ptr[wr_sram_idx] != r_ex_data_ptr[wr_sram_idx]));

    assign O_SREADY             = (ALWAYS_READY) ? 1 : (~w_sramfifo_full);
//-------------extra fifo flow control signals----------------------------
    always_comb begin
        ctrl_req_cnt = 'd0;//
        nxt_w_ctrl_ptr = 'd0;
        nxt_ctrl_data = 'd0;

        for(int dec_multi = 0; dec_multi < DEC_MULTI; dec_multi = dec_multi + 1) begin       
            if(I_SVALID[dec_multi*4+0]) begin
                nxt_ctrl_data[ctrl_req_cnt] = 2'b10;
                nxt_w_ctrl_ptr[ctrl_req_cnt] = ((w_ctrl_ptr + ctrl_req_cnt) >= CTRL_FIFO_DEPTH) ? ((w_ctrl_ptr + ctrl_req_cnt) - CTRL_FIFO_DEPTH) : (w_ctrl_ptr + ctrl_req_cnt);
                ctrl_req_cnt = ctrl_req_cnt + 1;
            end else if(I_SVALID[dec_multi*4+1]) begin
                nxt_ctrl_data[ctrl_req_cnt] = 2'b01;
                nxt_w_ctrl_ptr[ctrl_req_cnt] = ((w_ctrl_ptr + ctrl_req_cnt) >= CTRL_FIFO_DEPTH) ? ((w_ctrl_ptr + ctrl_req_cnt) - CTRL_FIFO_DEPTH) : (w_ctrl_ptr + ctrl_req_cnt);
                ctrl_req_cnt = ctrl_req_cnt + 1;
            end
            if(I_SVALID[dec_multi*4+2]) begin
                nxt_ctrl_data[ctrl_req_cnt] = 2'b00;
                nxt_w_ctrl_ptr[ctrl_req_cnt] = ((w_ctrl_ptr + ctrl_req_cnt) >= CTRL_FIFO_DEPTH) ? ((w_ctrl_ptr + ctrl_req_cnt) - CTRL_FIFO_DEPTH) : (w_ctrl_ptr + ctrl_req_cnt);
                ctrl_req_cnt = ctrl_req_cnt + 1;
            end
            if(I_SVALID[dec_multi*4+3]) begin
                nxt_ctrl_data[ctrl_req_cnt] = 2'b00;
                nxt_w_ctrl_ptr[ctrl_req_cnt] = ((w_ctrl_ptr + ctrl_req_cnt) >= CTRL_FIFO_DEPTH) ? ((w_ctrl_ptr + ctrl_req_cnt) - CTRL_FIFO_DEPTH) : (w_ctrl_ptr + ctrl_req_cnt);
                ctrl_req_cnt = ctrl_req_cnt + 1;
            end
        end
    end

    always @(posedge I_CLK or negedge I_RESETN) begin
        if (!I_RESETN) begin
            ctrl_fifo <= 'd0;                
            w_ctrl_ptr <= 'd0;
        end else begin
            if(|I_SVALID && O_SREADY) begin
                for(int ctrl_cnt = 0; ctrl_cnt < ICH_CNT; ctrl_cnt = ctrl_cnt +1) begin
                    if(ctrl_cnt < ctrl_req_cnt)
                        ctrl_fifo[nxt_w_ctrl_ptr[ctrl_cnt]] <= nxt_ctrl_data[ctrl_cnt];
                end
                w_ctrl_ptr <= (w_ctrl_ptr + ctrl_req_cnt >= CTRL_FIFO_DEPTH) ? (w_ctrl_ptr + ctrl_req_cnt - CTRL_FIFO_DEPTH) : (w_ctrl_ptr + ctrl_req_cnt);
            end           
        end
    end

    assign o_mdlen  = ctrl_fifo[r_ctrl_sram_ptr];
    assign o_mdlen_cen_a = (w_regfifo_sready & (r_sram_dout_d1_valid | ~r_cen_a_d1)) ? ctrl_fifo[nxt_r_ctrl_sram_ptr_cen_a] : ctrl_fifo[r_ctrl_sram_ptr];

    assign O_MDLEN  = ctrl_fifo[r_ctrl_ptr];
    assign nxt_r_ctrl_sram_ptr_cen_a = ((r_ctrl_sram_ptr + 1) == CTRL_FIFO_DEPTH) ? 'd0 : (r_ctrl_sram_ptr + 1);

    always_comb begin
        nxt_r_ctrl_ptr = r_ctrl_ptr;
        nxt_r_ctrl_sram_ptr = r_ctrl_sram_ptr;
    
        if(|w_regfifo_svalid & w_regfifo_sready) begin
            for(int req_cnt = 0; req_cnt < ICH_CNT; req_cnt = req_cnt + 1) begin
                if(w_regfifo_svalid[req_cnt])
                    nxt_r_ctrl_sram_ptr = ((nxt_r_ctrl_sram_ptr + 1) == CTRL_FIFO_DEPTH) ? 'd0 : (nxt_r_ctrl_sram_ptr + 1);
            end
        end

        if(I_MREADY && O_MVALID)
            nxt_r_ctrl_ptr = ((nxt_r_ctrl_ptr + 1) == CTRL_FIFO_DEPTH) ? 'd0 : (nxt_r_ctrl_ptr + 1);
    end
                
    always @(posedge I_CLK or negedge I_RESETN) begin
        if (!I_RESETN) begin
            r_ctrl_ptr <= 'd0;
            r_ctrl_sram_ptr <= 'd0;
        end else begin  
            if (I_MREADY && O_MVALID) begin
                r_ctrl_ptr <= nxt_r_ctrl_ptr;
            end
            if(|w_regfifo_svalid && w_regfifo_sready) begin
                r_ctrl_sram_ptr <= nxt_r_ctrl_sram_ptr;
            end
        end
    end
 //---------read & write-----------------------------------------------------
    always_comb begin
        regfifo_tmp_cnt = 'd0;
        bypass_sramfifo = 'd0;
        for(int ich_cnt = 0; ich_cnt < ICH_CNT; ich_cnt = ich_cnt + 1) begin
            if(I_SVALID[ich_cnt]) begin    
                regfifo_tmp_cnt = regfifo_tmp_cnt + 1;
                bypass_sramfifo[ich_cnt] = w_sramfifo_empty & (w_regfifo_empty_cnt >= regfifo_tmp_cnt) & (~r_sram_dout_d1_valid & r_cen_a_d1);
            end
            cen_b_tmp[ich_cnt] = ~(I_SVALID[ich_cnt] & ~w_sramfifo_full & ~bypass_sramfifo[ich_cnt]);
        end
    end

    assign cen_a_tmp = ~(~w_sramfifo_empty & (w_regfifo_sready | (~r_sram_dout_d1_valid & r_cen_a_d1)));

    generate
        for(sram_cnt = 0; sram_cnt < REQ_CNT; sram_cnt = sram_cnt + 1) begin
            assign cen_b[sram_cnt] = ~(nxt_wr_sram_idx_valid[sram_cnt]);
            assign cen_a[sram_cnt] = ~(nxt_rd_sram_idx_valid[sram_cnt]);
            assign addr_b[sram_cnt] = w_data_ptr[sram_cnt];
            assign addr_a[sram_cnt] = r_data_ptr[sram_cnt];
        end
    endgenerate

//---------read output-------------------------------------------------------
    assign w_sram_dout_valid    = ~r_cen_a_d1;
    assign w_sram_dout          = I_FIFO_SRAM_RD_DATA;
    
    assign w_sramfifo_mvalid    = r_sram_dout_d1_valid | w_sram_dout_valid;

    logic [REQ_CNT_WD-1:0] sram_idx;
    always_comb begin
        w_regfifo_input_data = 'd0;
        for(int chunk_cnt = 0; chunk_cnt < AXI_CON; chunk_cnt = chunk_cnt + 1) begin
            sram_idx = (rd_sram_idx_d1 + chunk_cnt >= REQ_CNT) ? (rd_sram_idx_d1 + chunk_cnt - REQ_CNT) : (rd_sram_idx_d1 + chunk_cnt);
            if(w_sram_dout_valid) begin           
                if(chunk_cnt < (1 << o_mdlen)) begin
                    w_regfifo_input_data[chunk_cnt] = w_sram_dout[sram_idx];
                end
            end else if(r_sram_dout_d1_valid) begin
                if(chunk_cnt < (1 << o_mdlen)) begin
                    w_regfifo_input_data[chunk_cnt] = r_sram_dout_d1[sram_idx];
                end
            end
        end
    end

//---------------------------------------------------------------------
    always @(posedge I_CLK or negedge I_RESETN) begin
        if (!I_RESETN) begin               
            r_cen_a_d1 <= 1'b1;
            r_sram_dout_d1 <= 'd0;
            r_sram_dout_d1_valid <= 1'b0;            

        end else begin
            r_cen_a_d1 <= cen_a_tmp;

            if(w_sram_dout_valid & ~w_regfifo_sready) begin
                r_sram_dout_d1_valid <= 1'b1;
                r_sram_dout_d1 <= w_sram_dout; 
            end else if (w_regfifo_sready) begin
                r_sram_dout_d1_valid <= 1'b0;
            end
        end
    end

    assign O_FIFO_SRAM_RD_ENB   = cen_a;
    assign O_FIFO_SRAM_RD_ADDR  = addr_a;
    assign O_FIFO_SRAM_WR_ENB   = cen_b;
    assign O_FIFO_SRAM_WR_ADDR  = addr_b;
    assign O_FIFO_SRAM_WR_DATA  = sram_wr_data;

//------regfifo------------------------------------------------------
    genvar u;
    generate
        for(u = 0; u < ICH_CNT; u = u + 1) begin : GEN_REGFIFO_S
            localparam int CH_MOD4 = u % 4;

            assign w_regfifo_svalid[u]  = (bypass_sramfifo[u]) ? I_SVALID[u] : (u == 0) ? w_sramfifo_mvalid : 1'b0;
            assign w_regfifo_sdata[u]   = (bypass_sramfifo[u]) ? (CH_MOD4 == 0) ? {I_EXT_SDATA[u], I_SDATA[u]} : (CH_MOD4 == 1) ? {I_EXT_SDATA[u], I_SDATA[u][511:0], I_SDATA[u][511:0]} : {I_EXT_SDATA[u], I_SDATA[u][255:0], I_SDATA[u][255:0], I_SDATA[u][255:0], I_SDATA[u][255:0]} :
                                                                 (u == 0) ? (o_mdlen == 2) ? {w_regfifo_input_data[3][DATA_FIFO_WD +: EXT_FIFO_WD], w_regfifo_input_data[3][DATA_FIFO_WD-1:0], w_regfifo_input_data[2][DATA_FIFO_WD-1:0], w_regfifo_input_data[1][DATA_FIFO_WD-1:0], w_regfifo_input_data[0][DATA_FIFO_WD-1:0]} :
                                                                            (o_mdlen == 1) ? {w_regfifo_input_data[1][DATA_FIFO_WD +: EXT_FIFO_WD], w_regfifo_input_data[1][DATA_FIFO_WD-1:0], w_regfifo_input_data[0][DATA_FIFO_WD-1:0], w_regfifo_input_data[1][DATA_FIFO_WD-1:0], w_regfifo_input_data[0][DATA_FIFO_WD-1:0]} :
                                                                                             {w_regfifo_input_data[0][DATA_FIFO_WD +: EXT_FIFO_WD], w_regfifo_input_data[0][DATA_FIFO_WD-1:0], w_regfifo_input_data[0][DATA_FIFO_WD-1:0], w_regfifo_input_data[0][DATA_FIFO_WD-1:0], w_regfifo_input_data[0][DATA_FIFO_WD-1:0]} : {(AXI_PEER_DIE_MAX_DATA_WD + EXT_FIFO_WD){1'b0}};
        end
    endgenerate
    
    assign w_regfifo_mready     = I_MREADY;
    assign O_MDATA              = w_regfifo_mdata[AXI_PEER_DIE_MAX_DATA_WD-1:0];
    assign O_EXT_MDATA          = w_regfifo_mdata[AXI_PEER_DIE_MAX_DATA_WD +: EXT_FIFO_WD];
    assign O_MVALID             = w_regfifo_mvalid;

    AOU_SYNC_FIFO_NS1M_SREADY#(
        .FIFO_WIDTH         (AXI_PEER_DIE_MAX_DATA_WD + EXT_FIFO_WD),
        .FIFO_DEPTH         (REGFIFO_DEPTH      ),
        .ICH_CNT            (ICH_CNT            )
    )u_aou_regfifo
    (
        .I_CLK              (I_CLK              ),
        .I_RESETN           (I_RESETN           ),
       
        .I_SVALID           (w_regfifo_svalid   ),
        .I_SDATA            (w_regfifo_sdata    ),
        .O_SREADY           (w_regfifo_sready   ),
       
        .I_MREADY           (w_regfifo_mready   ),
        .O_MDATA            (w_regfifo_mdata    ),
        .O_MVALID           (w_regfifo_mvalid   ),
    
        .O_S_EMPTY_CNT      (w_regfifo_empty_cnt),
        .O_M_DATA_CNT       (                   ) 
    );

endmodule


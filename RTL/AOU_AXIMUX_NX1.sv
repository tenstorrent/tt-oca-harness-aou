/*
BOS SoC Team/ Kwanho Kim
Now only Support 4X1 or 3X1 or 2X1
*/

`timescale 1ns/1ps

module AOU_AXIMUX_NX1 #(
    parameter   AXI_SLV_NUM  = 2,
    localparam  LOG_MN = $clog2(AXI_SLV_NUM),  
    parameter   AXI_DATA_WD   = 512,
    parameter   AXI_ADDR_WD   = 64,
    parameter   AXI_ID_WD     = 2,
    parameter   AXI_QOS_WD    = 4,
    parameter   AXI_STRB_WD   = AXI_DATA_WD / 8,
    parameter   AXI_LEN_WD    = 8,
    parameter   AXI_PEER_DIE_MAX_DATA_WD    = 1024

)
(
    input                                              I_CLK,
    input                                              I_RESETN,

    // Arbitration configuration must remain static while traffic is active.
    input       [1:0]                                  I_ARB_MODE,
    input       [AXI_SLV_NUM-1:0][1:0]                 I_AW_PRIORITY,
    input       [AXI_SLV_NUM-1:0][1:0]                 I_AR_PRIORITY,

    input       [AXI_SLV_NUM-1:0][AXI_ID_WD-1: 0]      I_S_AWID,
    input       [AXI_SLV_NUM-1:0][AXI_ADDR_WD-1: 0]    I_S_AWADDR,
    input       [AXI_SLV_NUM-1:0][AXI_LEN_WD-1: 0]     I_S_AWLEN,
    input       [AXI_SLV_NUM-1:0][2: 0]                I_S_AWSIZE,
    input       [AXI_SLV_NUM-1:0][1: 0]                I_S_AWBURST,
    input       [AXI_SLV_NUM-1:0]                      I_S_AWLOCK,
    input       [AXI_SLV_NUM-1:0][3: 0]                I_S_AWCACHE,
    input       [AXI_SLV_NUM-1:0][2: 0]                I_S_AWPROT,
    input       [AXI_SLV_NUM-1:0][AXI_QOS_WD-1: 0]     I_S_AWQOS,
    input       [AXI_SLV_NUM-1:0]                      I_S_AWVALID,
    output wire [AXI_SLV_NUM-1:0]                      O_S_AWREADY,

    input       [AXI_SLV_NUM-1:0][AXI_DATA_WD-1: 0]    I_S_WDATA,
    input       [AXI_SLV_NUM-1:0][AXI_STRB_WD-1: 0]    I_S_WSTRB,
    input       [AXI_SLV_NUM-1:0]                      I_S_WLAST,
    input       [AXI_SLV_NUM-1:0][1:0]                 I_S_WDLEN,
    input       [AXI_SLV_NUM-1:0]                      I_S_WVALID,
    output      [AXI_SLV_NUM-1:0]                      O_S_WREADY,

    output wire [AXI_SLV_NUM-1:0][AXI_ID_WD-1: 0]      O_S_BID,
    output wire [AXI_SLV_NUM-1:0][1: 0]                O_S_BRESP,
    output wire [AXI_SLV_NUM-1:0]                      O_S_BVALID,
    input       [AXI_SLV_NUM-1:0]                      I_S_BREADY,

    input       [AXI_SLV_NUM-1:0][AXI_ID_WD-1: 0]      I_S_ARID,
    input       [AXI_SLV_NUM-1:0][AXI_ADDR_WD-1: 0]    I_S_ARADDR,
    input       [AXI_SLV_NUM-1:0][2: 0]                I_S_ARSIZE,
    input       [AXI_SLV_NUM-1:0][1: 0]                I_S_ARBURST,
    input       [AXI_SLV_NUM-1:0][3: 0]                I_S_ARCACHE,
    input       [AXI_SLV_NUM-1:0][2: 0]                I_S_ARPROT,
    input       [AXI_SLV_NUM-1:0][AXI_LEN_WD-1: 0]     I_S_ARLEN,
    input       [AXI_SLV_NUM-1:0]                      I_S_ARLOCK,
    input       [AXI_SLV_NUM-1:0][AXI_QOS_WD-1: 0]     I_S_ARQOS,
    input       [AXI_SLV_NUM-1:0]                      I_S_ARVALID,
    output wire [AXI_SLV_NUM-1:0]                      O_S_ARREADY,

    output wire [AXI_SLV_NUM-1:0][AXI_ID_WD-1: 0]      O_S_RID,
    output wire [AXI_SLV_NUM-1:0][AXI_PEER_DIE_MAX_DATA_WD-1: 0]    O_S_RDATA,
    output wire [AXI_SLV_NUM-1:0][1: 0]                O_S_RRESP,
    output wire [AXI_SLV_NUM-1:0]                      O_S_RLAST,
    output wire [AXI_SLV_NUM-1:0]                      O_S_RVALID,
    input       [AXI_SLV_NUM-1:0]                      I_S_RREADY,
 
    output wire [AXI_ID_WD-1+LOG_MN:0]                 O_M_AWID,
    output wire [AXI_ADDR_WD-1: 0]                     O_M_AWADDR,
    output wire [AXI_LEN_WD-1: 0]                      O_M_AWLEN,
    output wire [2: 0]                                 O_M_AWSIZE,
    output wire [1: 0]                                 O_M_AWBURST,
    output wire                                        O_M_AWLOCK,
    output wire [3: 0]                                 O_M_AWCACHE,
    output wire [2: 0]                                 O_M_AWPROT,
    output wire [AXI_QOS_WD-1: 0]                      O_M_AWQOS,
    output wire                                        O_M_AWVALID,
    input                                              I_M_AWREADY,      

    output wire [AXI_DATA_WD-1: 0]                     O_M_WDATA,
    output wire [AXI_STRB_WD-1: 0]                     O_M_WSTRB,
    output wire                                        O_M_WLAST,
    output wire [1:0]                                  O_M_WDLEN,
    output wire                                        O_M_WVALID,
    input                                              I_M_WREADY,

    input       [AXI_ID_WD-1+LOG_MN: 0]                I_M_BID,
    input       [1: 0]                                 I_M_BRESP,
    input                                              I_M_BVALID,
    output wire                                        O_M_BREADY,

    output wire [AXI_ID_WD-1+LOG_MN: 0]                O_M_ARID,
    output wire [AXI_ADDR_WD-1: 0]                     O_M_ARADDR,
    output wire [2: 0]                                 O_M_ARSIZE,
    output wire [1: 0]                                 O_M_ARBURST,
    output wire [3: 0]                                 O_M_ARCACHE,
    output wire [2: 0]                                 O_M_ARPROT,
    output wire [AXI_LEN_WD-1: 0]                      O_M_ARLEN,
    output wire                                        O_M_ARLOCK,
    output wire [AXI_QOS_WD-1: 0]                      O_M_ARQOS,
    output wire                                        O_M_ARVALID,
    input                                              I_M_ARREADY,

    input       [AXI_ID_WD-1+LOG_MN: 0]                I_M_RID,
    input       [AXI_PEER_DIE_MAX_DATA_WD-1: 0]        I_M_RDATA,
    input       [1: 0]                                 I_M_RRESP,
    input                                              I_M_RLAST,
    input                                              I_M_RVALID,
    output wire                                        O_M_RREADY
);

wire [AXI_SLV_NUM-1: 0]                         w_ar_arb_grt    ;
reg  [LOG_MN-1:0]                               w_ar_arb_grt_bin;
wire [AXI_SLV_NUM-1: 0]                         w_aw_arb_grt    ;
reg  [AXI_SLV_NUM-1: 0]                         r_aw_arb_grt    ;

reg                                             r_s_wbusy_tt    ; 

wire [AXI_SLV_NUM-1: 0]                         w_aw_arb_grt_mux;
reg  [LOG_MN-1:0]                               w_aw_arb_grt_bin_mux;

wire                                            w_no_awvalid    ;

assign w_aw_arb_grt_mux = r_s_wbusy_tt ? r_aw_arb_grt : w_aw_arb_grt; 

generate
if (AXI_SLV_NUM == 2) begin
    AOU_ASYMMETRIC_RP_QOS_ARBITER #(
        .RP_CNT (AXI_SLV_NUM)
    ) AR_ARBITER (
        .I_ARB_MODE         ( I_ARB_MODE                     ),
        .I_QOS              ( I_AR_PRIORITY                  ),
        .I_CLK              ( I_CLK                          ),
        .I_RESETN           ( I_RESETN                       ),
        
        .I_REQ              ( I_S_ARVALID                    ),
        .I_ARB_EN           ( O_M_ARVALID & I_M_ARREADY      ),
        
        .O_GRANTED_AGENT    ( w_ar_arb_grt                   )
    );
    
    
    always_comb begin
        case (w_ar_arb_grt) 
            2'b01   : w_ar_arb_grt_bin = 1'b0;
            2'b10   : w_ar_arb_grt_bin = 1'b1;
            default : w_ar_arb_grt_bin = 1'b0;
        endcase
    end

    AOU_ASYMMETRIC_RP_QOS_ARBITER #(
        .RP_CNT (AXI_SLV_NUM)
    ) AW_ARBITER (
        .I_ARB_MODE         ( I_ARB_MODE                     ),
        .I_QOS              ( I_AW_PRIORITY                  ),
        .I_CLK              ( I_CLK                          ),
        .I_RESETN           ( I_RESETN                       ),
        
        .I_REQ              ( I_S_AWVALID                    ),
        .I_ARB_EN           ( O_M_WVALID & I_M_WREADY & O_M_WLAST ),
        
        .O_GRANTED_AGENT    ( w_aw_arb_grt                   )
    );
    
    always_comb begin
        case (w_aw_arb_grt_mux) 
            2'b01 : w_aw_arb_grt_bin_mux   = 1'b0;
            2'b10 : w_aw_arb_grt_bin_mux   = 1'b1;
            default : w_aw_arb_grt_bin_mux = 1'b0;
        endcase
    end

end else if (AXI_SLV_NUM == 3) begin : g_arb3
    AOU_ASYMMETRIC_RP_QOS_ARBITER #(
        .RP_CNT (AXI_SLV_NUM)
    ) AR_ARBITER (
        .I_ARB_MODE      (I_ARB_MODE),
        .I_QOS           (I_AR_PRIORITY),
        .I_CLK           (I_CLK),
        .I_RESETN        (I_RESETN),
        .I_REQ           (I_S_ARVALID),
        .I_ARB_EN        (O_M_ARVALID & I_M_ARREADY),
        .O_GRANTED_AGENT (w_ar_arb_grt)
    );

    always_comb begin
        case (w_ar_arb_grt)
            3'b001: w_ar_arb_grt_bin = 2'b00;
            3'b010: w_ar_arb_grt_bin = 2'b01;
            3'b100: w_ar_arb_grt_bin = 2'b10;
            default: w_ar_arb_grt_bin = 2'b00;
        endcase
    end

    AOU_ASYMMETRIC_RP_QOS_ARBITER #(
        .RP_CNT (AXI_SLV_NUM)
    ) AW_ARBITER (
        .I_ARB_MODE      (I_ARB_MODE),
        .I_QOS           (I_AW_PRIORITY),
        .I_CLK           (I_CLK),
        .I_RESETN        (I_RESETN),
        .I_REQ           (I_S_AWVALID),
        .I_ARB_EN        (O_M_WVALID & I_M_WREADY & O_M_WLAST),
        .O_GRANTED_AGENT (w_aw_arb_grt)
    );

    always_comb begin
        case (w_aw_arb_grt_mux)
            3'b001: w_aw_arb_grt_bin_mux = 2'b00;
            3'b010: w_aw_arb_grt_bin_mux = 2'b01;
            3'b100: w_aw_arb_grt_bin_mux = 2'b10;
            default: w_aw_arb_grt_bin_mux = 2'b00;
        endcase
    end

end else if (AXI_SLV_NUM == 4) begin

    AOU_ASYMMETRIC_RP_QOS_ARBITER #(
        .RP_CNT (AXI_SLV_NUM)
    ) AR_ARBITER (
        .I_ARB_MODE         ( I_ARB_MODE                     ),
        .I_QOS              ( I_AR_PRIORITY                  ),
        .I_CLK              ( I_CLK                          ),
        .I_RESETN           ( I_RESETN                       ),
        
        .I_REQ              ( I_S_ARVALID                    ),
        .I_ARB_EN           ( O_M_ARVALID & I_M_ARREADY      ),
        
        .O_GRANTED_AGENT    ( w_ar_arb_grt                   )
    );
    
    always_comb begin
        case (w_ar_arb_grt) 
            4'b0001 : w_ar_arb_grt_bin = 2'b00;
            4'b0010 : w_ar_arb_grt_bin = 2'b01;
            4'b0100 : w_ar_arb_grt_bin = 2'b10;
            4'b1000 : w_ar_arb_grt_bin = 2'b11;
            default : w_ar_arb_grt_bin = 2'b00;
        endcase
    end

    AOU_ASYMMETRIC_RP_QOS_ARBITER #(
        .RP_CNT (AXI_SLV_NUM)
    ) AW_ARBITER (
        .I_ARB_MODE         ( I_ARB_MODE                     ),
        .I_QOS              ( I_AW_PRIORITY                  ),
        .I_CLK              ( I_CLK                          ),
        .I_RESETN           ( I_RESETN                       ),
        
        .I_REQ              ( I_S_AWVALID                    ),
        .I_ARB_EN           ( O_M_WVALID & I_M_WREADY & O_M_WLAST ),
        
        .O_GRANTED_AGENT    ( w_aw_arb_grt                   )
    );
    
    always_comb begin
        case (w_aw_arb_grt_mux) 
            4'b0001 : w_aw_arb_grt_bin_mux = 2'b00;
            4'b0010 : w_aw_arb_grt_bin_mux = 2'b01;
            4'b0100 : w_aw_arb_grt_bin_mux = 2'b10;
            4'b1000 : w_aw_arb_grt_bin_mux = 2'b11;
            default : w_aw_arb_grt_bin_mux = 2'b00;
        endcase
    end

end
endgenerate

//==============================================================
//                          AR, R
//==============================================================

assign O_M_ARID     = {I_S_ARID[w_ar_arb_grt_bin], w_ar_arb_grt_bin};
assign O_M_ARVALID  = I_S_ARVALID[w_ar_arb_grt_bin] ;
assign O_M_ARADDR   = I_S_ARADDR[w_ar_arb_grt_bin]  ;
assign O_M_ARSIZE   = I_S_ARSIZE[w_ar_arb_grt_bin]  ;
assign O_M_ARBURST  = I_S_ARBURST[w_ar_arb_grt_bin] ;
assign O_M_ARCACHE  = I_S_ARCACHE[w_ar_arb_grt_bin] ;
assign O_M_ARPROT   = I_S_ARPROT[w_ar_arb_grt_bin]  ;
assign O_M_ARLEN    = I_S_ARLEN[w_ar_arb_grt_bin]   ;
assign O_M_ARLOCK   = I_S_ARLOCK[w_ar_arb_grt_bin]  ;
assign O_M_ARQOS    = I_S_ARQOS[w_ar_arb_grt_bin]   ;

assign O_M_RREADY   = ~I_M_RVALID | I_S_RREADY[I_M_RID[0+:LOG_MN]];

genvar p;
generate
    for(p = 0; p < AXI_SLV_NUM; p = p + 1) begin
        assign O_S_ARREADY[p]   = w_ar_arb_grt[p] & I_M_ARREADY;

        assign O_S_RID[p]       = I_M_RID[AXI_ID_WD-1+LOG_MN:LOG_MN];
        assign O_S_RDATA[p]     = I_M_RDATA;
        assign O_S_RRESP[p]     = I_M_RRESP;
        assign O_S_RLAST[p]     = I_M_RLAST;
        assign O_S_RVALID[p]    = (I_M_RID[0+:LOG_MN] == p) & I_M_RVALID;
    end
endgenerate

//==============================================================
//                          AW, W, B
//==============================================================

always_ff @(posedge I_CLK or negedge I_RESETN) begin
    if (~I_RESETN) begin
        r_s_wbusy_tt <= 'd0;
        r_aw_arb_grt <= 'd0;   
    end else begin
        if ((I_S_AWVALID[w_aw_arb_grt_bin_mux] & O_S_AWREADY[w_aw_arb_grt_bin_mux])) begin
            if (I_S_WVALID[w_aw_arb_grt_bin_mux] & O_S_WREADY[w_aw_arb_grt_bin_mux] & I_S_WLAST[w_aw_arb_grt_bin_mux])
                r_s_wbusy_tt <= 1'b0;
            else begin
                r_s_wbusy_tt <= 1'b1;
                r_aw_arb_grt <= w_aw_arb_grt;
            end

        end else begin
            if (r_s_wbusy_tt & I_S_WVALID[w_aw_arb_grt_bin_mux] & O_S_WREADY[w_aw_arb_grt_bin_mux] & I_S_WLAST[w_aw_arb_grt_bin_mux])
                r_s_wbusy_tt <=1'b0;
        end
    end
end

assign O_M_AWID        = {I_S_AWID[w_aw_arb_grt_bin_mux], w_aw_arb_grt_bin_mux};
assign O_M_AWADDR      = I_S_AWADDR[w_aw_arb_grt_bin_mux]  ;
assign O_M_AWLEN       = I_S_AWLEN[w_aw_arb_grt_bin_mux]   ;
assign O_M_AWSIZE      = I_S_AWSIZE[w_aw_arb_grt_bin_mux]  ;
assign O_M_AWBURST     = I_S_AWBURST[w_aw_arb_grt_bin_mux] ;
assign O_M_AWLOCK      = I_S_AWLOCK[w_aw_arb_grt_bin_mux]  ;
assign O_M_AWCACHE     = I_S_AWCACHE[w_aw_arb_grt_bin_mux] ;
assign O_M_AWPROT      = I_S_AWPROT[w_aw_arb_grt_bin_mux]  ;
assign O_M_AWQOS       = I_S_AWQOS[w_aw_arb_grt_bin_mux]   ;

assign O_M_WDATA       = I_S_WDATA[w_aw_arb_grt_bin_mux] ;
assign O_M_WSTRB       = I_S_WSTRB[w_aw_arb_grt_bin_mux] ;
assign O_M_WLAST       = I_S_WLAST[w_aw_arb_grt_bin_mux] ;
assign O_M_WDLEN       = I_S_WDLEN[w_aw_arb_grt_bin_mux];

assign O_M_AWVALID     = ~r_s_wbusy_tt & I_S_AWVALID[w_aw_arb_grt_bin_mux];

assign O_M_WVALID      = ((~r_s_wbusy_tt & I_S_AWVALID[w_aw_arb_grt_bin_mux] & O_S_AWREADY[w_aw_arb_grt_bin_mux]) | r_s_wbusy_tt) & I_S_WVALID[w_aw_arb_grt_bin_mux];

assign O_M_BREADY      = ~I_M_BVALID | I_S_BREADY[I_M_BID[0+:LOG_MN]];

assign  w_no_awvalid    = ~(|I_S_AWVALID);

generate
    for(p = 0; p < AXI_SLV_NUM; p = p + 1) begin
        assign O_S_AWREADY[p] = ~r_s_wbusy_tt & (((w_aw_arb_grt_bin_mux == p) & I_M_AWREADY) | w_no_awvalid) ;
        assign O_S_WREADY[p]  = ((~r_s_wbusy_tt & ((w_aw_arb_grt_bin_mux == p) & I_S_AWVALID[w_aw_arb_grt_bin_mux] & O_S_AWREADY[w_aw_arb_grt_bin_mux]) ) |
                                (r_s_wbusy_tt & ((w_aw_arb_grt_bin_mux == p) ))) & I_M_WREADY;

        assign O_S_BID[p]     = I_M_BID[AXI_ID_WD-1+LOG_MN:LOG_MN];
        assign O_S_BRESP[p]   = I_M_BRESP;
        assign O_S_BVALID[p]  = (I_M_BID[0+:LOG_MN] == p) & I_M_BVALID;
    end
endgenerate

//==============================================================

endmodule


`timescale 1ns/1ps

module AOU_ID_REMAPPER #(
    parameter   WID_WD              = 11,
    parameter   NID_WD              = 10,
    localparam  UNIQ_NID_NUM        = 2**NID_WD,

    parameter   MO_NUM              = 256,
    localparam  MO_CNT_WD           = $clog2(MO_NUM + 1)
)
(
    input                           I_CLK,
    input                           I_RESETN,

    // Downstream: AW or AR.
    input  [WID_WD-1:0]             I_AR_WID,
    input                           I_AR_VALID,
    input                           I_AR_READY,
    output                          O_AR_MAP_READY,
    output [NID_WD-1:0]             O_AR_NID,

    // Upstream: B or R.
    input  [NID_WD-1:0]             I_R_NID,
    input                           I_R_VALID,
    input                           I_R_READY,
    input                           I_R_LAST,
    output [WID_WD-1:0]             O_R_WID
);

localparam MAP_TABLE_ENTRY_NUM = (UNIQ_NID_NUM < MO_NUM) ? UNIQ_NID_NUM : MO_NUM;
localparam MAP_TABLE_IDX_WD = (MAP_TABLE_ENTRY_NUM <= 1) ? 1 : $clog2(MAP_TABLE_ENTRY_NUM);

typedef struct packed {
    logic [WID_WD-1:0] wid;
    logic vld;
    logic [MO_CNT_WD-1:0] cnt;
} st_wid2nid;

st_wid2nid [MAP_TABLE_ENTRY_NUM-1:0] wid2nid;

//==================================
// Parallel entry lookup.
//==================================

logic [MAP_TABLE_ENTRY_NUM-1:0] w_hit_vec;
logic [MAP_TABLE_ENTRY_NUM-1:0] w_hit_full_vec;
logic [MAP_TABLE_ENTRY_NUM-1:0] w_free_vec;
logic [MAP_TABLE_ENTRY_NUM-1:0] w_alloc_vec;
logic [MAP_TABLE_ENTRY_NUM-1:0] w_selected_vec;

logic w_hit;
logic w_hit_cnt_full;
logic w_free_way_find;
logic w_alloc_found;

logic [MAP_TABLE_IDX_WD-1:0] w_hit_nid;
logic [MAP_TABLE_IDX_WD-1:0] w_alloc_nid;

always_comb begin
    for (int i = 0; i < MAP_TABLE_ENTRY_NUM; i++) begin
        w_hit_vec[i] = wid2nid[i].vld && (wid2nid[i].wid == I_AR_WID);
        w_hit_full_vec[i] = w_hit_vec[i] && (wid2nid[i].cnt == MO_CNT_WD'(MO_NUM));
        w_free_vec[i] = !wid2nid[i].vld;
    end
end

assign w_hit = |w_hit_vec;
assign w_hit_cnt_full = |w_hit_full_vec;
assign w_free_way_find = |w_free_vec;

//==================================
// Hit index: one-hot-to-binary encoding.
// At most one valid entry may match a WID.
//==================================

always_comb begin
    w_hit_nid = '0;

    for (int i = 0; i < MAP_TABLE_ENTRY_NUM; i++) begin
        w_hit_nid = w_hit_nid | ({MAP_TABLE_IDX_WD{w_hit_vec[i]}} & MAP_TABLE_IDX_WD'(i));
    end
end

//==================================
// Allocation: select the lowest free index.
// Search independently of the hit result.
//==================================

always_comb begin
    w_alloc_nid = '0;
    w_alloc_vec = '0;
    w_alloc_found = 1'b0;

    for (int i = 0; i < MAP_TABLE_ENTRY_NUM; i++) begin
        if (!w_alloc_found && w_free_vec[i]) begin
            w_alloc_nid = MAP_TABLE_IDX_WD'(i);
            w_alloc_vec[i] = 1'b1;
            w_alloc_found = 1'b1;
        end
    end
end

assign w_selected_vec = w_hit ? w_hit_vec : w_alloc_vec;

//==================================
// Reservation tracking.
//
// Reserve on the first valid/map-ready cycle,
// even when downstream READY is low.
// Prevent repeated allocation/count increments
// until the pending request handshakes.
//==================================

logic r_alloc_blk;
logic r_cnt_inc_blk;

always_ff @(posedge I_CLK or negedge I_RESETN) begin
    if (!I_RESETN) begin
        r_alloc_blk <= 1'b0;
    end else if (I_AR_VALID && O_AR_MAP_READY && !I_AR_READY) begin
        r_alloc_blk <= 1'b1;
    end else if (I_AR_VALID && O_AR_MAP_READY && I_AR_READY) begin
        r_alloc_blk <= 1'b0;
    end
end

always_ff @(posedge I_CLK or negedge I_RESETN) begin
    if (!I_RESETN) begin
        r_cnt_inc_blk <= 1'b0;
    end else if (I_AR_VALID && O_AR_MAP_READY && !I_AR_READY) begin
        r_cnt_inc_blk <= 1'b1;
    end else if (I_AR_VALID && O_AR_MAP_READY && I_AR_READY) begin
        r_cnt_inc_blk <= 1'b0;
    end
end

wire w_cnt_inc_cond = I_AR_VALID && O_AR_MAP_READY && !r_cnt_inc_blk;
wire w_cnt_dec_cond = I_R_VALID && I_R_READY && I_R_LAST;

//==================================
// Store WID on a new allocation.
//==================================

always_ff @(posedge I_CLK or negedge I_RESETN) begin
    if (!I_RESETN) begin
        for (int i = 0; i < MAP_TABLE_ENTRY_NUM; i++) begin
            wid2nid[i].wid <= '0;
        end
    end else begin
        for (int i = 0; i < MAP_TABLE_ENTRY_NUM; i++) begin
            if (I_AR_VALID && O_AR_MAP_READY && !r_alloc_blk && !w_hit && w_alloc_vec[i]) begin
                wid2nid[i].wid <= I_AR_WID;
            end
        end
    end
end

//==================================
// Per-entry count and valid.
//
// cnt includes a reserved request that has not
// yet handshaken with downstream.
//==================================

generate
    for (genvar gi = 0; gi < MAP_TABLE_ENTRY_NUM; gi++) begin : g_entry_state
        wire w_entry_inc;
        wire w_entry_dec;

        assign w_entry_inc = w_cnt_inc_cond && w_selected_vec[gi];
        assign w_entry_dec = w_cnt_dec_cond && (I_R_NID == NID_WD'(gi));

        always_ff @(posedge I_CLK or negedge I_RESETN) begin
            if (!I_RESETN) begin
                wid2nid[gi].cnt <= '0;
                wid2nid[gi].vld <= 1'b0;
            end else begin
                case ({w_entry_inc, w_entry_dec})
                    2'b10: begin
                        wid2nid[gi].cnt <= wid2nid[gi].cnt + 1'b1;
                        wid2nid[gi].vld <= 1'b1;
                    end

                    2'b01: begin
                        wid2nid[gi].cnt <= wid2nid[gi].cnt - 1'b1;

                        if (wid2nid[gi].cnt == MO_CNT_WD'(1)) begin
                            wid2nid[gi].vld <= 1'b0;
                        end
                    end

                    default: begin
                        // Hold for no update or simultaneous inc/dec.
                    end
                endcase
            end
        end
    end
endgenerate

//==================================
// Outputs.
//
// A reserved request remains map-ready even if
// its reservation brought the count to MO_NUM.
//==================================

assign O_AR_MAP_READY = r_cnt_inc_blk || (w_hit ? !w_hit_cnt_full : w_free_way_find);
assign O_AR_NID = NID_WD'(w_hit ? w_hit_nid : w_alloc_nid);
assign O_R_WID = wid2nid[MAP_TABLE_IDX_WD'(I_R_NID)].wid;

//==================================
// Assertions.
//==================================

`ifdef ASSERTION_ON
// synopsys translate_off

localparam TOTAL_CNT_WD = MO_CNT_WD + $clog2(MAP_TABLE_ENTRY_NUM);

logic [TOTAL_CNT_WD-1:0] w_total_mo_cnt;

always_comb begin
    w_total_mo_cnt = '0;

    for (int i = 0; i < MAP_TABLE_ENTRY_NUM; i++) begin
        w_total_mo_cnt = w_total_mo_cnt + TOTAL_CNT_WD'(wid2nid[i].cnt);
    end
end

aou_id_remapper_total_mo_assertion:
    assert property (
        @(posedge I_CLK) disable iff (!I_RESETN)
        w_total_mo_cnt <= TOTAL_CNT_WD'(MO_NUM)
    )
    else $error("[%0t] %m: Total outstanding count exceeds MO_NUM. total=%0d, MO_NUM=%0d", $time, $sampled(w_total_mo_cnt), MO_NUM);

aou_id_remapper_hit_onehot_assertion:
    assert property (
        @(posedge I_CLK) disable iff (!I_RESETN)
        $onehot0(w_hit_vec)
    )
    else $error("[%0t] %m: Multiple entries match the same WID.", $time);

aou_id_remapper_response_entry_assertion:
    assert property (
        @(posedge I_CLK) disable iff (!I_RESETN)
        w_cnt_dec_cond |-> (({1'b0, I_R_NID} < (NID_WD+1)'(MAP_TABLE_ENTRY_NUM)) && wid2nid[MAP_TABLE_IDX_WD'(I_R_NID)].vld)
    )
    else $error("[%0t] %m: Response references an invalid mapping entry.", $time);

generate
    for (genvar ai = 0; ai < MAP_TABLE_ENTRY_NUM; ai++) begin : g_entry_assertion
        aou_id_remapper_valid_count_assertion:
            assert property (
                @(posedge I_CLK) disable iff (!I_RESETN)
                wid2nid[ai].vld == (wid2nid[ai].cnt != '0)
            )
            else $error("[%0t] %m: Entry valid/count mismatch.", $time);
    end
endgenerate

// synopsys translate_on
`endif

endmodule

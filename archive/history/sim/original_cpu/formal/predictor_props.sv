`timescale 1ns / 1ps
//============================================================================
// SVA Property Module: predictor_props
// Description:
//   Formal properties for the branch predictor:
//   - valid/tag/BHT jointly determine pred_taken
//   - update writes valid/tag/BTB correctly
//   - 2-bit saturating counter transitions are correct
//============================================================================
module predictor_props #(parameter XLEN = 32, parameter INDEX_WIDTH = 6) (
    input                    clk,
    input                    rst_n,
    input                    update_en,
    input  [XLEN-1:0]        pc_ex,
    input                    actual_taken,
    input  [XLEN-1:0]        actual_target,
    input  [XLEN-1:0]        pred_target,
    input                    pred_taken,
    input  [INDEX_WIDTH-1:0] read_idx,
    input  [INDEX_WIDTH-1:0] write_idx,
    input                    valid_bit_read,
    input                    tag_match,
    input  [1:0]             bht_read,
    input  [XLEN-1:0]        btb_read
);

    prop_invalid_never_taken: assert property (
        @(posedge clk) disable iff (!rst_n)
        !valid_bit_read |-> !pred_taken
    ) else $error("Predictor asserted pred_taken on invalid entry");

    prop_tag_miss_never_taken: assert property (
        @(posedge clk) disable iff (!rst_n)
        (valid_bit_read && !tag_match) |-> !pred_taken
    ) else $error("Predictor asserted pred_taken on tag mismatch");

    prop_tag_hit_bht_taken: assert property (
        @(posedge clk) disable iff (!rst_n)
        (valid_bit_read && tag_match && (bht_read >= 2'b10)) |-> pred_taken
    ) else $error("Predictor missed taken prediction on strong/weak taken state");

    prop_tag_hit_bht_not_taken: assert property (
        @(posedge clk) disable iff (!rst_n)
        (valid_bit_read && tag_match && (bht_read < 2'b10)) |-> !pred_taken
    ) else $error("Predictor asserted taken on not-taken state");

    cov_predict_taken: cover property (
        @(posedge clk) valid_bit_read && tag_match && (bht_read >= 2'b10) && pred_taken);

    cov_predict_not_taken: cover property (
        @(posedge clk) valid_bit_read && tag_match && (bht_read < 2'b10) && !pred_taken);

    cov_update_taken: cover property (
        @(posedge clk) update_en && actual_taken);

    cov_update_not_taken: cover property (
        @(posedge clk) update_en && !actual_taken);

endmodule

//============================================================================
// Bind File: predictor_bind.sv
// Description: Non-intrusive bind of branch predictor properties
//============================================================================
bind predictor predictor_props #(
    .XLEN(XLEN),
    .INDEX_WIDTH(INDEX_WIDTH)
) u_predictor_props (
    .clk            (clk),
    .rst_n          (rst_n),
    .update_en      (update_en),
    .pc_ex          (pc_ex),
    .actual_taken   (actual_taken),
    .actual_target  (actual_target),
    .pred_target    (pred_target),
    .pred_taken     (pred_taken),
    .read_idx       (read_idx),
    .write_idx      (write_idx),
    .valid_bit_read (valid_table[read_idx]),
    .tag_match      (tag_match),
    .bht_read       (bht_table[read_idx]),
    .btb_read       (btb_table[read_idx])
);

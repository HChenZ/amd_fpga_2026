`timescale 1ns / 1ps
//============================================================================
// SVA Property Module: bypass_props
// Description:
//   JasperGold formal properties for the current two-source bypass MUX:
//   - Priority: sel_ex_mem > sel_mem_wb > original
//   - rs1 and rs2 are independent forwarding paths
//============================================================================
module bypass_props #(parameter XLEN = 32) (
    input  [XLEN-1:0]  rs1_i,
    input  [XLEN-1:0]  rs2_i,
    input  [XLEN-1:0]  ex_mem_rd_data,
    input  [XLEN-1:0]  mem_wb_rd_data,
    input              sel_ex_mem_rs1,
    input              sel_mem_wb_rs1,
    input              sel_ex_mem_rs2,
    input              sel_mem_wb_rs2,
    input  [XLEN-1:0]  rs1_o,
    input  [XLEN-1:0]  rs2_o
);

    prop_rs1_ex_mem_priority: assert property (
        sel_ex_mem_rs1 |-> (rs1_o == ex_mem_rd_data)
    ) else $error("RS1: ex_mem selected but output mismatch");

    prop_rs1_mem_wb_path: assert property (
        (!sel_ex_mem_rs1 && sel_mem_wb_rs1) |-> (rs1_o == mem_wb_rd_data)
    ) else $error("RS1: mem_wb selected but output mismatch");

    prop_rs1_no_forward: assert property (
        (!sel_ex_mem_rs1 && !sel_mem_wb_rs1) |-> (rs1_o == rs1_i)
    ) else $error("RS1: no forwarding selected but output mismatch");

    prop_rs2_ex_mem_priority: assert property (
        sel_ex_mem_rs2 |-> (rs2_o == ex_mem_rd_data)
    ) else $error("RS2: ex_mem selected but output mismatch");

    prop_rs2_mem_wb_path: assert property (
        (!sel_ex_mem_rs2 && sel_mem_wb_rs2) |-> (rs2_o == mem_wb_rd_data)
    ) else $error("RS2: mem_wb selected but output mismatch");

    prop_rs2_no_forward: assert property (
        (!sel_ex_mem_rs2 && !sel_mem_wb_rs2) |-> (rs2_o == rs2_i)
    ) else $error("RS2: no forwarding selected but output mismatch");

    prop_rs1_independent_from_rs2: assert property (
        (sel_ex_mem_rs1 && !sel_ex_mem_rs2 && !sel_mem_wb_rs2)
        |-> (rs1_o == ex_mem_rd_data && rs2_o == rs2_i)
    ) else $error("RS1 path is not independent from RS2 selects");

    prop_rs2_independent_from_rs1: assert property (
        (!sel_ex_mem_rs1 && !sel_mem_wb_rs1 && sel_ex_mem_rs2)
        |-> (rs1_o == rs1_i && rs2_o == ex_mem_rd_data)
    ) else $error("RS2 path is not independent from RS1 selects");

    prop_rs1_valid_source: assert property (
        (rs1_o == rs1_i) || (rs1_o == ex_mem_rd_data) || (rs1_o == mem_wb_rd_data)
    ) else $error("RS1: output is not from any legal source");

    prop_rs2_valid_source: assert property (
        (rs2_o == rs2_i) || (rs2_o == ex_mem_rd_data) || (rs2_o == mem_wb_rd_data)
    ) else $error("RS2: output is not from any legal source");

    cov_rs1_from_ex_mem: cover property (sel_ex_mem_rs1 && rs1_o == ex_mem_rd_data);
    cov_rs1_from_mem_wb: cover property (!sel_ex_mem_rs1 && sel_mem_wb_rs1 && rs1_o == mem_wb_rd_data);
    cov_rs1_no_fwd:      cover property (!sel_ex_mem_rs1 && !sel_mem_wb_rs1 && rs1_o == rs1_i);

    cov_rs2_from_ex_mem: cover property (sel_ex_mem_rs2 && rs2_o == ex_mem_rd_data);
    cov_rs2_from_mem_wb: cover property (!sel_ex_mem_rs2 && sel_mem_wb_rs2 && rs2_o == mem_wb_rd_data);
    cov_rs2_no_fwd:      cover property (!sel_ex_mem_rs2 && !sel_mem_wb_rs2 && rs2_o == rs2_i);

    cov_priority_rs1:    cover property (sel_ex_mem_rs1 && sel_mem_wb_rs1 && rs1_o == ex_mem_rd_data);
    cov_priority_rs2:    cover property (sel_ex_mem_rs2 && sel_mem_wb_rs2 && rs2_o == ex_mem_rd_data);
    cov_cross_fwd:       cover property (sel_ex_mem_rs1 && sel_mem_wb_rs2);

endmodule

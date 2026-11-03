`timescale 1ns / 1ps
//============================================================================
// SVA Property Module: regfile_props
// Description:
//   Formal properties for the architectural register file:
//   - x0 is hardwired to zero
//   - writes to x0 are ignored
//   - same-cycle write-through on both read ports
//   - non-bypassed reads return stored array contents
//   - stored-array reads are consistent with the underlying storage
//============================================================================
module regfile_props #(parameter XLEN = 32) (
    input              clk,
    input              rst_n,
    input  [4:0]       w_reg_addr,
    input  [4:0]       r_reg_addr1,
    input  [4:0]       r_reg_addr2,
    input  [XLEN-1:0]  w_reg_data,
    input              w_reg_en,
    input  [XLEN-1:0]  reg_rs1,
    input  [XLEN-1:0]  reg_rs2,
    input  [XLEN-1:0]  storage_r1,
    input  [XLEN-1:0]  storage_r2
);

    prop_x0_read_port1: assert property (
        @(posedge clk) disable iff (!rst_n)
        (r_reg_addr1 == 5'h0) |-> (reg_rs1 == {XLEN{1'b0}})
    ) else $error("regfile rs1 returned non-zero for x0");

    prop_x0_read_port2: assert property (
        @(posedge clk) disable iff (!rst_n)
        (r_reg_addr2 == 5'h0) |-> (reg_rs2 == {XLEN{1'b0}})
    ) else $error("regfile rs2 returned non-zero for x0");

    prop_write_x0_ignored_port1: assert property (
        @(posedge clk) disable iff (!rst_n)
        (w_reg_en && (w_reg_addr == 5'h0) && (r_reg_addr1 == 5'h0)) |-> (reg_rs1 == {XLEN{1'b0}})
    ) else $error("write to x0 affected rs1 x0 read");

    prop_write_x0_ignored_port2: assert property (
        @(posedge clk) disable iff (!rst_n)
        (w_reg_en && (w_reg_addr == 5'h0) && (r_reg_addr2 == 5'h0)) |-> (reg_rs2 == {XLEN{1'b0}})
    ) else $error("write to x0 affected rs2 x0 read");

    prop_write_through_rs1: assert property (
        @(posedge clk) disable iff (!rst_n)
        (w_reg_en && (w_reg_addr != 5'h0) && (r_reg_addr1 == w_reg_addr)) |->
        (reg_rs1 == w_reg_data)
    ) else $error("rs1 write-through bypass mismatch");

    prop_write_through_rs2: assert property (
        @(posedge clk) disable iff (!rst_n)
        (w_reg_en && (w_reg_addr != 5'h0) && (r_reg_addr2 == w_reg_addr)) |->
        (reg_rs2 == w_reg_data)
    ) else $error("rs2 write-through bypass mismatch");

    prop_storage_read_rs1: assert property (
        @(posedge clk) disable iff (!rst_n)
        ((r_reg_addr1 != 5'h0) && !(w_reg_en && (w_reg_addr == r_reg_addr1))) |->
        (reg_rs1 == storage_r1)
    ) else $error("rs1 read did not match stored register value");

    prop_storage_read_rs2: assert property (
        @(posedge clk) disable iff (!rst_n)
        ((r_reg_addr2 != 5'h0) && !(w_reg_en && (w_reg_addr == r_reg_addr2))) |->
        (reg_rs2 == storage_r2)
    ) else $error("rs2 read did not match stored register value");

    cov_rs1_write_through: cover property (
        @(posedge clk) w_reg_en && (w_reg_addr != 5'h0) && (r_reg_addr1 == w_reg_addr));

    cov_rs2_write_through: cover property (
        @(posedge clk) w_reg_en && (w_reg_addr != 5'h0) && (r_reg_addr2 == w_reg_addr));

    cov_dual_read_same_reg: cover property (
        @(posedge clk) (r_reg_addr1 == r_reg_addr2) && (r_reg_addr1 != 5'h0));

    cov_write_x0_attempt: cover property (
        @(posedge clk) w_reg_en && (w_reg_addr == 5'h0));

endmodule

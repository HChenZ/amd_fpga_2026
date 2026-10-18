`timescale 1ns / 1ps
`include "defines.v"

// Registered operands -> registered product, with completion held until EX ack.
// No architectural multicycle timing exception: each stage has one clock period.
module multiplier #(
    parameter XLEN = 32
)(
    input                   clk,
    input                   rst_n,

    input                   mul_start,
    input   [XLEN-1:0]      rs1_data,
    input   [XLEN-1:0]      rs2_data,
    input   [5:0]           func_sel,

    output  [XLEN-1:0]      mul_result,
    output reg              mul_done,
    input                   mul_ack,
    input                   cancel
);

    wire rs1_is_signed = (func_sel == `EXE_MULH_OP) || (func_sel == `EXE_MULHSU_OP);
    wire rs2_is_signed = (func_sel == `EXE_MULH_OP);

    wire rs1_sign = rs1_is_signed & rs1_data[XLEN-1];
    wire rs2_sign = rs2_is_signed & rs2_data[XLEN-1];

    wire signed [XLEN:0] op1_ext = {rs1_sign, rs1_data};
    wire signed [XLEN:0] op2_ext = {rs2_sign, rs2_data};

    reg signed [2*XLEN+1:0]   p_reg;
    reg signed [XLEN:0]      op1_q, op2_q;
    reg [5:0]                 func_reg;

    localparam IDLE = 2'd0, PRODUCT = 2'd1, COMPLETE = 2'd2;
    reg [1:0] count;

    // Deliberately reset-free datapath registers allow DSP input/output packing.
    // They are never consumed before the control FSM has produced mul_done.
    always @(posedge clk) begin
        if (count == IDLE && mul_start && !cancel) begin
            op1_q <= op1_ext;
            op2_q <= op2_ext;
        end
        p_reg <= op1_q * op2_q;
    end

    always @(posedge clk or negedge rst_n) 
    begin
        if (!rst_n) 
        begin
            count    <= 2'b00;
            mul_done <= 1'b0;
            func_reg <= 6'h0;
        end
        else if (cancel)
        begin
            count <= IDLE;
            mul_done <= 1'b0;
        end
        else begin
            case (count)
                IDLE: if (mul_start) begin
                    func_reg <= func_sel;
                    count    <= PRODUCT;
                    mul_done <= 1'b0;
                end
                PRODUCT: begin
                    mul_done <= 1'b1;
                    count    <= COMPLETE;
                end
                COMPLETE: if (mul_ack) begin
                    count <= IDLE;
                    mul_done <= 1'b0;
                end
                default: begin
                    count <= IDLE;
                    mul_done <= 1'b0;
                end
            endcase
        end
    end

    // Product is stable throughout COMPLETE, including downstream holds.
    assign mul_result = (func_reg == `EXE_MUL_OP || func_reg == `EXE_MULW_OP)
                      ? p_reg[XLEN-1:0]
                      : p_reg[2*XLEN-1 : XLEN];

endmodule

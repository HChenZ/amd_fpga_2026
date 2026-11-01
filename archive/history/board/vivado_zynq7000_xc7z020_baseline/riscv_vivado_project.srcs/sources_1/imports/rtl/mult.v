`timescale 1ns / 1ps
`include "defines.v"

// 合并版 FSM + 组合输出：mul_result 组合自 p_reg，不注册
// State0: 锁存输入+组合乘 → p_reg。State1: mul_done=1
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
    output reg              mul_done
);

    wire rs1_is_signed = (func_sel == `EXE_MULH_OP) || (func_sel == `EXE_MULHSU_OP);
    wire rs2_is_signed = (func_sel == `EXE_MULH_OP);

    wire rs1_sign = rs1_is_signed & rs1_data[XLEN-1];
    wire rs2_sign = rs2_is_signed & rs2_data[XLEN-1];

    wire signed [XLEN:0] op1_ext = {rs1_sign, rs1_data};
    wire signed [XLEN:0] op2_ext = {rs2_sign, rs2_data};

    reg signed [2*XLEN+1:0]   p_reg;
    reg [5:0]                 func_reg;

    reg [1:0] count;

    always @(posedge clk or negedge rst_n) 
    begin
        if (!rst_n) 
        begin
            count    <= 2'b00;
            mul_done <= 1'b0;
            p_reg    <= {(2*XLEN+2){1'b0}};
            func_reg <= 6'h0;
        end
        else if (mul_start)
        begin
            case (count)
                2'd0: 
                begin
                    p_reg    <= op1_ext * op2_ext;
                    func_reg <= func_sel;
                    count    <= count + 1'b1;
                    mul_done <= 1'b0;
                end
                2'd1: 
                begin
                    mul_done <= 1'b1;
                    count    <= 2'b00;
                end
            endcase
        end
        else 
        begin
            count    <= 2'b00;
            mul_done <= 1'b0;
        end
    end

    // 组合输出 — p_reg 在 State0 末锁定，C1 期间 comb 有效
    assign mul_result = (func_reg == `EXE_MUL_OP || func_reg == `EXE_MULW_OP)
                      ? p_reg[XLEN-1:0]
                      : p_reg[2*XLEN-1 : XLEN];

endmodule
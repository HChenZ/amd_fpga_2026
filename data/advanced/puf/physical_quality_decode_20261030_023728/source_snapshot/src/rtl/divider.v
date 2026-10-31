`timescale 1ns / 1ps
`include "defines.v"

module divider #(
    parameter XLEN = 32
)(
    input  wire             clk,
    input  wire             rst_n,
    
    input  wire             div_start,  
    input  wire [XLEN-1:0]  rs1_data,   // ID 阶段传来的原始数据 (W指令高32位已被清零)
    input  wire [XLEN-1:0]  rs2_data,   
    input  wire [5:0]       func_sel,   
    input  wire             is_word_op, // 关键信号：标识当前是否为 W 后缀指令

    output reg  [XLEN-1:0]  div_result, 
    output reg              div_done    
);

    // =========================================================================
    // 指令类型解析
    // =========================================================================
    wire is_signed = (func_sel == `EXE_DIV_OP) || (func_sel == `EXE_REM_OP) || (func_sel == `EXE_DIVW_OP) || (func_sel == `EXE_REMW_OP);
    wire is_rem    = (func_sel == `EXE_REM_OP) || (func_sel == `EXE_REMU_OP) || (func_sel == `EXE_REMW_OP) || (func_sel == `EXE_REMUW_OP);

    // =========================================================================
    // 数据清洗 
    // =========================================================================
    wire [XLEN-1:0] op1_eff;
    wire [XLEN-1:0] op2_eff;


    assign op1_eff = (is_word_op && is_signed) ? {{32{rs1_data[31]}}, rs1_data[31:0]} : rs1_data;
    assign op2_eff = (is_word_op && is_signed) ? {{32{rs2_data[31]}}, rs2_data[31:0]} : rs2_data;


    // =========================================================================
    // 符号判断与绝对值提取
    // =========================================================================
    wire out_sign_quot = is_signed & (op1_eff[XLEN-1] ^ op2_eff[XLEN-1]); 
    wire out_sign_rem  = is_signed & op1_eff[XLEN-1];

    wire [XLEN-1:0] op1_unsigned = (is_signed & op1_eff[XLEN-1]) ? (~op1_eff + 1'b1) : op1_eff;
    wire[XLEN-1:0] op2_unsigned = (is_signed & op2_eff[XLEN-1]) ? (~op2_eff + 1'b1) : op2_eff;

    // 除 0 判断
    wire div_by_zero = (op2_eff == {XLEN{1'b0}});

    // =========================================================================
    // 状态机与工作寄存器
    // =========================================================================
    localparam IDLE  = 2'd0;
    localparam CALC  = 2'd1;
    localparam DONE  = 2'd2;

    reg [1:0]  state;
    // 64 位架构下必须能数到 64，所以需要 7 位计数器
    reg [6:0]  count;       
    
    // 移位寄存器宽度为 2*XLEN
    reg [2*XLEN-1:0] shift_reg;   
    reg [XLEN-1:0]   divisor_reg; 
    
    reg latched_sign_quot;
    reg latched_sign_rem;
    reg latched_is_rem;

    // =========================================================================
    // 移位减法逻辑
    // =========================================================================
    wire [XLEN:0] sub_res = {1'b0, shift_reg[2*XLEN-2 : XLEN-1]} - {1'b0, divisor_reg};
    wire          enough  = ~sub_res[XLEN]; 

    wire [XLEN-1:0] final_quot = latched_sign_quot ? (~shift_reg[XLEN-1:0] + 1'b1) : shift_reg[XLEN-1:0];
    wire[XLEN-1:0] final_rem  = latched_sign_rem  ? (~shift_reg[2*XLEN-1 : XLEN] + 1'b1) : shift_reg[2*XLEN-1 : XLEN];

    // =========================================================================
    // 最终结果整理 (Result Formatting)
    // =========================================================================
    // 取出原始的 64/32 位结果
    wire [XLEN-1:0] raw_result = latched_is_rem ? final_rem : final_quot;
    reg  [XLEN-1:0] formatted_result;

    always @(*) 
    begin
        if (is_word_op) 
        begin
            // 无论是有符号还是无符号 W 指令，最终结果必须对低 32 位进行符号扩展
            formatted_result = {{32{raw_result[31]}}, raw_result[31:0]};
        end 
        else 
        begin
            // 普通 64 位指令或 32 位模式，直接输出
            formatted_result = raw_result;
        end
    end

    // =========================================================================
    // 主状态机
    // =========================================================================
    always @(posedge clk or negedge rst_n) 
    begin
        if (!rst_n) 
        begin
            state             <= IDLE;
            count             <= 7'b0;
            div_done          <= 1'b0;
            div_result        <= {XLEN{1'b0}};
            shift_reg         <= {2*XLEN{1'b0}};
            divisor_reg       <= {XLEN{1'b0}};
            latched_sign_quot <= 1'b0;
            latched_sign_rem  <= 1'b0;
            latched_is_rem    <= 1'b0;
        end 
        else 
        begin
            case (state)
                IDLE: 
                begin
                    div_done <= 1'b0;
                    if (div_start) 
                    begin
                        if (div_by_zero) 
                        begin
                            // 除以 0 时，RISC-V 规定商全1，余数等于被除数
                            shift_reg[XLEN-1:0] <= {XLEN{1'b1}}; 
                            shift_reg[2*XLEN-1: XLEN] <= op1_eff;
                            latched_sign_quot <= 1'b0; 
                            latched_sign_rem <= 1'b0;
                            latched_is_rem <= is_rem;
                            
                            state <= DONE; 
                        end 
                        else 
                        begin
                            shift_reg <= {{XLEN{1'b0}}, op1_unsigned}; 
                            divisor_reg <= op2_unsigned;
                            
                            latched_sign_quot <= out_sign_quot;
                            latched_sign_rem <= out_sign_rem;
                            latched_is_rem <= is_rem;
                            
                            count <= 7'd0;
                            state <= CALC;
                        end
                    end
                end

                CALC: 
                begin
                    if (count == XLEN - 1) 
                    begin
                        state <= DONE; 
                    end
                    count <= count + 1'b1;
                    
                    if (enough) 
                    begin
                        shift_reg <= {sub_res[XLEN-1:0], shift_reg[XLEN-2:0], 1'b1};
                    end 
                    else 
                    begin
                        shift_reg <= {shift_reg[2*XLEN-2:0], 1'b0};
                    end
                end

                DONE: 
                begin
                    div_result <= formatted_result;
                    div_done <= 1'b1; 
                    state <= IDLE; 
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule
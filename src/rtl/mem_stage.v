`timescale 1ns / 1ps
`include "defines.v"
module mem_stage #(
    parameter XLEN = 32
)(
    // from ex_mem (registered)
    input                   ex_reg_w_en,
    input   [XLEN-1:0]      ex_rd_data,
    input   [XLEN-1:0]      ex_mem_addr,
    input   [4:0]           ex_reg_addr,
    input   [2:0]           ex_op_sel,
    input   [5:0]           ex_func_sel,

    // from D-Cache / BRAM
    input   [XLEN-1:0]      mem_r_data,

    // to mem_wb
    output                  mem_reg_w_en,
    output  [XLEN-1:0]      mem_rd_data,
    output  [4:0]           mem_reg_addr,
    output  [2:0]           mem_op_sel

);

    // =========================================================================
    // byte_offset 计算
    // =========================================================================
    wire [2:0] byte_offset;

    generate
        if(XLEN==64) 
        begin
            assign byte_offset = ex_mem_addr[2:0];
        end 
        else 
        begin
            assign byte_offset = {1'b0, ex_mem_addr[1:0]};
        end
    endgenerate

    // =========================================================================
    // 数据对齐：将读取出的数据右移，把有效数据移到最低位
    // =========================================================================
    reg [XLEN-1:0] r_data;

    generate
        if(XLEN==64) 
        begin
            always @(*) 
            begin
                case(byte_offset)
                    3'b000: r_data = mem_r_data;
                    3'b001: r_data = mem_r_data >> 8;
                    3'b010: r_data = mem_r_data >> 16;
                    3'b011: r_data = mem_r_data >> 24;
                    3'b100: r_data = mem_r_data >> 32;
                    3'b101: r_data = mem_r_data >> 40;
                    3'b110: r_data = mem_r_data >> 48;
                    3'b111: r_data = mem_r_data >> 56;
                    default: r_data = 64'h0;
                endcase
            end
        end else 
        begin
            always @(*) 
            begin
                case(byte_offset[1:0])
                    2'b00: r_data = mem_r_data;
                    2'b01: r_data = mem_r_data >> 8;
                    2'b10: r_data = mem_r_data >> 16;
                    2'b11: r_data = mem_r_data >> 24;
                    default: r_data = 32'h0;
                endcase
            end
        end
    endgenerate

    // =========================================================================
    // Load 符号扩展 / 零扩展
    // =========================================================================
    reg [XLEN-1:0] load_data;

    generate
        if(XLEN==64) 
        begin
            always @(*) 
            begin
                case(ex_func_sel)
                    `EXE_LB_OP:  load_data = {{(XLEN-8){r_data[7]}}, r_data[7:0]};
                    `EXE_LH_OP:  load_data = {{(XLEN-16){r_data[15]}}, r_data[15:0]};
                    `EXE_LW_OP:  load_data = {{32{r_data[31]}}, r_data[31:0]};
                    `EXE_LBU_OP: load_data = {{(XLEN-8){1'b0}}, r_data[7:0]};
                    `EXE_LHU_OP: load_data = {{(XLEN-16){1'b0}}, r_data[15:0]};
                    `EXE_LWU_OP: load_data = {32'b0, r_data[31:0]};
                    `EXE_LD_OP:  load_data = r_data;
                    default:     load_data = {XLEN{1'b0}};
                endcase
            end
        end 
        else 
        begin
            always @(*) 
            begin
                case(ex_func_sel)
                    `EXE_LB_OP:  load_data = {{(XLEN-8){r_data[7]}}, r_data[7:0]};
                    `EXE_LH_OP:  load_data = {{(XLEN-16){r_data[15]}}, r_data[15:0]};
                    `EXE_LW_OP:  load_data = r_data;
                    `EXE_LBU_OP: load_data = {{(XLEN-8){1'b0}}, r_data[7:0]};
                    `EXE_LHU_OP: load_data = {{(XLEN-16){1'b0}}, r_data[15:0]};
                    default:     load_data = {XLEN{1'b0}};
                endcase
            end
        end
    endgenerate

    // =========================================================================
    // 结果选择：load 用 RAM 数据，其他透传 ALU 结果
    // =========================================================================
    assign mem_reg_w_en = ex_reg_w_en;
    assign mem_reg_addr = ex_reg_addr;
    assign mem_op_sel   = ex_op_sel;
    assign mem_rd_data = (ex_op_sel == `EXE_RES_LOAD_STORE) ? load_data : ex_rd_data;

endmodule
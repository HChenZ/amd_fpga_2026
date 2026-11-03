`timescale 1ns / 1ps
module bypass #(parameter XLEN = 32)
  (
    input  [XLEN-1:0]  rs1_i,
    input  [XLEN-1:0]  rs2_i,

    // 旁路数据源
    input  [XLEN-1:0]  ex_mem_rd_data,
    input  [XLEN-1:0]  mem_wb_rd_data,

    // 来自 id_ex 寄存器的控制信号
    input sel_ex_mem_rs1,
    input sel_mem_wb_rs1,
    input sel_ex_mem_rs2,
    input sel_mem_wb_rs2,

    // 输出到 EX 阶段
    output reg [XLEN-1:0] rs1_o,
    output reg [XLEN-1:0] rs2_o
  );

    //rs1 旁路 MUX: ex_mem > mem_wb
    always @(*)
    begin
        if (sel_ex_mem_rs1)
          rs1_o = ex_mem_rd_data;
        else if (sel_mem_wb_rs1)
          rs1_o = mem_wb_rd_data;
        else
          rs1_o = rs1_i;
    end

    //rs2 旁路 MUX
    always @(*)
    begin
        if (sel_ex_mem_rs2)
          rs2_o = ex_mem_rd_data;
        else if (sel_mem_wb_rs2)
          rs2_o = mem_wb_rd_data;
        else
          rs2_o = rs2_i;
    end

endmodule
`timescale 1ns / 1ps
// BUFG 的 Icarus 仿真模型（Vivado 综合时用 UNISIM 原语，不要编译本文件）
module BUFG (input wire I, output wire O);
    assign O = I;
endmodule

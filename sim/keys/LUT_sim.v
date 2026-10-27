`timescale 1ns / 1ps
// LUT1/LUT2 的 Icarus 仿真模型（Vivado 综合时用 UNISIM 原语，不要编译本文件）
module LUT1 #(parameter [1:0] INIT = 2'b00) (output wire O, input wire I0);
    assign O = INIT[I0];
endmodule
module LUT2 #(parameter [3:0] INIT = 4'b0000) (output wire O, input wire I0, input wire I1);
    assign O = INIT[{I1, I0}];
endmodule

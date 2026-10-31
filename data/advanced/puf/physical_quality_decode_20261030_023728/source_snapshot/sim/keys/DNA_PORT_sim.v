`timescale 1ns / 1ps
// =============================================================================
// DNA_PORT_sim.v  ——  Xilinx DNA_PORT 原语的 Icarus 仿真 model
//
// 综合（Vivado）时不要编译本文件：Vivado 用 UNISIM 库自带的 DNA_PORT 原语。
// Icarus 仿真时用本 model 模拟 READ/SHIFT 行为：
//   - READ 拉高一拍：并行载入 SIM_DNA_VALUE 到内部 57-bit 移位寄存器；
//   - SHIFT 拉高：DOUT 同步移出 MSB（bit56 先出），寄存器左移，DIN 从低位补入。
//
// 位序约定：DOUT 为 MSB-first（bit56 先移出），与 Xilinx UG953 / support 文章
// 64847 的 SIM_DNA_VALUE=[56:0](MSB:LSB) 语义一致。上板后以 Vivado Device
// Programmer 显示的 DNA 值核对位序（见 README）。
// =============================================================================
module DNA_PORT #(
    parameter [56:0] SIM_DNA_VALUE = 57'h0
)(
    input  wire CLK,
    input  wire DIN,     // 用户数据输入（本设计恒接 0）
    output reg  DOUT,    // 移出数据（MSB first）
    input  wire READ,    // 高有效：载入 DNA
    input  wire SHIFT    // 高有效：移位使能
);

    reg [56:0] sr;

    always @(posedge CLK) begin
        if (READ) begin
            sr   <= SIM_DNA_VALUE;   // 并行载入 57-bit DNA
            DOUT <= 1'b0;
        end
        else if (SHIFT) begin
            DOUT <= sr[56];          // 移出最高位
            sr   <= {sr[55:0], DIN}; // 左移，低位补 DIN
        end
    end

endmodule

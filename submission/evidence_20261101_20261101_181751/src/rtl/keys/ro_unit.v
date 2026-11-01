`timescale 1ns / 1ps
// =============================================================================
// ro_unit.v — 环形振荡器单元（RO PUF 的基本单元）
//
// 综合（定义 SYNTHESIS）：**用 LUT 原语显式搭 5 级奇数环**，每级都 DONT_TOUCH：
//   n0 = LUT2(NAND): ~(en & n4)
//   n1..n4 = LUT1(INV): ~n(i-1)
//   osc = n4
//   为什么不用 assign 链：Vivado 会把整条反相链合并成**一个** LUT（DRC 里能看到
//   "1 LUT cells form a combinatorial loop"），级数失控、频率也不再由 STAGES 决定。
//   原语 + DONT_TOUCH 能保证 256 个 RO 各自是 5 级环，级数可控。
//
// 仿真（不定义 SYNTHESIS）：Icarus 无法仿真真实组合环，用时钟分频模拟固定频率振荡，
//   只验证采样/计数/比较/表决逻辑；真实随机性必须上板测。
// =============================================================================
(* DONT_TOUCH = "yes" *) (* keep = "true" *) (* keep_hierarchy = "yes" *)
module ro_unit #(
    parameter STAGES  = 5,   // 环内反相级数（奇数，>=3）
    parameter SIM_DIV = 3    // 仿真分频：每 SIM_DIV 个 clk 翻转一次
)(
    input  wire clk,   // 仅仿真使用
    input  wire en,    // 1 = 振荡
    output wire osc
);

`ifdef SYNTHESIS
    // ---------------------------------------------------------------- 真实 RO
    // n[0] = ~(en & n[STAGES-1])  用 LUT2，INIT=8'b0010 (O = ~(I0 & I1))
    wire [STAGES-1:0] n;

    (* DONT_TOUCH = "yes" *) LUT2 #(.INIT(4'b0010)) u_nand (
        .O (n[0]),
        .I0(en),
        .I1(n[STAGES-1])
    );

    genvar i;
    generate
        for (i = 1; i < STAGES; i = i + 1) begin : g_inv
            // LUT1，INIT=2'b01 → O = ~I0
            (* DONT_TOUCH = "yes" *) LUT1 #(.INIT(2'b01)) u_inv (
                .O  (n[i]),
                .I0 (n[i-1])
            );
        end
    endgenerate

    assign osc = n[STAGES-1];
`else
    // ---------------------------------------------------------------- 仿真模型
    reg [15:0] div;
    reg        q;
    always @(posedge clk or negedge en) begin
        if (!en) begin
            div <= 16'd0;
            q   <= 1'b0;
        end else if (div >= SIM_DIV[15:0] - 16'd1) begin
            div <= 16'd0;
            q   <= ~q;
        end else begin
            div <= div + 16'd1;
        end
    end
    assign osc = q;
`endif

endmodule

`timescale 1ns / 1ps
// =============================================================================
// device_dna.v — 读取 XC7Z020 出厂唯一 Device DNA（57-bit）
//
// 时序（与 Xilinx DNA_PORT 原语一致）：
//   IDLE --start--> LOAD(READ=1 一拍，载入 DNA) --> SHIFT(SHIFT=1，DOUT 逐位移出)
//   --> DONE(valid 一拍)
//
// 位序说明（上板必须核对一次）：
//   DNA_PORT 的 DOUT 在 SHIFT 有效后由寄存器给出，因此在第一个 SHIFT 拍采样
//   拿到的是载入拍留下的值，而不是 bit56。SHIFT_SKIP 用来对齐这个相位：
//     SHIFT_SKIP=1（默认）：跳过第一个 SHIFT 拍，采 57 个真 bit；
//     SHIFT_SKIP=0：从第一个 SHIFT 拍开始采。
//   上板做法：把读到的 dna 与 Vivado Hardware Manager -> Device Properties 里显示的
//   DNA 值逐位比对（或在 Programmer 的 "Read Device DNA" 中读出），
//   若整体错一位就把 SHIFT_SKIP 取反。**这一步未做之前不要用它生成密钥。**
//
// 安全语义（重要）：
//   DNA 是"唯一 ID"，不是秘密——任何拿到这颗芯片的人都能读出同样的 DNA。
//   它的作用是设备绑定/域分隔，熵上限 57 bit；真正的秘密必须来自 RO PUF。
// =============================================================================
module device_dna #(
    parameter [56:0] SIM_DNA     = 57'h0,  // 仅仿真：注入的 DNA 值
    parameter        SHIFT_SKIP  = 1       // 采样相位，见上
)(
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,     // 1 拍脉冲
    output reg  [56:0]  dna,
    output reg          valid      // 1 拍脉冲
);

    localparam [1:0] IDLE = 2'd0, LOAD = 2'd1, SHIFT = 2'd2, DONE = 2'd3;
    localparam [5:0] SKIP = SHIFT_SKIP[5:0];   // 参数不能直接做位选，先落地

    reg  [1:0] state;
    reg  [5:0] cnt;
    wire       dout;

    wire read_p  = (state == LOAD);
    wire shift_p = (state == SHIFT);

    // Vivado 综合时映射到 UNISIM 硬核；Icarus 仿真时由 sim/keys/DNA_PORT_sim.v 提供同名 model
    DNA_PORT #(.SIM_DNA_VALUE(SIM_DNA)) u_dna_port (
        .CLK  (clk),
        .DIN  (1'b0),
        .DOUT (dout),
        .READ (read_p),
        .SHIFT(shift_p)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            cnt   <= 6'd0;
            dna   <= 57'b0;
            valid <= 1'b0;
        end else begin
            valid <= 1'b0;
            case (state)
                IDLE: begin
                    cnt <= 6'd0;
                    // 不在 IDLE 清零：读到的值要留到上层取走（清零只在复位时）
                    if (start) state <= LOAD;
                end
                LOAD: state <= SHIFT;              // READ 已拉高一拍，DNA_PORT 已载入
                SHIFT: begin
                    if (cnt >= SKIP)
                        dna <= {dna[55:0], dout};
                    if (cnt == (6'd56 + SKIP))
                        state <= DONE;
                    else
                        cnt <= cnt + 1'b1;
                end
                DONE: begin
                    valid <= 1'b1;
                    state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end

endmodule

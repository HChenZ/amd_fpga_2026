`timescale 1ns / 1ps
// =============================================================================
// puf_key.v — 密钥子系统：DNA + RO-PUF -> 稳定响应 -> Ascon p12 KDF -> 128-bit key
//
// 安全模型（写进报告要能站得住）：
//   * PUF 提供**秘密**：RO 频率指纹只有这颗芯片测得出来（不可复制、不含存储）。
//   * DNA 提供**绑定**：57-bit 出厂唯一 ID，把密钥钉在这一颗芯片上。
//   * key = P12( KDF_CTX ^ {const, const, puf_bits, {7'b0, dna}} )[127:0]
//     即：PUF 与 DNA 都参与，任何一方缺失都无法重建同一把钥匙。
//
// 两种工作模式（start 触发，mode 选择）：
//   mode=1 ENROLL（一次性）：采 PUF -> 记录 ref = raw、mask = ~dither，标记 enrolled。
//                            需要把 ref/mask 回填到 INIT_REF/INIT_MASK（见文档流程）。
//   mode=0 RECONSTRUCT（每次上电）：采 PUF -> 与 ref/mask 比对
//                            - 稳定位全一致：用 raw & mask 派生密钥
//                            - 有不一致位：标记 mismatch 并**回退为 DNA-only 派生**
//                              （保证系统还能跑，同时把降级状态暴露给软件）
//
// 为什么用掩码而不是纠错码：
//   RO PUF 的失效模式主要是"个别位在温压变化下翻转"，用 dither（M 次采样不一致）
//   把它们整位丢弃，比做 BCH 简单得多；丢弃位用 N_RO=256 的冗余吃掉。
//   若实测 BER 仍高，再在该模块后加 BCH/重复码（P03 的下一步）。
// =============================================================================
module puf_key #(
    parameter [56:0]  SIM_DNA   = 57'h0,
    parameter         USE_PUF   = 1,          // 0 = 只用 DNA 派生（无 PUF 的降级模式）
    parameter [127:0] INIT_REF  = 128'h0,     // enroll 后回填
    parameter [127:0] INIT_MASK = 128'h0,     // 同上：1 = 该位稳定可用
    parameter [56:0]  SHIFT_SKIP = 1,
    // RO PUF 参数（透传）
    parameter N_RO         = 256,
    parameter CW           = 20,
    parameter WINDOW       = 65536,
    parameter DWELL        = 256,
    parameter M            = 5,
    parameter STAGES       = 5,
    parameter SIM_DIV_BASE = 3,
    parameter SIM_DIV_STEP = 1,
    parameter SIM_DIV_SPAN = 16,
    parameter [127:0] SIM_DITHER = 128'h0
)(
    input  wire         clk,
    input  wire         ro_clk,   // 慢时钟域（顶层 clk/4），只给 RO 采样用
    input  wire         rst_n,
    input  wire         start,       // 1 拍脉冲：开始一次密钥生成
    input  wire         mode,        // 1 = enroll, 0 = reconstruct
    output reg  [127:0] key,
    output reg          key_valid,   // key 更新后 1 拍脉冲
    output reg          busy,
    output reg          done,        // 一次流程结束的 1 拍脉冲
    output reg          mismatch,    // reconstruct 时 PUF 响应与 ref 不一致（已回退）
    output reg          fallback,    // 本次使用了 DNA-only 降级密钥
    output reg          enrolled,    // ref/mask 已就绪
    output reg  [7:0]   quality,     // 可用（稳定且掩码内）位数，饱和到 255
    // 调试/上板 enroll 用回读
    output wire [56:0]  dna_o,
    output wire [127:0] puf_raw_o,
    output wire [127:0] dither_o,
    output wire [127:0] helper_ref_o,    // enroll 产物：参考响应（MMIO 回读用）
    output wire [127:0] helper_mask_o    // enroll 产物：可用掩码
);

    localparam BITS = N_RO/2;

    // ---------------------------------------------------------------- 常量
    // 域分隔：让 KDF 输出与本项目其它 p12 用途（AEAD/ISE）不重叠
    localparam [63:0] CTX_S3 = 64'h4B455947454E3033;   // "KEYGEN03"
    localparam [63:0] CTX_S4 = 64'h4B455947454E3034;   // "KEYGEN04"
    localparam [319:0] KDF_CTX = {
        64'h5A5A5A5A5A5A5A5A, 64'hA5A5A5A5A5A5A5A5,
        128'h0123456789ABCDEFFEDCBA9876543210, 64'h0
    };

    // ---------------------------------------------------------------- 子模块
    reg  dna_req;
    wire [56:0] dna;
    wire        dna_valid;
    reg  [56:0] dna_lat;   // 读到的 DNA 必须锁存：device_dna 之后不会再保持

    device_dna #(.SIM_DNA(SIM_DNA), .SHIFT_SKIP(SHIFT_SKIP)) u_dna (
        .clk(clk), .rst_n(rst_n), .start(dna_req),
        .dna(dna), .valid(dna_valid)
    );
    assign dna_o = dna_lat;

    reg  puf_req;
    wire [BITS-1:0] puf_raw, puf_dither, puf_stable;
    wire            puf_valid, puf_busy;

    ro_puf_core #(
        .N_RO(N_RO), .CW(CW), .WINDOW(WINDOW), .DWELL(DWELL), .M(M), .STAGES(STAGES),
        .SIM_DIV_BASE(SIM_DIV_BASE), .SIM_DIV_STEP(SIM_DIV_STEP),
        .SIM_DIV_SPAN(SIM_DIV_SPAN), .SIM_DITHER(SIM_DITHER)
    ) u_puf (
        .clk(clk), .ro_clk(ro_clk), .rst_n(rst_n), .start(puf_req),
        .raw(puf_raw), .dither(puf_dither), .stable(puf_stable),
        .valid(puf_valid), .busy(puf_busy)
    );
    assign puf_raw_o    = puf_raw;
    assign dither_o     = puf_dither;

    // helper（enroll 写入，掉电由 INIT_* 回填；片内寄存器实现，综合后是 256 个 FF）
    reg [BITS-1:0] h_ref;
    reg [BITS-1:0] mask;

    // 供 MMIO 回读（不属于秘密：helper data 在 PUF 方案里本就是公开量）
    assign helper_ref_o  = h_ref;
    assign helper_mask_o = mask;

    // ---------------------------------------------------------------- KDF
    reg  kdf_start;
    wire [319:0] kdf_out;
    wire         kdf_done, kdf_busy;

    reg [BITS-1:0] puf_bits;          // 参与派生的 PUF 位（已按 mask 处理/或回退清零）

    wire [319:0] kdf_material = {
        CTX_S4, CTX_S3,
        puf_bits[127:0],
        {7'b0, dna_lat}
    };
    wire [319:0] kdf_in = kdf_material ^ KDF_CTX;

    p12 u_kdf (
        .clk(clk), .rst_n(rst_n), .start(kdf_start),
        .s_in(kdf_in), .s_out(kdf_out), .done(kdf_done), .busy(kdf_busy)
    );

    // ---------------------------------------------------------------- 控制
    localparam [2:0] IDLE = 3'd0, DNA_W = 3'd1, PUF_W = 3'd2, COMPARE = 3'd3,
                     KDF_W = 3'd4, FIN = 3'd5;

    reg [2:0] state;

    // popcount：(mask & ~dither) 的位数，饱和到 255
    integer b;
    reg [15:0] pc;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= IDLE;
            dna_req   <= 1'b0;
            puf_req   <= 1'b0;
            kdf_start <= 1'b0;
            key       <= 128'b0;
            key_valid <= 1'b0;
            busy      <= 1'b0;
            done      <= 1'b0;
            mismatch  <= 1'b0;
            fallback  <= 1'b0;
            enrolled  <= (INIT_MASK != 0);
            quality   <= 8'd0;
            h_ref       <= INIT_REF;
            mask      <= INIT_MASK;
            puf_bits  <= {BITS{1'b0}};
            dna_lat   <= 57'b0;
        end else begin
            key_valid <= 1'b0;
            done      <= 1'b0;
            dna_req   <= 1'b0;
            puf_req   <= 1'b0;
            kdf_start <= 1'b0;

            case (state)
                IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        busy    <= 1'b1;
                        mismatch <= 1'b0;
                        fallback <= 1'b0;
                        dna_req <= 1'b1;
                        state   <= DNA_W;
                    end
                end

                DNA_W: begin
                    if (dna_valid) begin
                        dna_lat <= dna;
                        if (USE_PUF) begin
                            puf_req <= 1'b1;
                            state   <= PUF_W;
                        end else begin
                            // 无 PUF：只用 DNA，直接进 KDF
                            puf_bits <= {BITS{1'b0}};
                            fallback <= 1'b1;
                            state    <= COMPARE;
                        end
                    end
                end

                PUF_W: begin
                    if (puf_valid) begin
                        if (mode) begin
                            // ---- ENROLL：记录参考位与可用掩码
                            h_ref      <= puf_raw;
                            mask     <= puf_stable;
                            enrolled <= 1'b1;
                            puf_bits <= puf_raw & puf_stable;
                        end else begin
                            // ---- RECONSTRUCT
                            if (!enrolled) begin
                                // 没有 helper：只能降级，避免产生一把"随机的"密钥
                                mismatch <= 1'b1;
                                fallback <= 1'b1;
                                puf_bits <= {BITS{1'b0}};
                            end else if ((puf_raw & mask) != (h_ref & mask)) begin
                                mismatch <= 1'b1;
                                fallback <= 1'b1;
                                puf_bits <= {BITS{1'b0}};
                            end else begin
                                puf_bits <= puf_raw & mask;
                            end
                        end
                        // 质量统计：enroll 数"稳定位数"，reconstruct 数"可用（掩码内）位数"
                        pc = 0;
                        for (b = 0; b < BITS; b = b + 1) begin
                            if (mode ? puf_stable[b] : mask[b]) pc = pc + 1;
                        end
                        quality <= (pc > 16'd255) ? 8'd255 : pc[7:0];
                        state   <= COMPARE;
                    end
                end

                COMPARE: begin
                    kdf_start <= 1'b1;
                    state     <= KDF_W;
                end

                KDF_W: begin
                    if (kdf_done) begin
                        key       <= kdf_out[127:0];
                        key_valid <= 1'b1;
                        busy      <= 1'b0;
                        done      <= 1'b1;
                        state     <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule

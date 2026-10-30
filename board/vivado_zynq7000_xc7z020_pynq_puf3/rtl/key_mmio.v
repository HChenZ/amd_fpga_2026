`timescale 1ns / 1ps
// =============================================================================
// key_mmio.v — 密钥子系统的 MMIO 状态/控制窗口（挂在 Ascon 窗口内的 0x80 段）
//
// 为什么挂在 ascon 窗口而不是新开一段总线地址：
//   bus_interconnect.v 是共享文件（另一个 agent 也在改）。Ascon 窗口已经占
//   0x3000_0000，ascon_addr_sel[5:0] 只用到 0..22，0x80 起（sel 32..52）是空的，
//   在这里再加一个只读寄存器组不需要动总线译码，零冲突。
//
// 地址（基址 0x3000_0000，字索引 = 偏移>>2）：
//   0x80  STATUS   R   [0]busy [1]key_ready(粘滞) [2]enrolled [3]mismatch(实时)
//                      [4]fallback(实时) [5]done(粘滞) [15:8]quality
//                      [6]key_hw_sel(实际生效) [7]hwkey_on(软件请求)   <- pynq_puf3 新增
//   0x84  CTRL     W   [0]START(自清) [1]ENROLL(保持) [2]CLEAR(清粘滞位)
//                      [3]HWKEY_ON [4]HWKEY_OFF(同写时 OFF 优先)          <- pynq_puf3 新增
//
// pynq_puf3 变体（2026-10-30）：相对 src/rtl/keys/key_mmio.v 只增加 HWKEY 开关
// 与 STATUS[7:6] 回读；复位默认关闭，硬件密钥不再在 key_valid 时自动锁定。
//   0x88  DNA_LO   R   dna[31:0]
//   0x8C  DNA_HI   R   {7'b0, dna[56:32]}
//   0x90  QUALITY  R   {24'b0, quality}
//   0x94..0xA0  REF0..3    R  helper 参考位（enroll 产物，写回 INIT_REF）
//   0xA4..0xB0  MASK0..3   R  helper 可用掩码（写回 INIT_MASK）
//   0xB4..0xC0  DITHER0..3 R  本次采样中不稳定的位（P02 统计用）
//   0xC4..0xD0  RAW0..3    R  本次多数表决后的原始响应（P02 统计用）
//
// 安全边界：**本模块不暴露 key**。key 只在 puf_key -> ascon_mmio 的内部通路上，
// CPU 既不能写也不能读；这里能读的 DNA / helper / 状态都属于公开量或降级指示。
// =============================================================================
module key_mmio (
    input  wire         clk,
    input  wire         rst_n,

    // ---- 总线（Ascon 窗口内） ----
    input  wire         ascon_re,
    input  wire         ascon_we,
    input  wire [5:0]   ascon_addr_sel,
    input  wire [31:0]  ascon_wdata,
    output reg  [31:0]  key_rdata,      // 未选中时输出 0（总线用 OR 合并）

    // ---- 给 puf_key 的控制 ----
    output reg          key_start,      // 1 拍脉冲
    output reg          key_enroll_mode,
    output reg          hwkey_on,       // 软件请求使用硬件密钥（复位 0）
    input  wire         key_hw_sel,     // soc_top 实际送给 ascon_mmio 的选择

    // ---- 从 puf_key 读状态/数据 ----
    input  wire         key_valid,
    input  wire         key_busy,
    input  wire         key_done,
    input  wire         key_mismatch,
    input  wire         key_fallback,
    input  wire         key_enrolled,
    input  wire [7:0]   key_quality,
    input  wire [56:0]  key_dna,
    input  wire [127:0] key_ref,
    input  wire [127:0] key_mask,
    input  wire [127:0] key_dither,
    input  wire [127:0] key_raw
);

    localparam [5:0] BASE      = 6'd32;   // 0x80 >> 2
    localparam [5:0] A_STATUS  = BASE + 6'd0;
    localparam [5:0] A_CTRL    = BASE + 6'd1;
    localparam [5:0] A_DNA_LO  = BASE + 6'd2;
    localparam [5:0] A_DNA_HI  = BASE + 6'd3;
    localparam [5:0] A_QUAL    = BASE + 6'd4;
    localparam [5:0] A_REF0    = BASE + 6'd5;    // +0..3
    localparam [5:0] A_MASK0   = BASE + 6'd9;    // +0..3
    localparam [5:0] A_DITH0   = BASE + 6'd13;   // +0..3
    localparam [5:0] A_RAW0    = BASE + 6'd17;   // +0..3

    // ready/done 是单拍脉冲，需要粘滞；mismatch/fallback 是 puf_key 内的保持电平，
    // 直接透传即可（每次 start 会自清）——粘滞反而会在 CLEAR 后把旧值重新置位。
    reg key_ready_sticky, done_sticky;

    // ---------------------------------------------------------------- 粘滞状态
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key_ready_sticky <= 1'b0;
            done_sticky      <= 1'b0;
        end else if (ascon_we && (ascon_addr_sel == A_CTRL) && ascon_wdata[2]) begin
            key_ready_sticky <= 1'b0;
            done_sticky      <= 1'b0;
        end else begin
            if (key_valid) key_ready_sticky <= 1'b1;
            if (key_done)  done_sticky      <= 1'b1;
        end
    end

    // ---------------------------------------------------------------- 控制
    // 板上实测问题：忙时写 START 会被静默丢弃（第三次操作 reconstruct 就这样超时）。
    // 现在改为"排队"：忙时置 start_pend，空闲后自动补发一次，模式在请求时刻快照。
    // 另外 ENROLL/RECONSTRUCT 模式只在真正发 START 的那一拍更新，CLEAR 不再改模式。
    reg start_pend;
    reg pend_mode;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key_start       <= 1'b0;
            key_enroll_mode <= 1'b0;
            start_pend      <= 1'b0;
            pend_mode       <= 1'b0;
        end else begin
            key_start <= 1'b0;                       // 自清脉冲
            if (ascon_we && (ascon_addr_sel == A_CTRL)) begin
                if (ascon_wdata[0]) begin
                    if (!key_busy) begin
                        key_start       <= 1'b1;
                        key_enroll_mode <= ascon_wdata[1];
                    end else begin
                        start_pend <= 1'b1;          // 忙：排队，不丢
                        pend_mode  <= ascon_wdata[1];
                    end
                end
                if (ascon_wdata[2]) start_pend <= 1'b0;   // CLEAR 取消排队
            end
            // 排队请求在器件空闲时补发（与 CLEAR 同拍时让 CLEAR 优先）
            if (start_pend && !key_busy && !key_start &&
                !(ascon_we && (ascon_addr_sel == A_CTRL) && ascon_wdata[2])) begin
                key_start       <= 1'b1;
                key_enroll_mode <= pend_mode;
                start_pend      <= 1'b0;
            end
        end
    end

    // ---------------------------------------------------------------- HWKEY 开关
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            hwkey_on <= 1'b0;
        else if (ascon_we && (ascon_addr_sel == A_CTRL)) begin
            if (ascon_wdata[4])      hwkey_on <= 1'b0;
            else if (ascon_wdata[3]) hwkey_on <= 1'b1;
        end
    end

    // ---------------------------------------------------------------- 读数据
    always @(*) begin
        key_rdata = 32'b0;
        case (ascon_addr_sel)
            // [0]busy [1]key_ready [2]enrolled [3]mismatch [4]fallback [5]done
            // [6]key_hw_sel [7]hwkey_on [15:8]quality [31:16]保留
            A_STATUS: key_rdata = {16'b0, key_quality, hwkey_on, key_hw_sel,
                                   done_sticky, key_fallback, key_mismatch,
                                   key_enrolled, key_ready_sticky, key_busy};
            A_DNA_LO: key_rdata = key_dna[31:0];
            A_DNA_HI: key_rdata = {7'b0, key_dna[56:32]};
            A_QUAL:   key_rdata = {24'b0, key_quality};
            A_REF0+0: key_rdata = key_ref[31:0];
            A_REF0+1: key_rdata = key_ref[63:32];
            A_REF0+2: key_rdata = key_ref[95:64];
            A_REF0+3: key_rdata = key_ref[127:96];
            A_MASK0+0: key_rdata = key_mask[31:0];
            A_MASK0+1: key_rdata = key_mask[63:32];
            A_MASK0+2: key_rdata = key_mask[95:64];
            A_MASK0+3: key_rdata = key_mask[127:96];
            A_DITH0+0: key_rdata = key_dither[31:0];
            A_DITH0+1: key_rdata = key_dither[63:32];
            A_DITH0+2: key_rdata = key_dither[95:64];
            A_DITH0+3: key_rdata = key_dither[127:96];
            A_RAW0+0: key_rdata = key_raw[31:0];
            A_RAW0+1: key_rdata = key_raw[63:32];
            A_RAW0+2: key_rdata = key_raw[95:64];
            A_RAW0+3: key_rdata = key_raw[127:96];
            default:  key_rdata = 32'b0;             // 未选中：必须为 0（总线 OR 合并）
        endcase
    end

endmodule

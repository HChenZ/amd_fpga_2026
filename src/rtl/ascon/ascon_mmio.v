`timescale 1ns / 1ps

`include "ascon_aead_core.v"

// =============================================================================
// ascon_mmio.v  ——  处理器对接接口（MMIO 寄存器文件 + 控制 FSM + 数据缓冲）
//
// 作用：把 CPU 的 MMIO 总线（bus_interconnect 译码出的 ascon_re/we/addr_sel/
//       wdata/rdata）翻译成 ascon_aead_core 的流式控制接口。CPU 侧通过寄存器
//       写 key/nonce/AD/msg/长度，触发 START，轮询 STATUS，再读回 CT/PT/tag。
//
// 寄存器映射（基址 0x30000000，32-bit 字访问，addr_sel = cpu_addr[7:2]）：
//   0x00 CTRL     W   [0]=START(自清脉冲) [1]=ENCRYPT(1加密/0解密) [2]=ZEROIZE(idle only, wins START)
//   0x04 STATUS   R   [0]=BUSY [1]=DONE [2]=FAIL(解密 tag 校验失败)
//   0x08 ADLEN    W   AD 字节数
//   0x0C MLEN     W   消息字节数
//   0x10~0x1C     W   KEY   K0..K3（小端序字）
//   0x20~0x2C     W   NONCE N0..N3（小端序字）
//   0x30~0x3C     W   TAGIN T0..T3（解密：待校验 tag）
//   0x40 AD_WDATA W   推入一个 AD 字（内部指针自增）
//   0x44 MSG_WDATA W  推入一个消息字（加密=明文 / 解密=密文）
//   0x48 OUT_RDATA R  弹出一个输出字（加密=密文 / 解密=明文，指针自增）
//   0x4C~0x58     R   TAGOUT 0..3（加密：计算出的 tag）
//
// 与总线时序约定（与 clint/gpio/uart/cpi 完全一致）：
//   - re/we 是 1 拍脉冲；
//   - 读数据在 re 的当拍寄存，下一拍出现在 ascon_rdata；
//   - 无读请求时 ascon_rdata 必须为 0（总线用 OR 门合并，防止串扰）。
// =============================================================================
module ascon_mmio #(
    parameter MAX_AD_BYTES  = 256,   // 必须为 4 的倍数
    parameter MAX_MSG_BYTES = 256    // 必须为 4 的倍数
)(
    input  wire         clk,
    input  wire         rst_n,

    // ---- 总线接口（来自 bus_interconnect） ----
    input  wire         ascon_re,        // 读脉冲
    input  wire         ascon_we,        // 写脉冲
    input  wire [5:0]   ascon_addr_sel,  // 字索引（byte offset >> 2）
    input  wire [31:0]  ascon_wdata,
    output wire [31:0]  ascon_rdata,

    // ---- 完成中断（可选） ----
    output wire         ascon_irq        // DONE 时给出一拍脉冲
);

    // -------------------------------------------------------------------------
    // 寄存器地址（字索引）常量
    // -------------------------------------------------------------------------
    localparam [5:0] R_CTRL      = 6'd0;
    localparam [5:0] R_STATUS    = 6'd1;
    localparam [5:0] R_ADLEN     = 6'd2;
    localparam [5:0] R_MLEN      = 6'd3;
    localparam [5:0] R_KEY0      = 6'd4;
    localparam [5:0] R_KEY1      = 6'd5;
    localparam [5:0] R_KEY2      = 6'd6;
    localparam [5:0] R_KEY3      = 6'd7;
    localparam [5:0] R_NONCE0    = 6'd8;
    localparam [5:0] R_NONCE1    = 6'd9;
    localparam [5:0] R_NONCE2    = 6'd10;
    localparam [5:0] R_NONCE3    = 6'd11;
    localparam [5:0] R_TAGIN0    = 6'd12;
    localparam [5:0] R_TAGIN1    = 6'd13;
    localparam [5:0] R_TAGIN2    = 6'd14;
    localparam [5:0] R_TAGIN3    = 6'd15;
    localparam [5:0] R_AD_WDATA  = 6'd16;
    localparam [5:0] R_MSG_WDATA = 6'd17;
    localparam [5:0] R_OUT_RDATA = 6'd18;
    localparam [5:0] R_TAGOUT0   = 6'd19;
    localparam [5:0] R_TAGOUT1   = 6'd20;
    localparam [5:0] R_TAGOUT2   = 6'd21;
    localparam [5:0] R_TAGOUT3   = 6'd22;

    // -------------------------------------------------------------------------
    // 缓冲深度与指针位宽
    // -------------------------------------------------------------------------
    localparam AD_WORDS  = MAX_AD_BYTES  / 4;
    localparam MSG_WORDS = MAX_MSG_BYTES / 4;
    localparam AD_IDX_W  = $clog2(AD_WORDS  + 1);
    localparam MSG_IDX_W = $clog2(MSG_WORDS + 1);

    // -------------------------------------------------------------------------
    // 内部数据缓冲（AD 输入、消息输入、CT/PT 输出）
    // -------------------------------------------------------------------------
    reg [31:0] AD_BUF  [0:AD_WORDS-1];
    reg [31:0] MSG_BUF [0:MSG_WORDS-1];
    reg [31:0] OUT_BUF [0:MSG_WORDS-1];

    // -------------------------------------------------------------------------
    // 寄存器文件
    // -------------------------------------------------------------------------
    reg [15:0]  adlen_r;
    reg [15:0]  mlen_r;
    reg [127:0] key_r;
    reg [127:0] nonce_r;
    reg [127:0] tagin_r;
    reg [127:0] tagout_r;

    reg         busy_r;
    reg         done_r;
    reg         fail_r;
    reg         irq_r;

    // CPU 侧数据缓冲写/读指针（IDLE 时由 CPU 推进，START 时复位）
    reg [AD_IDX_W-1:0]  ad_wr_cnt;
    reg [MSG_IDX_W-1:0] msg_wr_cnt;
    reg [MSG_IDX_W-1:0] out_rd_cnt;

    // 核心侧数据流指针（RUN 时推进）
    reg         run_encrypt;
    reg [15:0]  run_adlen;
    reg [15:0]  run_mlen;
    reg [127:0] run_key;
    reg [127:0] run_nonce;
    reg [127:0] run_tagin;
    reg [15:0]  total_words;   // = ad_words + msg_words
    reg [15:0]  feed_cnt;      // 已喂给核心的输入字数
    reg [15:0]  out_cnt;       // 已收到的输出字数
    reg         core_start_pulse;

    // 读数据寄存器（打一拍，对齐总线时序）
    reg [31:0]  rdata_reg;

    // -------------------------------------------------------------------------
    // 核心接口信号
    // -------------------------------------------------------------------------
    wire         core_in_req;
    wire         core_out_valid;
    wire [31:0]  core_out_word;
    wire [127:0] core_tag_out;
    wire         core_done;
    wire         core_success;

    // START 条件：写 CTRL 且 bit0=1，且当前空闲
    wire zeroize_cond = ascon_we && (ascon_addr_sel == R_CTRL) && ascon_wdata[2] && !busy_r;
    reg core_clear;
    integer ai, oi;
    wire start_cond = ascon_we && (ascon_addr_sel == R_CTRL) && ascon_wdata[0] && !busy_r && !zeroize_cond;

    // 计算字长（字节数向上取整到 4 的倍数）
    wire [15:0] ad_words  = (run_adlen + 16'd3) >> 2;
    wire [15:0] msg_words = (run_mlen  + 16'd3) >> 2;

    // 组合逻辑：当前要喂给核心的输入字
    wire [15:0]           msg_base = feed_cnt - ad_words;
    wire [AD_IDX_W-1:0]   ad_idx    = feed_cnt[AD_IDX_W-1:0];
    wire [MSG_IDX_W-1:0]  msg_idx   = msg_base[MSG_IDX_W-1:0];
    wire [31:0] core_in_word = (feed_cnt < ad_words) ? AD_BUF[ad_idx] : MSG_BUF[msg_idx];
    wire       core_in_last = (feed_cnt == (total_words - 16'd1));

    // =========================================================================
    // 块 A：CPU 写路径（寄存器 + AD/msg 数据缓冲，指针复位）
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            adlen_r   <= 16'b0;
            mlen_r    <= 16'b0;
            key_r     <= 128'b0;
            nonce_r   <= 128'b0;
            tagin_r   <= 128'b0;
            ad_wr_cnt <= {AD_IDX_W{1'b0}};
            msg_wr_cnt<= {MSG_IDX_W{1'b0}};
            for (ai=0; ai<AD_WORDS; ai=ai+1) AD_BUF[ai] <= 0;
            for (ai=0; ai<MSG_WORDS; ai=ai+1) MSG_BUF[ai] <= 0;
        end
        else if (zeroize_cond) begin
            adlen_r   <= 16'b0;
            mlen_r    <= 16'b0;
            key_r     <= 128'b0;
            nonce_r   <= 128'b0;
            tagin_r   <= 128'b0;
            ad_wr_cnt <= {AD_IDX_W{1'b0}};
            msg_wr_cnt<= {MSG_IDX_W{1'b0}};
            for (ai=0; ai<AD_WORDS; ai=ai+1) AD_BUF[ai] <= 0;
            for (ai=0; ai<MSG_WORDS; ai=ai+1) MSG_BUF[ai] <= 0;
        end
        else begin
            // 新一次操作开始：复位数据缓冲写指针
            if (start_cond) begin
                ad_wr_cnt  <= {AD_IDX_W{1'b0}};
                msg_wr_cnt <= {MSG_IDX_W{1'b0}};
            end

            if (ascon_we && !busy_r) begin
                case (ascon_addr_sel)
                    R_ADLEN:     adlen_r <= ascon_wdata[15:0];
                    R_MLEN:      mlen_r  <= ascon_wdata[15:0];
                    R_KEY0:      key_r[31:0]    <= ascon_wdata;
                    R_KEY1:      key_r[63:32]   <= ascon_wdata;
                    R_KEY2:      key_r[95:64]   <= ascon_wdata;
                    R_KEY3:      key_r[127:96]  <= ascon_wdata;
                    R_NONCE0:    nonce_r[31:0]    <= ascon_wdata;
                    R_NONCE1:    nonce_r[63:32]   <= ascon_wdata;
                    R_NONCE2:    nonce_r[95:64]   <= ascon_wdata;
                    R_NONCE3:    nonce_r[127:96]  <= ascon_wdata;
                    R_TAGIN0:    tagin_r[31:0]    <= ascon_wdata;
                    R_TAGIN1:    tagin_r[63:32]   <= ascon_wdata;
                    R_TAGIN2:    tagin_r[95:64]   <= ascon_wdata;
                    R_TAGIN3:    tagin_r[127:96]  <= ascon_wdata;
                    R_AD_WDATA: begin
                        if (ad_wr_cnt < AD_WORDS) begin
                            AD_BUF[ad_wr_cnt] <= ascon_wdata;
                            ad_wr_cnt <= ad_wr_cnt + 1'b1;
                        end
                    end
                    R_MSG_WDATA: begin
                        if (msg_wr_cnt < MSG_WORDS) begin
                            MSG_BUF[msg_wr_cnt] <= ascon_wdata;
                            msg_wr_cnt <= msg_wr_cnt + 1'b1;
                        end
                    end
                    default: ;
                endcase
            end
        end
    end

    // =========================================================================
    // 块 B：CPU 读路径（寄存器 + OUT 数据缓冲，读指针复位）
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rdata_reg  <= 32'b0;
            out_rd_cnt <= {MSG_IDX_W{1'b0}};
        end
        else if (zeroize_cond) begin
            rdata_reg  <= 32'b0;
            out_rd_cnt <= {MSG_IDX_W{1'b0}};
        end
        else begin
            // 新一次操作开始：复位输出读指针
            if (start_cond)
                out_rd_cnt <= {MSG_IDX_W{1'b0}};

            if (ascon_re) begin
                case (ascon_addr_sel)
                    R_STATUS:    rdata_reg <= {29'b0, fail_r, done_r, busy_r};
                    R_ADLEN:     rdata_reg <= {16'b0, adlen_r};
                    R_MLEN:      rdata_reg <= {16'b0, mlen_r};
                    R_OUT_RDATA: begin
                        rdata_reg <= 32'b0;
                        if (done_r && !busy_r && !fail_r && !start_cond &&
                            out_rd_cnt < msg_words && out_rd_cnt < MSG_WORDS) begin
                            rdata_reg <= OUT_BUF[out_rd_cnt];
                            out_rd_cnt <= out_rd_cnt + 1'b1;
                        end
                    end
                    R_TAGOUT0:   rdata_reg <= tagout_r[31:0];
                    R_TAGOUT1:   rdata_reg <= tagout_r[63:32];
                    R_TAGOUT2:   rdata_reg <= tagout_r[95:64];
                    R_TAGOUT3:   rdata_reg <= tagout_r[127:96];
                    default:     rdata_reg <= 32'b0;
                endcase
            end
            else begin
                // 无读请求时输出 0，防止总线 OR 门串扰
                rdata_reg <= 32'b0;
            end
        end
    end

    // =========================================================================
    // 块 C：控制 FSM + 核心握手
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy_r          <= 1'b0;
            done_r          <= 1'b0;
            fail_r          <= 1'b0;
            irq_r           <= 1'b0;
            run_encrypt     <= 1'b0;
            run_adlen       <= 16'b0;
            run_mlen        <= 16'b0;
            run_key         <= 128'b0;
            run_nonce       <= 128'b0;
            run_tagin       <= 128'b0;
            total_words     <= 16'b0;
            feed_cnt        <= 16'b0;
            out_cnt         <= 16'b0;
            tagout_r        <= 128'b0;
            core_start_pulse<= 1'b0;
            core_clear <= 1'b0;
            for (oi=0; oi<MSG_WORDS; oi=oi+1) OUT_BUF[oi] <= 0;
        end
        else if (zeroize_cond) begin
            busy_r          <= 1'b0;
            done_r          <= 1'b0;
            fail_r          <= 1'b0;
            irq_r           <= 1'b0;
            run_encrypt     <= 1'b0;
            run_adlen       <= 16'b0;
            run_mlen        <= 16'b0;
            run_key         <= 128'b0;
            run_nonce       <= 128'b0;
            run_tagin       <= 128'b0;
            total_words     <= 16'b0;
            feed_cnt        <= 16'b0;
            out_cnt         <= 16'b0;
            tagout_r        <= 128'b0;
            core_start_pulse<= 1'b0;
            core_clear <= 1'b1;
            for (oi=0; oi<MSG_WORDS; oi=oi+1) OUT_BUF[oi] <= 0;
        end
        else begin
            core_clear <= 1'b0;
            // 脉冲信号默认衰减
            core_start_pulse <= 1'b0;
            irq_r            <= 1'b0;

            if (start_cond) begin
                tagout_r <= 128'b0;
                for (oi=0; oi<MSG_WORDS; oi=oi+1) OUT_BUF[oi] <= 0;
                // 锁存本次操作的参数，并复位核心侧指针
                run_encrypt      <= ascon_wdata[1];
                run_adlen        <= adlen_r;
                run_mlen         <= mlen_r;
                run_key          <= key_r;
                run_nonce        <= nonce_r;
                run_tagin        <= tagin_r;
                total_words      <= ((adlen_r + 16'd3) >> 2) + ((mlen_r + 16'd3) >> 2);
                feed_cnt         <= 16'b0;
                out_cnt          <= 16'b0;
                busy_r           <= 1'b1;
                done_r           <= 1'b0;
                fail_r           <= 1'b0;
                core_start_pulse <= 1'b1;
            end
            else if (busy_r) begin
                // 输入：核心请求就喂一个字
                if (core_in_req)
                    feed_cnt <= feed_cnt + 1'b1;

                // 输出：核心给数据就收进 OUT_BUF
                if (core_out_valid && out_cnt < MSG_WORDS) begin
                    // Mask unused bytes: the packed core bus includes private state.
                    if (out_cnt == msg_words-1 && run_mlen[1:0] != 0)
                        OUT_BUF[out_cnt] <= core_out_word & (32'hffffffff >> (8*(4-run_mlen[1:0])));
                    else OUT_BUF[out_cnt] <= core_out_word;
                    out_cnt <= out_cnt + 1'b1;
                end

                // 完成：收 tag，置状态，给中断
                if (core_done) begin
                    busy_r    <= 1'b0;
                    done_r    <= 1'b1;
                    fail_r    <= ~core_success;
                    tagout_r  <= core_success ? core_tag_out : 128'b0;
                    if (!core_success)
                        for (oi=0; oi<MSG_WORDS; oi=oi+1) OUT_BUF[oi] <= 0;
                    irq_r     <= 1'b1;
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // 核心实例化
    // -------------------------------------------------------------------------
    ascon_aead_core #(
        .MAX_AD_BYTES (MAX_AD_BYTES),
        .MAX_MSG_BYTES(MAX_MSG_BYTES)
    ) u_ascon_core (
        .clk       (clk),
        .rst_n     (rst_n && !core_clear),
        .start     (core_start_pulse),
        .encrypt   (run_encrypt),
        .adlen     (run_adlen),
        .mlen      (run_mlen),
        .key       (run_key),
        .nonce     (run_nonce),
        .tag_in    (run_tagin),
        .in_req    (core_in_req),
        .in_word   (core_in_word),
        .in_last   (core_in_last),
        .out_valid (core_out_valid),
        .out_word  (core_out_word),
        .out_ready (1'b1),
        .tag_out   (core_tag_out),
        .busy      (),
        .done      (core_done),
        .success   (core_success)
    );

    // -------------------------------------------------------------------------
    // 输出
    // -------------------------------------------------------------------------
    assign ascon_rdata = rdata_reg;
    assign ascon_irq   = irq_r;

endmodule

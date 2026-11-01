`timescale 1ns / 1ps
// =============================================================================
// ro_puf_core.v — RO PUF 采样器（RO 自身时钟计数 + 慢时钟域控制 + 跨时钟握手）
//
// 为什么这样测：
//   1) RO 的频率（典型 150~300 MHz on 7-series LUT）**高于**系统时钟，用 clk 去数
//      它的上升沿会混叠，测不到频率。因此每个 RO 直接驱动自己的计数器时钟
//      （posedge osc[i]），窗口内自由计数。
//   2) 采样控制（窗口/清零/比较/表决）跑在独立的慢时钟域 ro_clk（顶层由 clk/4 产生，
//      100 MHz -> 25 MHz），把 256 个计数器 + 表决逻辑从核心时钟域里隔离出去，
//      减少对 CPU 时序的扰动；pblock 由 XDC 单独约束（见 build/keys_ro_pblock.xdc）。
//   3) 域间只传两个翻转脉冲：start（clk->ro_clk）与 done（ro_clk->clk）。
//      raw/dither 在 done 之后保持稳定，核心侧直接读（静态数据，无需逐位同步）。
//
// 位定义：bit i = (cnt[i] >= cnt[i+BITS])，i = 0..BITS-1，BITS = N_RO/2。
//   M 次采样后逐位多数表决得到 raw；M 次里既出现过 1 又出现过 0 的位标记为 dither。
//
// 安全/稳定性：频率差随温压漂移，单次采样不能当密钥；本模块只提供"多次表决 + 抖动位"，
//   稳定性 BER 与唯一性必须上板实测（P02）。仿真里的频率差是 SIM_DIV_* 注入的确定性值。
// =============================================================================
module ro_puf_core #(
    parameter N_RO         = 256,     // RO 数量（偶数）
    parameter CW           = 20,      // 计数器位宽
    parameter WINDOW       = 16384,   // 采样窗口（ro_clk 周期）
    parameter DWELL        = 256,     // 起振/清零等待（ro_clk 周期）
    parameter M            = 5,       // 采样次数（奇数）
    parameter STAGES       = 5,       // RO 环内反相级数
    parameter SIM_DIV_BASE = 3,
    parameter SIM_DIV_STEP = 1,
    parameter SIM_DIV_SPAN = 13,
    parameter [127:0] SIM_DITHER = 128'h0
)(
    input  wire                 clk,        // 核心时钟域（握手用）
    input  wire                 ro_clk,     // 慢速时钟域（计数控制）
    input  wire                 rst_n,
    input  wire                 start,      // clk 域，1 拍脉冲
    output reg  [N_RO/2-1:0]    raw,
    output reg  [N_RO/2-1:0]    dither,
    output wire [N_RO/2-1:0]    stable,
    output reg                  valid,      // clk 域，1 拍脉冲
    output reg                  busy
);

    localparam BITS  = N_RO/2;
    localparam WW    = $clog2(WINDOW+1);
    localparam ACC_W = $clog2(M+1);

    // ---------------------------------------------------------------- 跨域握手
    reg  req_tgl;          // clk 域
    reg  done_tgl;         // ro_clk 域
    reg  [1:0] done_sync;  // clk 域同步 done_tgl
    reg  [2:0] req_sync;   // ro_clk 域同步 req_tgl
    reg  [2:0] done_seen;

    wire req_event  = req_sync[1] ^ req_sync[2];
    wire done_event = done_sync[0] ^ done_sync[1];

    // 慢时钟域的复位（异步置位、同步释放）
    reg [1:0] ro_rst_sync;
    wire      ro_rst_n = ro_rst_sync[1];

    always @(posedge ro_clk or negedge rst_n) begin
        if (!rst_n) ro_rst_sync <= 2'b00;
        else        ro_rst_sync <= {ro_rst_sync[0], 1'b1};
    end

    // ---------------------------------------------------------------- RO 阵列
    wire [N_RO-1:0]  osc;
    reg  [CW-1:0]    cnt [0:N_RO-1];
    reg              ro_en;      // ro_clk 域
    reg              cnt_en;     // ro_clk 域
    reg              cnt_clr;    // ro_clk 域
    reg  [CW-1:0]    pre [0:N_RO-1];   // 采样结束后从 RO 域搬到 ro_clk 域的快照

    genvar k;
    generate
        for (k = 0; k < N_RO; k = k + 1) begin : g_ro
            ro_unit #(
                .STAGES  (STAGES),
                .SIM_DIV (SIM_DIV_BASE + ((k*7) % SIM_DIV_SPAN)*SIM_DIV_STEP)
            ) u_ro (
                .clk (clk),
                .en  (ro_en),
                .osc (osc[k])
            );

            // 计数器时钟 = 该 RO 自身（PUF 的标准做法）
            always @(posedge osc[k]) begin
                if (cnt_clr)      cnt[k] <= {CW{1'b0}};
                else if (cnt_en)  cnt[k] <= cnt[k] + 1'b1;
            end
        end
    endgenerate

    // ---------------------------------------------------------------- ro_clk 域 FSM
    localparam [2:0] R_IDLE = 3'd0, R_ARM = 3'd1, R_DWELL = 3'd2, R_COUNT = 3'd3,
                     R_SETTLE = 3'd4, R_EVAL = 3'd5, R_FINAL = 3'd6;

    reg [2:0]       rstate;
    reg [2:0]       m;
    reg [WW-1:0]    win, dwell;
    reg [BITS*ACC_W-1:0] acc;
    reg [BITS-1:0]  raw_r, dith_r;
    integer         b;

    // ---------------------------------------------------------------- 看门狗
    // 板上实测：连续第三次操作时 done 永不到来（ro_clk 域卡在采样中间态）。
    // 采样域必须保证"请求进来 → 一定给出 done"，否则上层总线软件只能超时。
    // 上限取 M 个窗口 + 余量，超出即强制收尾（用当前累加值出结果）。
    localparam integer WD_RO = (M * (WINDOW + 2*DWELL + 8)) + 32*DWELL;
    localparam [23:0]  WD_RO_C = WD_RO[23:0];
    reg [23:0] ro_wd;

    always @(posedge ro_clk or negedge ro_rst_n) begin
        if (!ro_rst_n) begin
            req_sync  <= 3'b000;
            done_tgl  <= 1'b0;
            rstate    <= R_IDLE;
            m         <= 3'd0;
            win       <= {WW{1'b0}};
            dwell     <= {WW{1'b0}};
            acc       <= {(BITS*ACC_W){1'b0}};
            raw_r     <= {BITS{1'b0}};
            dith_r    <= {BITS{1'b0}};
            ro_en     <= 1'b0;
            cnt_en    <= 1'b0;
            cnt_clr   <= 1'b0;
            ro_wd     <= 24'd0;
        end else begin
            req_sync <= {req_sync[1:0], req_tgl};
            cnt_clr  <= 1'b0;

            // 离线/看门狗计数（非 IDLE 才走）
            if (rstate == R_IDLE) ro_wd <= 24'd0;
            else if (ro_wd != 24'hFFFFFF) ro_wd <= ro_wd + 24'd1;

            if (req_event) begin
                // 新请求是权威的：无论当前在 IDLE 还是卡在中间态，一律从起振重来
                ro_en   <= 1'b1;
                dwell   <= {WW{1'b0}};
                win     <= {WW{1'b0}};
                m       <= 3'd0;
                acc     <= {(BITS*ACC_W){1'b0}};
                cnt_en  <= 1'b0;
                cnt_clr <= 1'b1;
                ro_wd   <= 24'd0;
                rstate  <= R_DWELL;
            end else if ((rstate != R_IDLE) && (ro_wd >= WD_RO_C)) begin
                // 看门狗兜底：强制出结果，保证上层一定收到 valid/done
                ro_en    <= 1'b0;
                cnt_en   <= 1'b0;
                done_tgl <= ~done_tgl;
                rstate   <= R_IDLE;
            end else case (rstate)
                R_IDLE: begin
                    ro_en  <= 1'b0;
                    cnt_en <= 1'b0;
                    if (req_event) begin
                        ro_en  <= 1'b1;         // 先起振
                        dwell  <= {WW{1'b0}};
                        m      <= 3'd0;
                        acc    <= {(BITS*ACC_W){1'b0}};
                        rstate <= R_DWELL;
                    end
                end

                R_DWELL: begin
                    if (dwell >= DWELL[WW-1:0]) begin
                        cnt_clr <= 1'b1;        // 清计数（RO 仍在跑，保证有时钟进来）
                        win     <= {WW{1'b0}};
                        rstate  <= R_ARM;
                    end else
                        dwell <= dwell + 1'b1;
                end

                R_ARM: begin                    // 清计数保持足够长，再开计数
                    cnt_clr <= 1'b1;
                    cnt_en  <= 1'b1;
                    win     <= {WW{1'b0}};
                    rstate  <= R_COUNT;
                end

                R_COUNT: begin
                    if (win >= WINDOW[WW-1:0] - 1'b1) begin
                        cnt_en  <= 1'b0;        // 停止计数，计数器变静态
                        dwell   <= {WW{1'b0}};
                        rstate  <= R_SETTLE;    // 等静态
                    end else
                        win <= win + 1'b1;
                end

                R_SETTLE: begin
                    if (dwell >= DWELL[WW-1:0]) begin
                        for (b = 0; b < N_RO; b = b + 1)
                            pre[b] <= cnt[b];   // 静态快照（多周期路径）
                        rstate <= R_EVAL;
                    end else
                        dwell <= dwell + 1'b1;
                end

                R_EVAL: begin
                    for (b = 0; b < BITS; b = b + 1) begin
                        // SIM_DITHER[b]=1 的位按采样序号奇偶翻转，仿真里制造"不稳定位"
                        if ((pre[b] >= pre[b+BITS]) ^ (SIM_DITHER[b] & m[0]))
                            acc[b*ACC_W +: ACC_W] <= acc[b*ACC_W +: ACC_W] + 1'b1;
                    end
                    // 抖动位：本次结果与上一次累加是否出现分歧（用 acc 计数判定）
                    if (m == M[2:0] - 1'b1) begin
                        m      <= 3'd0;
                        rstate <= R_FINAL;
                    end else begin
                        m      <= m + 1'b1;
                        rstate <= R_DWELL;
                    end
                end

                R_FINAL: begin
                    for (b = 0; b < BITS; b = b + 1) begin
                        raw_r[b]  <= ((acc[b*ACC_W +: ACC_W] << 1) > M);
                        dith_r[b] <= (acc[b*ACC_W +: ACC_W] != 0) &&
                                     (acc[b*ACC_W +: ACC_W] != M);
                    end
                    ro_en    <= 1'b0;
                    done_tgl <= ~done_tgl;      // 通知 clk 域
                    rstate   <= R_IDLE;
                end

                default: rstate <= R_IDLE;
            endcase
        end
    end

    // ---------------------------------------------------------------- clk 域收尾
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            req_tgl   <= 1'b0;
            done_sync <= 2'b00;
            done_seen <= 3'b000;
            raw       <= {BITS{1'b0}};
            dither    <= {BITS{1'b0}};
            valid     <= 1'b0;
            busy      <= 1'b0;
        end else begin
            valid     <= 1'b0;
            done_sync <= {done_sync[0], done_tgl};
            if (start && !busy) begin
                busy    <= 1'b1;
                req_tgl <= ~req_tgl;
            end
            if (done_event) begin
                raw    <= raw_r;      // 静态数据，直接搬
                dither <= dith_r;
                valid  <= 1'b1;
                busy   <= 1'b0;
            end
        end
    end

    assign stable = ~dither;

endmodule

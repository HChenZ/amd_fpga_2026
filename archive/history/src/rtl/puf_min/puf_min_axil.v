`timescale 1ns/1ps
// =============================================================================
// puf_min_axil.v — PUF-MIN 4KiB AXI4-Lite 寄存器从机 + RO-PUF 采样器
//
// 任务：PUF-MIN（tasks/puf_fix_and_min_goal_20261030.md §4.3/§4.5）
// 目标：只把"物理响应"留在 PL；注册/重建/派生/统计全部由 PS 上的 Python 完成。
// 本模块不含 CPU、BRAM、AEAD、helper、镜像认证、邮箱。
//
// 单时钟设计：clk 同时作为 ro_puf_core_v2 的 clk 与 ro_clk（E1 已验证）。
// RO 环形振荡器本身仍然是异步物理环路（ro_array_v2 + 行为级模型），
// 因此"无时钟 pin / 未约束端点"必然存在，本设计不宣称对其签核。
//
// 寄存器（4KiB，字节偏移；未列出的偏移读返回 SLVERR、写返回 SLVERR）：
//   0x00 ID        R  0x4E494D50 ("PMIN")
//   0x04 VERSION   R  1
//   0x08 CTRL      W  bit0 START(脉冲) bit1 CLEAR(脉冲)；两位置 1 时 CLEAR 优先
//   0x0C STATUS    R  bit0 busy bit1 done(粘滞) bit2 valid(粘滞) bit3 locked
//                     bit4 dna_ready
//   0x10 ERROR     R  {24'b0, core.error_code}（最近一次采样结束时锁存）
//   0x14 TXN       R  事务号：每个 START 脉冲 +1；只有模块复位 rst_n 归零，
//                     CLEAR 不清零（CLEAR 会复位采样器核，驱动仍需可区分的新鲜度）
//   0x20..0x2C RAW[0..3] R  128-bit 响应；valid=0 时读 0
//   0x30 DNA_LO    R  {dna[31:0]}
//   0x34 DNA_HI    R  {7'b0, dna[56:32]}
//   0x40 CNT_SEL   W  8-bit 计数器下标 0..255（默认 0）
//   0x44 CNT_VAL   R  {12'b0, snapshot[sel]}；valid=0 时读 0
//
// 明确声明（不得含糊）：RAW 可被任意读回，**没有保密性**；DNA 是唯一 ID 不是秘密；
// 本设计不提供 ECC、熵估计、安全提取器、安全启动或防回滚。
// =============================================================================
module puf_min_axil #(
    parameter CW            = 20,
    parameter WINDOW        = 1024,
    parameter RO_DEADLINE   = 8192,
    parameter CORE_DEADLINE = 65536,
    parameter BITS          = 128,
    parameter [56:0] SIM_DNA = 57'h1234,
    parameter SHIFT_SKIP    = 1
)(
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF S_AXI, ASSOCIATED_RESET rst_n" *)
    input  wire        clk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst_n RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input  wire        rst_n,

    // ---- AXI4-Lite 从机 ----
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWADDR" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME S_AXI, PROTOCOL AXI4LITE, DATA_WIDTH 32, ADDR_WIDTH 12, READ_WRITE_MODE READ_WRITE, HAS_BURST 0, NUM_READ_OUTSTANDING 1, NUM_WRITE_OUTSTANDING 1" *)
    input  wire [11:0] s_axi_awaddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWPROT" *)
    input  wire [2:0]  s_axi_awprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWVALID" *)
    input  wire        s_axi_awvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWREADY" *)
    output wire        s_axi_awready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WDATA" *)
    input  wire [31:0] s_axi_wdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WSTRB" *)
    input  wire [3:0]  s_axi_wstrb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WVALID" *)
    input  wire        s_axi_wvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WREADY" *)
    output wire        s_axi_wready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BRESP" *)
    output wire [1:0]  s_axi_bresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BVALID" *)
    output wire        s_axi_bvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BREADY" *)
    input  wire        s_axi_bready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARADDR" *)
    input  wire [11:0] s_axi_araddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARPROT" *)
    input  wire [2:0]  s_axi_arprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARVALID" *)
    input  wire        s_axi_arvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARREADY" *)
    output wire        s_axi_arready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RDATA" *)
    output wire [31:0] s_axi_rdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RRESP" *)
    output wire [1:0]  s_axi_rresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RVALID" *)
    output wire        s_axi_rvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RREADY" *)
    input  wire        s_axi_rready,

    // ---- 物理 RO 环阵列（仿真时替换为行为级模型）----
    input  wire [2*BITS-1:0] osc
);
    localparam [31:0] ID_VALUE  = 32'h4E494D50; // "PMIN"
    localparam [31:0] VER_VALUE = 32'h0000_0001;

    localparam [1:0] OKAY = 2'b00, SLVERR = 2'b10;

    // -------------------------------------------------------------------------
    // CTRL 脉冲生成：单拍 START / CLEAR
    // -------------------------------------------------------------------------
    reg        start_pulse, clear_pulse;
    reg [7:0]  cnt_sel;

    // -------------------------------------------------------------------------
    // 采样器 + DNA
    // -------------------------------------------------------------------------
    wire [BITS-1:0]      core_raw;
    wire                 core_valid, core_done, core_busy, core_locked;
    wire [7:0]           core_error;
    wire [2*BITS*CW-1:0] core_counts;
    wire                 core_rst_n = rst_n && !clear_pulse;

    ro_puf_core_v2 #(.BITS(BITS),.CW(CW),.WINDOW(WINDOW),
        .RO_DEADLINE(RO_DEADLINE),.CORE_DEADLINE(CORE_DEADLINE)) sampler (
        .clk(clk),.ro_clk(clk),.rst_n(core_rst_n),.start(start_pulse),.osc(osc),
        .raw(core_raw),.valid(core_valid),.done(core_done),.busy(core_busy),
        .error_code(core_error),.locked(core_locked),.transaction_id(),
        .diagnostic_counts(core_counts));

    reg        dna_start, dna_started;
    wire       dna_valid;
    wire [56:0] dna_wire;
    reg [56:0] dna;
    reg        dna_ready;

    device_dna #(.SIM_DNA(SIM_DNA),.SHIFT_SKIP(SHIFT_SKIP)) dna_reader (
        .clk(clk),.rst_n(rst_n),.start(dna_start),.dna(dna_wire),.valid(dna_valid));

    // -------------------------------------------------------------------------
    // 事务号：在寄存器层维护，CLEAR 不复位（CLEAR 会复位采样器核，导致核内
    // transaction_id 回零；驱动需要"跨 CLEAR 仍单调"的序号来区分采样的新鲜度）。
    // 只由模块复位 rst_n 归零；每个 START 脉冲 +1。
    // -------------------------------------------------------------------------
    reg [31:0] txn_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) txn_r <= 32'h0;
        else if (start_pulse) txn_r <= txn_r + 32'h1;
    end

    // -------------------------------------------------------------------------
    // 粘滞状态：done/valid/raw/error 由采样器 1 拍脉冲转成可轮询状态
    // -------------------------------------------------------------------------
    reg              done_r, valid_r;
    reg [BITS-1:0]   raw_r;
    reg [7:0]        error_r;

    wire ctrl_cycle = start_pulse | clear_pulse;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            done_r <= 1'b0; valid_r <= 1'b0; raw_r <= 0; error_r <= 0;
        end else if (ctrl_cycle) begin
            done_r <= 1'b0; valid_r <= 1'b0; raw_r <= 0; error_r <= 0;
        end else if (core_done) begin
            done_r  <= 1'b1;
            valid_r <= core_valid;
            raw_r   <= core_valid ? core_raw : {BITS{1'b0}};
            error_r <= core_error;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dna_start <= 1'b0; dna_started <= 1'b0; dna_ready <= 1'b0; dna <= 0;
        end else begin
            dna_start <= 1'b0;
            if (!dna_started) begin dna_start <= 1'b1; dna_started <= 1'b1; end
            if (dna_valid) begin dna <= dna_wire; dna_ready <= 1'b1; end
        end
    end

    // -------------------------------------------------------------------------
    // 读回多路选择（寄存器化前组合，仍在同一拍内完成）
    // -------------------------------------------------------------------------
    // 诊断计数回读：先按 32 位对齐打包，再对打包视图做 cnt_sel*32 的变量切片。
    // 直接对 5120 位向量切 cnt_sel*CW（=*20）会被综合器展开成大量比较器：
    // 实测 OOC 综合 18170 LUT / 14754 FF（data/advanced/puf_min/impl_20261030_115206）。
    // 打包后下标乘法退化为移位，综合成标准 256:1 mux 树。
    // 打包用的下标都是常量，不产生额外逻辑；每个槽高 12 位不驱动也不被读取。
    wire [32*(2*BITS)-1:0] counts_packed;
    genvar gc;
    generate for (gc = 0; gc < 2*BITS; gc = gc + 1) begin: pack_counts
        assign counts_packed[gc*32 +: CW] = core_counts[gc*CW +: CW];
    end endgenerate
    wire [CW-1:0] cnt_word = counts_packed[cnt_sel*32 +: CW];

    reg [31:0] rd_mux;
    reg        rd_legal;
    always @(*) begin
        rd_mux = 32'h0;
        rd_legal = 1'b1;
        if (s_axi_araddr[1:0] != 2'b00) rd_legal = 1'b0;
        else case (s_axi_araddr[11:2])
            10'h000: rd_mux = ID_VALUE;
            10'h001: rd_mux = VER_VALUE;
            10'h003: rd_mux = {27'b0, dna_ready, core_locked, valid_r, done_r, core_busy};
            10'h004: rd_mux = {24'b0, error_r};
            10'h005: rd_mux = txn_r;
            10'h008: rd_mux = valid_r ? raw_r[31:0]   : 32'h0;
            10'h009: rd_mux = valid_r ? raw_r[63:32]  : 32'h0;
            10'h00a: rd_mux = valid_r ? raw_r[95:64]  : 32'h0;
            10'h00b: rd_mux = valid_r ? raw_r[127:96] : 32'h0;
            10'h00c: rd_mux = dna[31:0];
            10'h00d: rd_mux = {7'b0, dna[56:32]};
            10'h011: rd_mux = valid_r ? {{(32-CW){1'b0}}, cnt_word} : 32'h0;
            default: begin rd_mux = 32'h0; rd_legal = 1'b0; end
        endcase
    end

    reg wr_legal;
    always @(*) begin
        wr_legal = 1'b1;
        if (s_axi_awaddr[1:0] != 2'b00) wr_legal = 1'b0;
        else case (s_axi_awaddr[11:2])
            10'h002, 10'h010: wr_legal = 1'b1;   // CTRL / CNT_SEL
            default:          wr_legal = 1'b0;   // 只读或未映射
        endcase
    end

    // -------------------------------------------------------------------------
    // AXI4-Lite 写通道
    // -------------------------------------------------------------------------
    reg        aw_done, w_done;
    reg [11:0] awaddr_r;
    reg [31:0] wdata_r;
    reg [3:0]  wstrb_r;
    reg        bvalid_r;
    reg [1:0]  bresp_r;

    wire       do_write = aw_done && w_done;

    assign s_axi_awready = ~aw_done & ~bvalid_r;
    assign s_axi_wready  = ~w_done  & ~bvalid_r;
    assign s_axi_bvalid  = bvalid_r;
    assign s_axi_bresp   = bresp_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_done <= 1'b0; w_done <= 1'b0; awaddr_r <= 12'h0;
            wdata_r <= 32'h0; wstrb_r <= 4'h0; bvalid_r <= 1'b0; bresp_r <= OKAY;
        end else begin
            if (s_axi_awvalid && s_axi_awready) begin
                awaddr_r <= s_axi_awaddr; aw_done <= 1'b1;
            end
            if (s_axi_wvalid && s_axi_wready) begin
                wdata_r <= s_axi_wdata; wstrb_r <= s_axi_wstrb; w_done <= 1'b1;
            end
            if (do_write) begin
                aw_done  <= 1'b0;
                w_done   <= 1'b0;
                bvalid_r <= 1'b1;
                bresp_r  <= wr_legal ? OKAY : SLVERR;
            end else if (bvalid_r && s_axi_bready) begin
                bvalid_r <= 1'b0;
            end
        end
    end

    // 写生效：与上面的握手同一拍判定，写寄存器在下一拍可见。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            start_pulse <= 1'b0; clear_pulse <= 1'b0; cnt_sel <= 8'h0;
        end else begin
            start_pulse <= 1'b0;
            clear_pulse <= 1'b0;
            if (do_write && wr_legal && |wstrb_r) begin
                if (awaddr_r[11:2] == 10'h002) begin
                    // CLEAR 优先于 START，避免"同一拍清状态又启动"的歧义
                    if (wstrb_r[0] && wdata_r[1]) clear_pulse <= 1'b1;
                    else if (wstrb_r[0] && wdata_r[0]) start_pulse <= 1'b1;
                end else if (awaddr_r[11:2] == 10'h010) begin
                    if (wstrb_r[0]) cnt_sel <= wdata_r[7:0];
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // AXI4-Lite 读通道（数据/应答在 AR 握手拍寄存）
    // -------------------------------------------------------------------------
    reg        rvalid_r;
    reg [31:0] rdata_r;
    reg [1:0]  rresp_r;

    assign s_axi_arready = ~rvalid_r;
    assign s_axi_rvalid  = rvalid_r;
    assign s_axi_rdata   = rdata_r;
    assign s_axi_rresp   = rresp_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rvalid_r <= 1'b0; rdata_r <= 32'h0; rresp_r <= OKAY;
        end else if (s_axi_arvalid && s_axi_arready) begin
            rvalid_r <= 1'b1;
            rdata_r  <= rd_legal ? rd_mux : 32'h0;
            rresp_r  <= rd_legal ? OKAY : SLVERR;
        end else if (rvalid_r && s_axi_rready) begin
            rvalid_r <= 1'b0;
        end
    end

endmodule

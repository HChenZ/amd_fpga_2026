`timescale 1ns / 1ps
`include "defines.v"
// =============================================================================
// top_pynq.v  ——  PYNQ overlay 单模块顶层（新增文件，冻结的 top_pl_bram.v 不动）
//
// 两种用法：
//   (a) BD 里只放这一个模块：它把 pynq_ctl + pynq_mbox + pynq_soc 组合起来，
//       对外提供两个 AXI4-Lite 从口（ctl / mb）。仿真/综合都能用，
//       但 .hwh 里一个 module 带两条 MEMRANGE 的解析需要在板上确认。
//   (b) BD 里分别放 pynq_ctl_0 / pynq_mbox_0 / pynq_soc_0 三个模块（推荐，见 readme §6）：
//       hwh 一定有两条独立 MEMRANGE，正好对上 navigator profile 的
//       control / mailbox 两个绑定。此时本文件不参与 BD，只作为独立顶层备用。
//
// 数据通路（两种用法相同）：
//   PS ─AXI-Lite→ pynq_mbox(TX FIFO) ─uart_tx→ pynq_soc.uart_rxd
//   pynq_soc.uart_txd ─uart_rx→ pynq_mbox(RX FIFO) ─AXI-Lite→ PS
//   PS ─AXI-Lite→ pynq_ctl(CTRL[0]) ─3 级同步→ pynq_soc.soc_rst_n
// =============================================================================
module top_pynq #(
    parameter XLEN        = `XLEN,
    parameter RAM_DEPTH   = `RAM_DEPTH,
    parameter INDEX_WIDTH = `INDEX_WIDTH,
    parameter UART_BAUD_CNT_MAX = 16
)(
    input               clk,        // FCLK0 100 MHz
    input               rst_n,      // FCLK_RESET0_N

    // ---------- AXI4-Lite slave: 控制/状态 ----------
    input      [11:0]   s_axi_ctl_awaddr,
    input      [2:0]    s_axi_ctl_awprot,
    input               s_axi_ctl_awvalid,
    output              s_axi_ctl_awready,
    input      [31:0]   s_axi_ctl_wdata,
    input      [3:0]    s_axi_ctl_wstrb,
    input               s_axi_ctl_wvalid,
    output              s_axi_ctl_wready,
    output     [1:0]    s_axi_ctl_bresp,
    output              s_axi_ctl_bvalid,
    input               s_axi_ctl_bready,
    input      [11:0]   s_axi_ctl_araddr,
    input      [2:0]    s_axi_ctl_arprot,
    input               s_axi_ctl_arvalid,
    output              s_axi_ctl_arready,
    output     [31:0]   s_axi_ctl_rdata,
    output     [1:0]    s_axi_ctl_rresp,
    output              s_axi_ctl_rvalid,
    input               s_axi_ctl_rready,

    // ---------- AXI4-Lite slave: 邮箱/字节管道 ----------
    input      [11:0]   s_axi_mb_awaddr,
    input      [2:0]    s_axi_mb_awprot,
    input               s_axi_mb_awvalid,
    output              s_axi_mb_awready,
    input      [31:0]   s_axi_mb_wdata,
    input      [3:0]    s_axi_mb_wstrb,
    input               s_axi_mb_wvalid,
    output              s_axi_mb_wready,
    output     [1:0]    s_axi_mb_bresp,
    output              s_axi_mb_bvalid,
    input               s_axi_mb_bready,
    input      [11:0]   s_axi_mb_araddr,
    input      [2:0]    s_axi_mb_arprot,
    input               s_axi_mb_arvalid,
    output              s_axi_mb_arready,
    output     [31:0]   s_axi_mb_rdata,
    output     [1:0]    s_axi_mb_rresp,
    output              s_axi_mb_rvalid,
    input               s_axi_mb_rready
);

    wire        soc_reset;
    wire [1:0]  soc_button;
    wire [1:0]  soc_led;
    wire        soc_rst_n;
    wire        soc_uart_rxd;
    wire        soc_uart_txd;

    pynq_ctl u_pynq_ctl (
        .clk            (clk),
        .rst_n          (rst_n),
        .s_axi_awaddr   (s_axi_ctl_awaddr),
        .s_axi_awprot   (s_axi_ctl_awprot),
        .s_axi_awvalid  (s_axi_ctl_awvalid),
        .s_axi_awready  (s_axi_ctl_awready),
        .s_axi_wdata    (s_axi_ctl_wdata),
        .s_axi_wstrb    (s_axi_ctl_wstrb),
        .s_axi_wvalid   (s_axi_ctl_wvalid),
        .s_axi_wready   (s_axi_ctl_wready),
        .s_axi_bresp    (s_axi_ctl_bresp),
        .s_axi_bvalid   (s_axi_ctl_bvalid),
        .s_axi_bready   (s_axi_ctl_bready),
        .s_axi_araddr   (s_axi_ctl_araddr),
        .s_axi_arprot   (s_axi_ctl_arprot),
        .s_axi_arvalid  (s_axi_ctl_arvalid),
        .s_axi_arready  (s_axi_ctl_arready),
        .s_axi_rdata    (s_axi_ctl_rdata),
        .s_axi_rresp    (s_axi_ctl_rresp),
        .s_axi_rvalid   (s_axi_ctl_rvalid),
        .s_axi_rready   (s_axi_ctl_rready),
        .soc_reset      (soc_reset),
        .soc_button     (soc_button),
        .soc_led        (soc_led),
        .soc_rst_n      (soc_rst_n)
    );

    pynq_mbox #(
        .CLK_FREQ     (100_000_000),
        .BAUD_CNT_MAX (UART_BAUD_CNT_MAX)
    ) u_pynq_mbox (
        .clk            (clk),
        .rst_n          (rst_n),
        .s_axi_awaddr   (s_axi_mb_awaddr),
        .s_axi_awprot   (s_axi_mb_awprot),
        .s_axi_awvalid  (s_axi_mb_awvalid),
        .s_axi_awready  (s_axi_mb_awready),
        .s_axi_wdata    (s_axi_mb_wdata),
        .s_axi_wstrb    (s_axi_mb_wstrb),
        .s_axi_wvalid   (s_axi_mb_wvalid),
        .s_axi_wready   (s_axi_mb_wready),
        .s_axi_bresp    (s_axi_mb_bresp),
        .s_axi_bvalid   (s_axi_mb_bvalid),
        .s_axi_bready   (s_axi_mb_bready),
        .s_axi_araddr   (s_axi_mb_araddr),
        .s_axi_arprot   (s_axi_mb_arprot),
        .s_axi_arvalid  (s_axi_mb_arvalid),
        .s_axi_arready  (s_axi_mb_arready),
        .s_axi_rdata    (s_axi_mb_rdata),
        .s_axi_rresp    (s_axi_mb_rresp),
        .s_axi_rvalid   (s_axi_mb_rvalid),
        .s_axi_rready   (s_axi_mb_rready),
        .link_flush     (soc_reset),
        .mbox_txd       (soc_uart_rxd),
        .mbox_rxd       (soc_uart_txd)
    );

    pynq_soc #(
        .XLEN             (XLEN),
        .RAM_DEPTH        (RAM_DEPTH),
        .INDEX_WIDTH      (INDEX_WIDTH),
        .UART_BAUD_CNT_MAX(UART_BAUD_CNT_MAX)
    ) u_pynq_soc (
        .clk      (clk),
        .rst_n    (rst_n),
        .soc_rst_n(soc_rst_n),
        .uart_rxd (soc_uart_rxd),
        .uart_txd (soc_uart_txd),
        .button   (soc_button),
        .led      (soc_led)
    );

endmodule

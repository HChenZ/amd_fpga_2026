`timescale 1ns / 1ps
`include "defines.v"

module top_dma #(
    parameter XLEN = `XLEN,
    parameter RAM_DEPTH = `RAM_DEPTH,
    parameter INDEX_WIDTH = `INDEX_WIDTH,
    parameter RAM_INIT_FILE = "",
    parameter UART_CLK_FREQ = 100000000,
    parameter UART_BPS = 115200,
    parameter UART_BAUD_CNT_MAX = UART_CLK_FREQ / UART_BPS,
    parameter UART_RX_FIFO_DEPTH = 16,
    parameter UART_TX_FIFO_DEPTH = 16
)(
    input                       clk,
    input                       rst_n,
    input [63:0] session_epoch,
    input [31:0] s_axis_tdata, input [3:0] s_axis_tkeep,
    input s_axis_tvalid, output s_axis_tready, input s_axis_tlast,
    output [31:0] m_axis_tdata, output [3:0] m_axis_tkeep,
    output m_axis_tvalid, input m_axis_tready, output m_axis_tlast,
    output ready, output busy, output fault,
    output cpu_resetn,

    input                       uart_rxd,
    output                      uart_txd,

    input       [1:0]           button,
    output      [1:0]           led,

    // AXI4 master interface for Vivado Block Design.
    input                       M_AXI_AWREADY,
    output                      M_AXI_AWVALID,
    output      [0:0]           M_AXI_AWID,
    output      [XLEN-1:0]      M_AXI_AWADDR,
    output      [7:0]           M_AXI_AWLEN,
    output      [2:0]           M_AXI_AWSIZE,
    output      [1:0]           M_AXI_AWBURST,
    output                      M_AXI_AWLOCK,
    output      [3:0]           M_AXI_AWCACHE,
    output      [2:0]           M_AXI_AWPROT,
    output      [3:0]           M_AXI_AWQOS,
    output      [3:0]           M_AXI_AWREGION,

    input                       M_AXI_WREADY,
    output                      M_AXI_WVALID,
    output                      M_AXI_WLAST,
    output      [XLEN-1:0]      M_AXI_WDATA,
    output      [XLEN/8-1:0]    M_AXI_WSTRB,

    input                       M_AXI_BVALID,
    input       [0:0]           M_AXI_BID,
    input       [1:0]           M_AXI_BRESP,
    output                      M_AXI_BREADY,

    input                       M_AXI_ARREADY,
    output                      M_AXI_ARVALID,
    output                      M_AXI_ARLOCK,
    output      [0:0]           M_AXI_ARID,
    output      [XLEN-1:0]      M_AXI_ARADDR,
    output      [7:0]           M_AXI_ARLEN,
    output      [2:0]           M_AXI_ARSIZE,
    output      [1:0]           M_AXI_ARBURST,
    output      [3:0]           M_AXI_ARCACHE,
    output      [2:0]           M_AXI_ARPROT,
    output      [3:0]           M_AXI_ARQOS,
    output      [3:0]           M_AXI_ARREGION,

    input                       M_AXI_RVALID,
    input                       M_AXI_RLAST,
    input       [0:0]           M_AXI_RID,
    input       [XLEN-1:0]      M_AXI_RDATA,
    input       [1:0]           M_AXI_RRESP,
    output                      M_AXI_RREADY
);

    wire unused_m_awuser;
    wire unused_m_wuser;
    wire unused_m_aruser;

    wire dma_re, dma_we, cpu_rst_n;
    assign cpu_resetn = cpu_rst_n;
    wire [7:0] dma_addr;
    wire [31:0] dma_wdata, dma_rdata;
    wire [3:0] dma_wstrb;
    dma_cpu_endpoint u_endpoint (
        .clk(clk), .rst_n(rst_n), .session_epoch(session_epoch),
        .s_axis_tdata(s_axis_tdata), .s_axis_tkeep(s_axis_tkeep),
        .s_axis_tvalid(s_axis_tvalid), .s_axis_tready(s_axis_tready), .s_axis_tlast(s_axis_tlast),
        .m_axis_tdata(m_axis_tdata), .m_axis_tkeep(m_axis_tkeep),
        .m_axis_tvalid(m_axis_tvalid), .m_axis_tready(m_axis_tready), .m_axis_tlast(m_axis_tlast),
        .cpu_re(dma_re), .cpu_we(dma_we), .cpu_addr(dma_addr),
        .cpu_wdata(dma_wdata), .cpu_wstrb(dma_wstrb), .cpu_rdata(dma_rdata),
        .cpu_rst_n(cpu_rst_n), .ready(ready), .busy(busy), .fault(fault)
    );

    soc_top_dma #(
        .XLEN(XLEN),
        .RAM_DEPTH(RAM_DEPTH),
        .INDEX_WIDTH(INDEX_WIDTH),
        .UART_CLK_FREQ(UART_CLK_FREQ),
        .UART_BPS(UART_BPS),
        .UART_BAUD_CNT_MAX(UART_BAUD_CNT_MAX),
        .UART_RX_FIFO_DEPTH(UART_RX_FIFO_DEPTH),
        .UART_TX_FIFO_DEPTH(UART_TX_FIFO_DEPTH)
    ) u_soc_top (
        .clk(clk),
        .rst_n(cpu_rst_n),
        .dma_re(dma_re), .dma_we(dma_we), .dma_addr(dma_addr),
        .dma_wdata(dma_wdata), .dma_wstrb(dma_wstrb), .dma_rdata(dma_rdata),
        .uart_rxd(uart_rxd),
        .uart_txd(uart_txd),
        .button(button),
        .led(led),

        .m_awready(M_AXI_AWREADY),
        .m_awvalid(M_AXI_AWVALID),
        .m_awid(M_AXI_AWID[0]),
        .m_awaddr(M_AXI_AWADDR),
        .m_awlen(M_AXI_AWLEN),
        .m_awsize(M_AXI_AWSIZE),
        .m_awburst(M_AXI_AWBURST),
        .m_awlock(M_AXI_AWLOCK),
        .m_awcache(M_AXI_AWCACHE),
        .m_awprot(M_AXI_AWPROT),
        .m_awqos(M_AXI_AWQOS),
        .m_awregion(M_AXI_AWREGION),
        .m_awuser(unused_m_awuser),

        .m_wready(M_AXI_WREADY),
        .m_wvalid(M_AXI_WVALID),
        .m_wlast(M_AXI_WLAST),
        .m_wdata(M_AXI_WDATA),
        .m_wstrb(M_AXI_WSTRB),
        .m_wuser(unused_m_wuser),

        .m_bvalid(M_AXI_BVALID),
        .m_bid(M_AXI_BID[0]),
        .m_bresp(M_AXI_BRESP),
        .m_buser(1'b0),
        .m_bready(M_AXI_BREADY),

        .m_arready(M_AXI_ARREADY),
        .m_arvalid(M_AXI_ARVALID),
        .m_arlock(M_AXI_ARLOCK),
        .m_arid(M_AXI_ARID[0]),
        .m_araddr(M_AXI_ARADDR),
        .m_arlen(M_AXI_ARLEN),
        .m_arsize(M_AXI_ARSIZE),
        .m_arburst(M_AXI_ARBURST),
        .m_arcache(M_AXI_ARCACHE),
        .m_arprot(M_AXI_ARPROT),
        .m_arqos(M_AXI_ARQOS),
        .m_arregion(M_AXI_ARREGION),
        .m_aruser(unused_m_aruser),

        .m_rvalid(M_AXI_RVALID),
        .m_rlast(M_AXI_RLAST),
        .m_rid(M_AXI_RID[0]),
        .m_rdata(M_AXI_RDATA),
        .m_rresp(M_AXI_RRESP),
        .m_ruser(1'b0),
        .m_rready(M_AXI_RREADY)
    );

endmodule

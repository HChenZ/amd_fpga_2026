`timescale 1ns / 1ps
`include "defines.v"

module top_pl_bram #(
    parameter XLEN = `XLEN,
    parameter RAM_DEPTH = `RAM_DEPTH,
    parameter INDEX_WIDTH = `INDEX_WIDTH,
    parameter RESET_ACTIVE_LOW = 1,
    parameter [XLEN-1:0] BRAM_BASE_ADDR = 32'h1000_0000,
    parameter BRAM_ADDR_WIDTH = 15,
    parameter BRAM_ADDR_LSB = (XLEN == 64) ? 3 : 2,
    parameter AXI_BRAM_ADDR_WIDTH = BRAM_ADDR_WIDTH + BRAM_ADDR_LSB
)(
    input                       clk,
    input                       reset_btn,

    input                       uart_rxd,
    output                      uart_txd,

    input       [1:0]           button,
    output      [1:0]           led
);

    wire rst_n_raw = RESET_ACTIVE_LOW ? reset_btn : ~reset_btn;
    wire clk_100m;
    wire clk_locked;

    clk_wiz_0 u_clk_wiz_0 (
        .clk_in1(clk),
        .reset(~rst_n_raw),
        .clk_out1(clk_100m),
        .locked(clk_locked)
    );

    reg [2:0] rst_sync;
    always @(posedge clk_100m or negedge rst_n_raw) begin
        if (!rst_n_raw)
            rst_sync <= 3'b000;
        else if (!clk_locked)
            rst_sync <= 3'b000;
        else
            rst_sync <= {rst_sync[1:0], 1'b1};
    end

    wire rst_n = rst_sync[2];

    wire                      m_awready;
    wire                      m_awvalid;
    wire      [0:0]           m_awid;
    wire      [XLEN-1:0]      m_awaddr;
    wire      [7:0]           m_awlen;
    wire      [2:0]           m_awsize;
    wire      [1:0]           m_awburst;
    wire                      m_awlock;
    wire      [3:0]           m_awcache;
    wire      [2:0]           m_awprot;
    wire      [3:0]           m_awqos;
    wire      [3:0]           m_awregion;

    wire                      m_wready;
    wire                      m_wvalid;
    wire                      m_wlast;
    wire      [XLEN-1:0]      m_wdata;
    wire      [XLEN/8-1:0]    m_wstrb;

    wire                      m_bvalid;
    wire      [0:0]           m_bid;
    wire      [1:0]           m_bresp;
    wire                      m_bready;

    wire                      m_arready;
    wire                      m_arvalid;
    wire                      m_arlock;
    wire      [0:0]           m_arid;
    wire      [XLEN-1:0]      m_araddr;
    wire      [7:0]           m_arlen;
    wire      [2:0]           m_arsize;
    wire      [1:0]           m_arburst;
    wire      [3:0]           m_arcache;
    wire      [2:0]           m_arprot;
    wire      [3:0]           m_arqos;
    wire      [3:0]           m_arregion;

    wire                      m_rvalid;
    wire                      m_rlast;
    wire      [0:0]           m_rid;
    wire      [XLEN-1:0]      m_rdata;
    wire      [1:0]           m_rresp;
    wire                      m_rready;

    wire [XLEN-1:0]           bram_axi_awaddr = m_awaddr - BRAM_BASE_ADDR;
    wire [XLEN-1:0]           bram_axi_araddr = m_araddr - BRAM_BASE_ADDR;

    wire                      bram_rst_a;
    wire                      bram_clk_a;
    wire                      bram_en_a;
    wire      [XLEN/8-1:0]    bram_we_a;
    wire      [AXI_BRAM_ADDR_WIDTH-1:0] bram_addr_a;
    wire      [XLEN-1:0]      bram_wrdata_a;
    wire      [XLEN-1:0]      bram_rddata_a;

    top #(
        .XLEN(XLEN),
        .RAM_DEPTH(RAM_DEPTH),
        .INDEX_WIDTH(INDEX_WIDTH)
    ) u_soc_axi_top (
        .clk(clk_100m),
        .rst_n(rst_n),

        .uart_rxd(uart_rxd),
        .uart_txd(uart_txd),

        .button(button),
        .led(led),

        .M_AXI_AWREADY(m_awready),
        .M_AXI_AWVALID(m_awvalid),
        .M_AXI_AWID(m_awid),
        .M_AXI_AWADDR(m_awaddr),
        .M_AXI_AWLEN(m_awlen),
        .M_AXI_AWSIZE(m_awsize),
        .M_AXI_AWBURST(m_awburst),
        .M_AXI_AWLOCK(m_awlock),
        .M_AXI_AWCACHE(m_awcache),
        .M_AXI_AWPROT(m_awprot),
        .M_AXI_AWQOS(m_awqos),
        .M_AXI_AWREGION(m_awregion),

        .M_AXI_WREADY(m_wready),
        .M_AXI_WVALID(m_wvalid),
        .M_AXI_WLAST(m_wlast),
        .M_AXI_WDATA(m_wdata),
        .M_AXI_WSTRB(m_wstrb),

        .M_AXI_BVALID(m_bvalid),
        .M_AXI_BID(m_bid),
        .M_AXI_BRESP(m_bresp),
        .M_AXI_BREADY(m_bready),

        .M_AXI_ARREADY(m_arready),
        .M_AXI_ARVALID(m_arvalid),
        .M_AXI_ARLOCK(m_arlock),
        .M_AXI_ARID(m_arid),
        .M_AXI_ARADDR(m_araddr),
        .M_AXI_ARLEN(m_arlen),
        .M_AXI_ARSIZE(m_arsize),
        .M_AXI_ARBURST(m_arburst),
        .M_AXI_ARCACHE(m_arcache),
        .M_AXI_ARPROT(m_arprot),
        .M_AXI_ARQOS(m_arqos),
        .M_AXI_ARREGION(m_arregion),

        .M_AXI_RVALID(m_rvalid),
        .M_AXI_RLAST(m_rlast),
        .M_AXI_RID(m_rid),
        .M_AXI_RDATA(m_rdata),
        .M_AXI_RRESP(m_rresp),
        .M_AXI_RREADY(m_rready)
    );

    axi_bram_ctrl_0 u_axi_bram_ctrl_0 (
        .s_axi_aclk(clk_100m),
        .s_axi_aresetn(rst_n),

        .s_axi_awid(m_awid),
        .s_axi_awaddr(bram_axi_awaddr),
        .s_axi_awlen(m_awlen),
        .s_axi_awsize(m_awsize),
        .s_axi_awburst(m_awburst),
        .s_axi_awlock(m_awlock),
        .s_axi_awcache(m_awcache),
        .s_axi_awprot(m_awprot),
        .s_axi_awvalid(m_awvalid),
        .s_axi_awready(m_awready),

        .s_axi_wdata(m_wdata),
        .s_axi_wstrb(m_wstrb),
        .s_axi_wlast(m_wlast),
        .s_axi_wvalid(m_wvalid),
        .s_axi_wready(m_wready),

        .s_axi_bid(m_bid),
        .s_axi_bresp(m_bresp),
        .s_axi_bvalid(m_bvalid),
        .s_axi_bready(m_bready),

        .s_axi_arid(m_arid),
        .s_axi_araddr(bram_axi_araddr),
        .s_axi_arlen(m_arlen),
        .s_axi_arsize(m_arsize),
        .s_axi_arburst(m_arburst),
        .s_axi_arlock(m_arlock),
        .s_axi_arcache(m_arcache),
        .s_axi_arprot(m_arprot),
        .s_axi_arvalid(m_arvalid),
        .s_axi_arready(m_arready),

        .s_axi_rid(m_rid),
        .s_axi_rdata(m_rdata),
        .s_axi_rresp(m_rresp),
        .s_axi_rlast(m_rlast),
        .s_axi_rvalid(m_rvalid),
        .s_axi_rready(m_rready),

        .bram_rst_a(bram_rst_a),
        .bram_clk_a(bram_clk_a),
        .bram_en_a(bram_en_a),
        .bram_we_a(bram_we_a),
        .bram_addr_a(bram_addr_a),
        .bram_wrdata_a(bram_wrdata_a),
        .bram_rddata_a(bram_rddata_a)
    );

    blk_mem_gen_0 u_blk_mem_gen_0 (
        .clka(bram_clk_a),
        .rsta(bram_rst_a),
        .ena(bram_en_a),
        .wea(bram_we_a),
        .addra(bram_addr_a[BRAM_ADDR_LSB + BRAM_ADDR_WIDTH - 1:BRAM_ADDR_LSB]),
        .dina(bram_wrdata_a),
        .douta(bram_rddata_a)
    );

endmodule

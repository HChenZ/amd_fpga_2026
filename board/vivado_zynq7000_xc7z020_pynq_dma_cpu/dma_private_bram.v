`timescale 1ns/1ps
// Private RV32 program/data memory. Same XCI instances and byte->word address
// mapping as production pynq_soc, isolated here for the DMA experiment.
module dma_private_bram (
    (* X_INTERFACE_INFO="xilinx.com:signal:clock:1.0 clk CLK", X_INTERFACE_PARAMETER="XIL_INTERFACENAME clk, ASSOCIATED_BUSIF S_AXI, ASSOCIATED_RESET rst_n" *) input clk,
    (* X_INTERFACE_INFO="xilinx.com:signal:reset:1.0 rst_n RST", X_INTERFACE_PARAMETER="POLARITY ACTIVE_LOW" *) input rst_n,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI AWADDR" *) input [31:0] s_axi_awaddr,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI AWID" *) input [0:0] s_axi_awid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI AWLEN" *) input [7:0] s_axi_awlen,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI AWSIZE" *) input [2:0] s_axi_awsize,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI AWBURST" *) input [1:0] s_axi_awburst,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI AWLOCK" *) input s_axi_awlock,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI AWCACHE" *) input [3:0] s_axi_awcache,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI AWPROT" *) input [2:0] s_axi_awprot,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI AWVALID" *) input s_axi_awvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI AWREADY" *) output s_axi_awready,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI WDATA" *) input [31:0] s_axi_wdata,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI WSTRB" *) input [3:0] s_axi_wstrb,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI WLAST" *) input s_axi_wlast,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI WVALID" *) input s_axi_wvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI WREADY" *) output s_axi_wready,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI BID" *) output [0:0] s_axi_bid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI BRESP" *) output [1:0] s_axi_bresp,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI BVALID" *) output s_axi_bvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI BREADY" *) input s_axi_bready,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI ARADDR" *) input [31:0] s_axi_araddr,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI ARID" *) input [0:0] s_axi_arid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI ARLEN" *) input [7:0] s_axi_arlen,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI ARSIZE" *) input [2:0] s_axi_arsize,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI ARBURST" *) input [1:0] s_axi_arburst,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI ARLOCK" *) input s_axi_arlock,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI ARCACHE" *) input [3:0] s_axi_arcache,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI ARPROT" *) input [2:0] s_axi_arprot,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI ARVALID" *) input s_axi_arvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI ARREADY" *) output s_axi_arready,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI RID" *) output [0:0] s_axi_rid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI RDATA" *) output [31:0] s_axi_rdata,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI RRESP" *) output [1:0] s_axi_rresp,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI RLAST" *) output s_axi_rlast,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI RVALID" *) output s_axi_rvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI RREADY" *) input s_axi_rready
);
    wire [31:0] local_awaddr=s_axi_awaddr-32'h10000000;
    wire [31:0] local_araddr=s_axi_araddr-32'h10000000;
    wire bram_rst,bram_clk,bram_en;
    wire [3:0] bram_we;
    wire [16:0] bram_addr;
    wire [31:0] bram_din,bram_dout;
    axi_bram_ctrl_0 controller (
        .s_axi_aclk(clk),.s_axi_aresetn(rst_n),
        .s_axi_awid(s_axi_awid),.s_axi_awaddr(local_awaddr),.s_axi_awlen(s_axi_awlen),
        .s_axi_awsize(s_axi_awsize),.s_axi_awburst(s_axi_awburst),.s_axi_awlock(s_axi_awlock),
        .s_axi_awcache(s_axi_awcache),.s_axi_awprot(s_axi_awprot),.s_axi_awvalid(s_axi_awvalid),.s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata),.s_axi_wstrb(s_axi_wstrb),.s_axi_wlast(s_axi_wlast),.s_axi_wvalid(s_axi_wvalid),.s_axi_wready(s_axi_wready),
        .s_axi_bid(s_axi_bid),.s_axi_bresp(s_axi_bresp),.s_axi_bvalid(s_axi_bvalid),.s_axi_bready(s_axi_bready),
        .s_axi_arid(s_axi_arid),.s_axi_araddr(local_araddr),.s_axi_arlen(s_axi_arlen),
        .s_axi_arsize(s_axi_arsize),.s_axi_arburst(s_axi_arburst),.s_axi_arlock(s_axi_arlock),
        .s_axi_arcache(s_axi_arcache),.s_axi_arprot(s_axi_arprot),.s_axi_arvalid(s_axi_arvalid),.s_axi_arready(s_axi_arready),
        .s_axi_rid(s_axi_rid),.s_axi_rdata(s_axi_rdata),.s_axi_rresp(s_axi_rresp),.s_axi_rlast(s_axi_rlast),
        .s_axi_rvalid(s_axi_rvalid),.s_axi_rready(s_axi_rready),
        .bram_rst_a(bram_rst),.bram_clk_a(bram_clk),.bram_en_a(bram_en),.bram_we_a(bram_we),
        .bram_addr_a(bram_addr),.bram_wrdata_a(bram_din),.bram_rddata_a(bram_dout));
    blk_mem_gen_0 memory (.clka(bram_clk),.rsta(bram_rst),.ena(bram_en),.wea(bram_we),
                          .addra(bram_addr[16:2]),.dina(bram_din),.douta(bram_dout));
endmodule

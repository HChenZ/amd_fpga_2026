`timescale 1ns / 1ps
// =============================================================================
// ip_stubs.v —— 仅用于 iverilog 的 Xilinx IP 空壳（仿真替身，不是工程 IP 配置）
//
// 目的：让 top_pynq / pynq_soc 的 40 多根 AXI 连线能被 iverilog **完整 elaborate**，
//       从而在不开 Vivado 的情况下抓出端口名/位宽错误。
//       这里不含任何功能：BRAM 读数据恒 0、永远 ready，只能证明"接得上"。
//       真正的功能验证在 pynq_soc 之外：tb_pynq_bridge.v 覆盖两个桥，
//       上板由 Vivado 工程 + PYNQ 覆盖。
// =============================================================================
module axi_bram_ctrl_0 (
    input               s_axi_aclk,
    input               s_axi_aresetn,

    input       [0:0]   s_axi_awid,
    input      [31:0]   s_axi_awaddr,
    input       [7:0]   s_axi_awlen,
    input       [2:0]   s_axi_awsize,
    input       [1:0]   s_axi_awburst,
    input               s_axi_awlock,
    input       [3:0]   s_axi_awcache,
    input       [2:0]   s_axi_awprot,
    input               s_axi_awvalid,
    output              s_axi_awready,

    input      [31:0]   s_axi_wdata,
    input       [3:0]   s_axi_wstrb,
    input               s_axi_wlast,
    input               s_axi_wvalid,
    output              s_axi_wready,

    output      [0:0]   s_axi_bid,
    output      [1:0]   s_axi_bresp,
    output              s_axi_bvalid,
    input               s_axi_bready,

    input       [0:0]   s_axi_arid,
    input      [31:0]   s_axi_araddr,
    input       [7:0]   s_axi_arlen,
    input       [2:0]   s_axi_arsize,
    input       [1:0]   s_axi_arburst,
    input               s_axi_arlock,
    input       [3:0]   s_axi_arcache,
    input       [2:0]   s_axi_arprot,
    input               s_axi_arvalid,
    output              s_axi_arready,

    output      [0:0]   s_axi_rid,
    output     [31:0]   s_axi_rdata,
    output      [1:0]   s_axi_rresp,
    output              s_axi_rlast,
    output              s_axi_rvalid,
    input               s_axi_rready,

    output              bram_rst_a,
    output              bram_clk_a,
    output              bram_en_a,
    output      [3:0]   bram_we_a,
    output     [16:0]   bram_addr_a,
    output     [31:0]   bram_wrdata_a,
    input      [31:0]   bram_rddata_a
);
    assign s_axi_awready = 1'b1;
    assign s_axi_wready  = 1'b1;
    assign s_axi_bvalid  = 1'b0;
    assign s_axi_bid     = 1'b0;
    assign s_axi_bresp   = 2'b00;
    assign s_axi_arready = 1'b1;
    assign s_axi_rvalid  = 1'b0;
    assign s_axi_rid     = 1'b0;
    assign s_axi_rdata   = 32'h0;
    assign s_axi_rresp   = 2'b00;
    assign s_axi_rlast   = 1'b0;

    assign bram_rst_a    = ~s_axi_aresetn;
    assign bram_clk_a    = s_axi_aclk;
    assign bram_en_a     = 1'b0;
    assign bram_we_a     = 4'h0;
    assign bram_addr_a   = 17'h0;
    assign bram_wrdata_a = 32'h0;
endmodule

module blk_mem_gen_0 (
    input               clka,
    input               rsta,
    input               ena,
    input       [3:0]   wea,
    input      [14:0]   addra,
    input      [31:0]   dina,
    output     [31:0]   douta
);
    assign douta = 32'h0;
endmodule

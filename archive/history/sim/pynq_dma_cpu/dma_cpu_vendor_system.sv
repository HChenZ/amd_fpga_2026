`timescale 1ns/1ps
// Simulation-only wiring of the actual board CPU/control wrapper and vendor RAM.
module dma_cpu_vendor_system(
 input clk,input rst_n,
 input [31:0] s_axis_tdata,input [3:0] s_axis_tkeep,input s_axis_tvalid,
 output s_axis_tready,input s_axis_tlast,
 output [31:0] m_axis_tdata,output [3:0] m_axis_tkeep,output m_axis_tvalid,
 input m_axis_tready,output m_axis_tlast,output ready,output fault);
 wire busy,cpu_resetn;
 reg [7:0] s_axi_awaddr=0,s_axi_araddr=0;
 reg s_axi_awvalid=0,s_axi_wvalid=0,s_axi_bready=0,s_axi_arvalid=0,s_axi_rready=0;
 reg [31:0] s_axi_wdata=0;
 wire [3:0] s_axi_wstrb=15;
 wire s_axi_awready,s_axi_wready,s_axi_bvalid,s_axi_arready,s_axi_rvalid;
 wire [1:0] s_axi_bresp,s_axi_rresp;
 wire [31:0] s_axi_rdata;
 wire M_AXI_AWREADY,M_AXI_AWVALID,M_AXI_WREADY,M_AXI_WVALID,M_AXI_WLAST;
 wire M_AXI_BVALID,M_AXI_BREADY,M_AXI_ARREADY,M_AXI_ARVALID,M_AXI_RVALID,M_AXI_RLAST,M_AXI_RREADY;
 wire [0:0] M_AXI_AWID,M_AXI_BID,M_AXI_ARID,M_AXI_RID;
 wire [31:0] M_AXI_AWADDR,M_AXI_WDATA,M_AXI_ARADDR,M_AXI_RDATA;
 wire [7:0] M_AXI_AWLEN,M_AXI_ARLEN;
 wire [2:0] M_AXI_AWSIZE,M_AXI_ARSIZE,M_AXI_AWPROT,M_AXI_ARPROT;
 wire [1:0] M_AXI_AWBURST,M_AXI_ARBURST,M_AXI_BRESP,M_AXI_RRESP;
 wire M_AXI_AWLOCK,M_AXI_ARLOCK;
 wire [3:0] M_AXI_AWCACHE,M_AXI_AWQOS,M_AXI_AWREGION,M_AXI_WSTRB;
 wire [3:0] M_AXI_ARCACHE,M_AXI_ARQOS,M_AXI_ARREGION;
 pynq_dma_cpu core(.uart_rxd(1'b1),.uart_txd(),.button(2'b0),.led(),.*);
 dma_private_bram ram(.clk(clk),.rst_n(cpu_resetn),
 .s_axi_awaddr(M_AXI_AWADDR),.s_axi_awid(M_AXI_AWID),.s_axi_awlen(M_AXI_AWLEN),
 .s_axi_awsize(M_AXI_AWSIZE),.s_axi_awburst(M_AXI_AWBURST),.s_axi_awlock(M_AXI_AWLOCK),
 .s_axi_awcache(M_AXI_AWCACHE),.s_axi_awprot(M_AXI_AWPROT),.s_axi_awvalid(M_AXI_AWVALID),.s_axi_awready(M_AXI_AWREADY),
 .s_axi_wdata(M_AXI_WDATA),.s_axi_wstrb(M_AXI_WSTRB),.s_axi_wlast(M_AXI_WLAST),.s_axi_wvalid(M_AXI_WVALID),.s_axi_wready(M_AXI_WREADY),
 .s_axi_bid(M_AXI_BID),.s_axi_bresp(M_AXI_BRESP),.s_axi_bvalid(M_AXI_BVALID),.s_axi_bready(M_AXI_BREADY),
 .s_axi_araddr(M_AXI_ARADDR),.s_axi_arid(M_AXI_ARID),.s_axi_arlen(M_AXI_ARLEN),
 .s_axi_arsize(M_AXI_ARSIZE),.s_axi_arburst(M_AXI_ARBURST),.s_axi_arlock(M_AXI_ARLOCK),
 .s_axi_arcache(M_AXI_ARCACHE),.s_axi_arprot(M_AXI_ARPROT),.s_axi_arvalid(M_AXI_ARVALID),.s_axi_arready(M_AXI_ARREADY),
 .s_axi_rid(M_AXI_RID),.s_axi_rdata(M_AXI_RDATA),.s_axi_rresp(M_AXI_RRESP),.s_axi_rlast(M_AXI_RLAST),
 .s_axi_rvalid(M_AXI_RVALID),.s_axi_rready(M_AXI_RREADY));
 task wrctl(input [7:0] a,input [31:0] value);
 reg adone,wdone;
 begin
  @(negedge clk);s_axi_awaddr=a;s_axi_wdata=value;s_axi_awvalid=1;s_axi_wvalid=1;adone=0;wdone=0;
  while(!adone||!wdone)begin
   @(posedge clk);if(s_axi_awvalid&&s_axi_awready)adone=1;if(s_axi_wvalid&&s_axi_wready)wdone=1;
   @(negedge clk);if(adone)s_axi_awvalid=0;if(wdone)s_axi_wvalid=0;
  end
  while(!s_axi_bvalid)@(negedge clk);
  if(s_axi_bresp!=0)$fatal(1,"CPU control write failed");
  s_axi_bready=1;@(negedge clk);s_axi_bready=0;
 end endtask
 task rdctl(input [7:0] a,input [31:0] expected);
 begin
  @(negedge clk);s_axi_araddr=a;s_axi_arvalid=1;
  @(posedge clk);while(!s_axi_arready)@(posedge clk);
  @(negedge clk);s_axi_arvalid=0;while(!s_axi_rvalid)@(negedge clk);
  if(s_axi_rresp!=0 || s_axi_rdata!==expected)$fatal(1,"CPU control read a=%h got=%h expected=%h",a,s_axi_rdata,expected);
  s_axi_rready=1;@(negedge clk);s_axi_rready=0;
 end endtask
 initial begin
  wait(rst_n);repeat(4)@(negedge clk);
  rdctl(0,32'h32414d44);rdctl(4,2);rdctl('h1c,7);
  rdctl('h30,32);rdctl('h38,16);rdctl('h40,32);rdctl('h48,0);
  wrctl(8,1);wrctl('h0c,1);wrctl('h10,0);wrctl(8,0);
 end
endmodule

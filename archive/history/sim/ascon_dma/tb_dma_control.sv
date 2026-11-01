`timescale 1ns/1ps
module tb_dma_control;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0;
 reg [11:0] aw=0,ar=0;reg [31:0] wd=0;reg[3:0] ws=0;
 reg av=0,wv=0,br=0,arv=0,rr=0;wire ary,awy,wy,bv,rv;wire[31:0]rd;wire[1:0]bp,rp;
 wire sr,mv,ml;wire[31:0]md;wire[3:0]mk;
 integer checks=0;
 dma_direct_top dut(.clk(clk),.rst_n(rst_n),
 .s_axi_awaddr(aw),.s_axi_awprot(3'b0),.s_axi_awvalid(av),.s_axi_awready(awy),
 .s_axi_wdata(wd),.s_axi_wstrb(ws),.s_axi_wvalid(wv),.s_axi_wready(wy),
 .s_axi_bresp(bp),.s_axi_bvalid(bv),.s_axi_bready(br),
 .s_axi_araddr(ar),.s_axi_arprot(3'b0),.s_axi_arvalid(arv),.s_axi_arready(ary),
 .s_axi_rdata(rd),.s_axi_rresp(rp),.s_axi_rvalid(rv),.s_axi_rready(rr),
 .s_axis_tdata(32'b0),.s_axis_tkeep(4'b0),.s_axis_tvalid(1'b0),.s_axis_tready(sr),.s_axis_tlast(1'b0),
 .m_axis_tdata(md),.m_axis_tkeep(mk),.m_axis_tvalid(mv),.m_axis_tready(1'b1),.m_axis_tlast(ml));
 task address(input[11:0]a);begin @(negedge clk);aw=a;av=1;@(posedge clk);while(!awy)@(posedge clk);@(negedge clk);av=0;end endtask
 task data(input[31:0]v,input[3:0]s);begin @(negedge clk);wd=v;ws=s;wv=1;@(posedge clk);while(!wy)@(posedge clk);@(negedge clk);wv=0;end endtask
 task write_reg(input[11:0]a,input[31:0]v,input[3:0]s,input integer order);begin
   if(order==0)begin address(a);repeat(3)@(negedge clk);data(v,s);end
   else begin data(v,s);repeat(3)@(negedge clk);address(a);end
   while(!bv)@(negedge clk);
   repeat(3)begin @(negedge clk);if(!bv||bp!=0)$fatal(1,"write response unstable");end
   br=1;@(negedge clk);br=0;
 end endtask
 task read_check(input[11:0]a,input[31:0]v);begin
   @(negedge clk);ar=a;arv=1;@(posedge clk);while(!ary)@(posedge clk);@(negedge clk);arv=0;
   while(!rv)@(negedge clk);
   repeat(3)begin if(!rv||rd!==v||rp!=0)$fatal(1,"read %h got %h expected %h",a,rd,v);@(negedge clk);end
   rr=1;@(negedge clk);rr=0;checks=checks+1;
 end endtask
 initial begin
  repeat(4)@(negedge clk);rst_n=1;
  read_check(0,32'h32414d44);read_check(4,2);read_check(8,1);read_check('h14,1024);read_check('h1c,8);
  read_check('h30,0);read_check('h48,1024);read_check('h4c,1024);
  write_reg('hc,32'h11223344,15,0);write_reg('h10,32'h55667788,15,1);
  read_check('hc,32'h11223344);read_check('h10,32'h55667788);
  write_reg('hc,32'haabbccdd,4'b0101,1);read_check('hc,32'h11bb33dd);
  write_reg(8,0,0,0);read_check(8,1); // disabled byte strobe cannot release reset
  write_reg(8,0,1,1);read_check(8,0);
  repeat(1600)@(negedge clk);if(!sr||mv)$fatal(1,"engine not ready after scrub");read_check('h20,1);
  write_reg('hc,0,15,0);read_check('hc,32'h11bb33dd); // epoch immutable while active
  write_reg(8,1,1,0);read_check(8,1);
  @(negedge clk);rst_n=0;repeat(3)@(negedge clk);rst_n=1;read_check('hc,0);read_check(8,1);
  $display("TEST_PASS dma_control checks=%0d AW/W reorder, WSTRB, read/write backpressure, epoch/reset",checks);$finish;
 end
 initial begin #1000000;$fatal(1,"control watchdog");end
endmodule

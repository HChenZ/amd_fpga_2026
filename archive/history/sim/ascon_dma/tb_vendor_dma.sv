`timescale 1ns/1ps
// Real generated AXI DMA IP + direct engine + bounded AXI memory BFM.
// No PS DDR silicon model: this gate checks DMA register/burst/stream behavior.
module tb_vendor_dma;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0;
 reg [9:0] law=0,lar=0;reg lav=0,lwv=0,lbr=0,larv=0,lrr=0;reg[31:0]lwd=0;
 wire lawr,lwr,lbv,larr,lrv;wire[31:0]lrd;wire[1:0]lbresp,lrresp;
 wire [31:0]ra,wa,wd,sd,md;wire[7:0]rlen,wlen;wire[2:0]rsz,wsz;
 wire[1:0]rburst,wburst;wire rav,rrdy,wav,wv,wl,brdy;
 wire[3:0]wstrb,sk,mk;wire sv,sr,sl,mv,mr,ml;
 reg[31:0]rdata=0;reg rv=0,rl=0,bv=0;
 reg ractive=0,wactive=0;reg[31:0]raddr=0,waddr=0;integer rleft=0,wleft=0;
 reg[31:0]rng=32'h5ab1cafe;wire rar=!ractive&&!rv;wire war=!wactive&&!bv;wire wr=wactive&&rng[2:0]!=0;
 reg[7:0]mem[0:65535];
 wire fault,idle;
 d_dma_0 dma(
 .s_axi_lite_aclk(clk),.m_axi_mm2s_aclk(clk),.m_axi_s2mm_aclk(clk),.axi_resetn(rst_n),
 .s_axi_lite_awvalid(lav),.s_axi_lite_awready(lawr),.s_axi_lite_awaddr(law),
 .s_axi_lite_wvalid(lwv),.s_axi_lite_wready(lwr),.s_axi_lite_wdata(lwd),
 .s_axi_lite_bresp(lbresp),.s_axi_lite_bvalid(lbv),.s_axi_lite_bready(lbr),
 .s_axi_lite_arvalid(larv),.s_axi_lite_arready(larr),.s_axi_lite_araddr(lar),
 .s_axi_lite_rvalid(lrv),.s_axi_lite_rready(lrr),.s_axi_lite_rdata(lrd),.s_axi_lite_rresp(lrresp),
 .m_axi_mm2s_araddr(ra),.m_axi_mm2s_arlen(rlen),.m_axi_mm2s_arsize(rsz),.m_axi_mm2s_arburst(rburst),
 .m_axi_mm2s_arvalid(rav),.m_axi_mm2s_arready(rar),.m_axi_mm2s_rdata(rdata),.m_axi_mm2s_rresp(2'b0),
 .m_axi_mm2s_rlast(rl),.m_axi_mm2s_rvalid(rv),.m_axi_mm2s_rready(rrdy),
 .m_axis_mm2s_tdata(sd),.m_axis_mm2s_tkeep(sk),.m_axis_mm2s_tvalid(sv),.m_axis_mm2s_tready(sr),.m_axis_mm2s_tlast(sl),
 .m_axi_s2mm_awaddr(wa),.m_axi_s2mm_awlen(wlen),.m_axi_s2mm_awsize(wsz),.m_axi_s2mm_awburst(wburst),
 .m_axi_s2mm_awvalid(wav),.m_axi_s2mm_awready(war),.m_axi_s2mm_wdata(wd),.m_axi_s2mm_wstrb(wstrb),
 .m_axi_s2mm_wlast(wl),.m_axi_s2mm_wvalid(wv),.m_axi_s2mm_wready(wr),
 .m_axi_s2mm_bresp(2'b0),.m_axi_s2mm_bvalid(bv),.m_axi_s2mm_bready(brdy),
 .s_axis_s2mm_tdata(md),.s_axis_s2mm_tkeep(mk),.s_axis_s2mm_tvalid(mv),.s_axis_s2mm_tready(mr),.s_axis_s2mm_tlast(ml));
 ascon_axis_direct engine(.clk(clk),.rst_n(rst_n),.session_epoch(64'd1),
 .s_axis_tdata(sd),.s_axis_tkeep(sk),.s_axis_tvalid(sv),.s_axis_tready(sr),.s_axis_tlast(sl),
 .m_axis_tdata(md),.m_axis_tkeep(mk),.m_axis_tvalid(mv),.m_axis_tready(mr),.m_axis_tlast(ml),.fault(fault),.idle(idle));
 integer b;
 always @(posedge clk)begin
  if(!rst_n)begin ractive<=0;wactive<=0;rv<=0;bv<=0;rng<=32'h5ab1cafe;end
  else begin
   rng<={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
   if(rav&&rar)begin
    if(rsz!=2||rburst!=1||ra+rlen*4+4>65536)$fatal(1,"invalid AXI read burst");
    if(ra[11:0]+rlen*4+4>4096)$fatal(1,"DMA crossed 4KiB in one burst");
    ractive<=1;raddr<=ra;rleft<=rlen+1;
   end
   if(rv&&rrdy)begin rv<=0;raddr<=raddr+4;rleft<=rleft-1;if(rleft==1)ractive<=0;end
   else if(ractive&&!rv&&rng[4:3]!=0)begin
    rdata<={mem[raddr+3],mem[raddr+2],mem[raddr+1],mem[raddr]};rl<=rleft==1;rv<=1;
   end
   if(wav&&war)begin
    if(wsz!=2||wburst!=1||wa+wlen*4+4>65536)$fatal(1,"invalid AXI write burst");
    if(wa[11:0]+wlen*4+4>4096)$fatal(1,"DMA write crossed 4KiB");
    wactive<=1;waddr<=wa;wleft<=wlen+1;
   end
   if(wv&&wr)begin
    for(b=0;b<4;b=b+1)if(wstrb[b])mem[waddr+b]<=wd[b*8+:8];
    if(wl!==(wleft==1))$fatal(1,"write burst last mismatch");
    waddr<=waddr+4;wleft<=wleft-1;
    if(wleft==1)begin wactive<=0;bv<=1;end
   end
   if(bv&&brdy)bv<=0;
  end
 end
 task wrreg(input[9:0]a,input[31:0]v);
  reg adone,wdone;
  begin
   @(negedge clk);law=a;lwd=v;lav=1;lwv=1;adone=0;wdone=0;
   while(!adone||!wdone)begin
    @(posedge clk);if(lav&&lawr)adone=1;if(lwv&&lwr)wdone=1;
    @(negedge clk);if(adone)lav=0;if(wdone)lwv=0;
   end
   while(!lbv)@(negedge clk);if(lbresp!=0)$fatal(1,"DMA register write error");
   lbr=1;@(negedge clk);lbr=0;
  end
 endtask
 task rdreg(input[9:0]a,output[31:0]v);begin
  @(negedge clk);lar=a;larv=1;@(posedge clk);while(!larr)@(posedge clk);
  @(negedge clk);larv=0;while(!lrv)@(negedge clk);v=lrd;
  if(lrresp!=0)$fatal(1,"DMA register read error");lrr=1;@(negedge clk);lrr=0;
 end endtask
 reg[1023:0]path;integer f,rc,nreq,nexp,kind,i,j,polls,cases=0,skipped=0;
 reg[7:0]req[0:4095],expected[0:4095];reg[31:0]stat,actual;
 localparam TX=4092,RX=32764; // exercise real DMA 4KiB burst splitting
 initial begin
  if(!$value$plusargs("VECTORS=%s",path))$fatal(1,"missing vectors");
  f=$fopen(path,"r");if(!f)$fatal(1,"open vectors");
  repeat(10)@(negedge clk);rst_n=1;repeat(20)@(negedge clk);
  wrreg('h00,1);wrreg('h30,1);
  while(!$feof(f))begin
   rc=$fscanf(f,"%d %d %d\n",nreq,nexp,kind);
   if(rc==3)begin
    for(i=0;i<nreq;i=i+1)rc=$fscanf(f,"%h",req[i]);
    for(i=0;i<nexp;i=i+1)rc=$fscanf(f,"%h",expected[i]);
    if(kind==0)begin
     while(!idle)@(negedge clk);
     for(i=0;i<4096;i=i+1)mem[RX+i]=8'ha5;
     for(i=0;i<nreq;i=i+1)mem[TX+i]=req[i];
     wrreg('h34,'h1000);wrreg('h04,'h1000);
     wrreg('h48,RX);wrreg('h58,4096); // arm receive before send
     wrreg('h18,TX);wrreg('h28,nreq);
     polls=0;stat=0;
     while(!stat[1]&&polls<30000)begin
      rdreg('h34,stat);if(stat&32'h770)$fatal(1,"S2MM error %h",stat);polls=polls+1;
     end
     if(!stat[1])$fatal(1,"DMA completion timeout");
     rdreg('h58,actual);if(actual!=nexp)$fatal(1,"actual length got%0d expected%0d",actual,nexp);
     rdreg('h04,stat);if(!stat[1]||(stat&32'h770))$fatal(1,"MM2S did not finish cleanly");
     for(j=0;j<nexp;j=j+1)if((j<40||j>=48)&&mem[RX+j]!==expected[j])
       $fatal(1,"vendor DMA case%0d byte%0d got%h expected%h",cases,j,mem[RX+j],expected[j]);
     for(j=nexp;j<4096;j=j+1)if(mem[RX+j]!==8'ha5)$fatal(1,"DMA wrote beyond response");
     cases=cases+1;if(cases%300==0)$display("DMA_PROGRESS %0d",cases);
    end else skipped=skipped+1;
   end else if(!$feof(f))$fatal(1,"parse header");
  end
  $display("TEST_PASS vendor_dma cases=%0d malformed_stream_cases_tested_separately=%0d",cases,skipped);$finish;
 end
 initial begin #1000000000;$fatal(1,"vendor DMA watchdog");end
endmodule

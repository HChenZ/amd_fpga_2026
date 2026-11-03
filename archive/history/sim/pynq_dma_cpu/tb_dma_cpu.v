`timescale 1ns/1ps
module tb_dma_cpu;
    reg clk=0, rst_n=0;
    always #5 clk=~clk;
    reg [63:0] epoch=1;
    reg [31:0] sd=0;
    reg [3:0] sk=0;
    reg sv=0, sl=0, mr=0;
    wire sr,mv,ml,ready,busy,fault,cpu_rst_n;
    wire [31:0] md;
    wire [3:0] mk;
    wire cpu_re,cpu_we;
    wire [7:0] cpu_addr;
    wire [31:0] cpu_wdata,cpu_rdata;
    wire [3:0] cpu_wstrb;
    dma_cpu_endpoint ep(
        .clk(clk),.rst_n(rst_n),.session_epoch(epoch),
        .s_axis_tdata(sd),.s_axis_tkeep(sk),.s_axis_tvalid(sv),.s_axis_tready(sr),.s_axis_tlast(sl),
        .m_axis_tdata(md),.m_axis_tkeep(mk),.m_axis_tvalid(mv),.m_axis_tready(mr),.m_axis_tlast(ml),
        .cpu_re(cpu_re),.cpu_we(cpu_we),.cpu_addr(cpu_addr),.cpu_wdata(cpu_wdata),
        .cpu_wstrb(cpu_wstrb),.cpu_rdata(cpu_rdata),.cpu_rst_n(cpu_rst_n),
        .ready(ready),.busy(busy),.fault(fault));
    wire awready,awvalid,awid,wready,wvalid,wlast,bvalid,bid,bready;
    wire arready,arvalid,arid,rvalid,rlast,rid,rready;
    wire [31:0] awaddr,wdata,araddr,rdata;
    wire [7:0] awlen,arlen;
    wire [2:0] awsize,arsize;
    wire [1:0] awburst,arburst,bresp,rresp;
    wire [3:0] wstrb;
    soc_top_dma soc(
        .clk(clk),.rst_n(cpu_rst_n),.uart_rxd(1'b1),.uart_txd(),.button(2'b0),.led(),
        .dma_re(cpu_re),.dma_we(cpu_we),.dma_addr(cpu_addr),.dma_wdata(cpu_wdata),
        .dma_wstrb(cpu_wstrb),.dma_rdata(cpu_rdata),
        .m_awready(awready),.m_awvalid(awvalid),.m_awid(awid),.m_awaddr(awaddr),
        .m_awlen(awlen),.m_awsize(awsize),.m_awburst(awburst),
        .m_wready(wready),.m_wvalid(wvalid),.m_wlast(wlast),.m_wdata(wdata),.m_wstrb(wstrb),
        .m_bvalid(bvalid),.m_bid(bid),.m_bresp(bresp),.m_buser(1'b0),.m_bready(bready),
        .m_arready(arready),.m_arvalid(arvalid),.m_arid(arid),.m_araddr(araddr),
        .m_arlen(arlen),.m_arsize(arsize),.m_arburst(arburst),
        .m_rvalid(rvalid),.m_rlast(rlast),.m_rid(rid),.m_rdata(rdata),.m_rresp(rresp),.m_ruser(1'b0),.m_rready(rready));
    axi_slave_bram #(.ADDR_WIDTH(32),.DATA_WIDTH(32),.ID_WIDTH(1),.USER_WIDTH(1),
        .RAM_DEPTH(32768),.BASE_ADDR(32'h10000000)) mem(
        .s_axi_aclk(clk),.s_axi_aresetn(cpu_rst_n),
        .s_axi_awid(awid),.s_axi_awaddr(awaddr),.s_axi_awlen(awlen),.s_axi_awsize(awsize),
        .s_axi_awburst(awburst),.s_axi_awlock(1'b0),.s_axi_awcache(4'b0),.s_axi_awprot(3'b0),
        .s_axi_awqos(4'b0),.s_axi_awregion(4'b0),.s_axi_awuser(1'b0),
        .s_axi_awvalid(awvalid),.s_axi_awready(awready),
        .s_axi_wdata(wdata),.s_axi_wstrb(wstrb),.s_axi_wlast(wlast),.s_axi_wuser(1'b0),
        .s_axi_wvalid(wvalid),.s_axi_wready(wready),
        .s_axi_bid(bid),.s_axi_bresp(bresp),.s_axi_buser(),.s_axi_bvalid(bvalid),.s_axi_bready(bready),
        .s_axi_arid(arid),.s_axi_araddr(araddr),.s_axi_arlen(arlen),.s_axi_arsize(arsize),
        .s_axi_arburst(arburst),.s_axi_arlock(1'b0),.s_axi_arcache(4'b0),.s_axi_arprot(3'b0),
        .s_axi_arqos(4'b0),.s_axi_arregion(4'b0),.s_axi_aruser(1'b0),
        .s_axi_arvalid(arvalid),.s_axi_arready(arready),
        .s_axi_rid(rid),.s_axi_rdata(rdata),.s_axi_rresp(rresp),.s_axi_rlast(rlast),
        .s_axi_ruser(),.s_axi_rvalid(rvalid),.s_axi_rready(rready));

    reg [7:0] requests[0:2097151], expected[0:2097151];
    reg [31:0] sizes[0:8191],counts[0:8191];
    reg [1023:0] directory;
    integer cases,c,qbase=0,rbase=0,i,j,n,got,watch,stall;
    integer request_bytes,response_bytes;
    reg [31:0] held;
    reg [3:0] held_keep;
    reg held_last;
    reg [7:0] expected_byte;
    task beat(input [31:0] d,input [3:0] k,input l);
        begin
            @(negedge clk); sd=d;sk=k;sl=l;sv=1;
            watch=0;
            @(posedge clk);
            while(!sr) begin @(posedge clk); watch=watch+1; if(watch>10000) $fatal(1,"TX watchdog"); end
            @(negedge clk); sv=0;sl=0;
        end
    endtask
    task send_first(input [7:0] epnum);
        integer a,b;
        reg [31:0] word;
        begin
            for(a=0;a<sizes[0];a=a+4) begin
                word=0;
                for(b=0;b<4;b=b+1) if(a+b<sizes[0]) begin
                    word[b*8+:8]=requests[a+b];
                    if(a+b==8) word[b*8+:8]=epnum;
                    if(a+b==28) word[b*8+:8]=3;
                end
                beat(word,(a+4<=sizes[0])?4'hf:((1<<(sizes[0]-a))-1),a+4>=sizes[0]);
            end
        end
    endtask
    initial begin
        if(!$value$plusargs("DATA=%s",directory)) $fatal(1,"DATA required");
        if(!$value$plusargs("CASES=%d",cases)) $fatal(1,"CASES required");
        if(!$value$plusargs("REQUEST_BYTES=%d",request_bytes)) $fatal(1,"REQUEST_BYTES required");
        if(!$value$plusargs("RESPONSE_BYTES=%d",response_bytes)) $fatal(1,"RESPONSE_BYTES required");
        if(cases<1 || cases>8192 || request_bytes>2097152 || response_bytes>2097152) $fatal(1,"vector capacity");
        $readmemh({directory,"/requests.hex"},requests,0,request_bytes-1);
        $readmemh({directory,"/expected.hex"},expected,0,response_bytes-1);
        $readmemh({directory,"/sizes.hex"},sizes,0,cases-1);
        $readmemh({directory,"/counts.hex"},counts,0,cases-1);
        repeat(8) @(negedge clk);rst_n=1;
        repeat(4) @(negedge clk);
        for(c=0;c<cases;c=c+1) begin
            n=sizes[c];
            for(i=0;i<n;i=i+4) begin
                sd=0;sk=0;
                for(j=0;j<4;j=j+1) if(i+j<n) begin sd[j*8+:8]=requests[qbase+i+j];sk[j]=1;end
                beat(sd,sk,i+4>=n);
            end
            got=0;watch=0;
            while(got<counts[c]) begin
                @(negedge clk);mr=0;
                while(!mv) begin
                    @(negedge clk);watch=watch+1;
                    if(fault || watch>2000000) $fatal(1,"RX watchdog case=%0d pc=%h",c,soc.u_cpu_core.u_if_stage.pc);
                end
                held=md;held_keep=mk;held_last=ml;
                repeat(3) begin
                    @(negedge clk);
                    if(!mv || md!==held || mk!==held_keep || ml!==held_last) $fatal(1,"backpressure unstable");
                end
                for(j=0;j<4;j=j+1) if(mk[j]) begin
                    if(got>=counts[c]) $fatal(1,"excess output");
                    // Computation mcycle is measured, not predetermined by KAT.
                    if(!(got>=40 && got<48) && md[j*8+:8]!==expected[rbase+got])
                        $fatal(1,"KAT mismatch case=%0d byte=%0d got=%h expected=%h",c,got,md[j*8+:8],expected[rbase+got]);
                    if(got>=40 && got<48 && expected[rbase+24]!=0 && md[j*8+:8]!==0)
                        $fatal(1,"failure cycles leaked");
                    got=got+1;
                end
                if(ml !== (got==counts[c])) $fatal(1,"TLAST mismatch");
                mr=1;@(posedge clk);@(negedge clk);mr=0;
            end
            qbase=qbase+sizes[c];rbase=rbase+counts[c];
            $display("CPU_DMA_KAT case=%0d PASS",c);
        end
        // Reset in a partial packet, then epoch change: no stale response.
        beat(32'h51313044,15,0);
        @(negedge clk);epoch=2;
        repeat(5) @(negedge clk);
        if(mv || busy || fault || !ready) $fatal(1,"epoch abort failed");
        // Abort actual CPU ISE computation, then abort a completed stalled result.
        send_first(2);
        watch=0;
        while(!soc.u_cpu_core.u_ex_stage.ascon_perm_start) begin
            @(negedge clk);watch=watch+1;
            if(watch>2000000 || fault) $fatal(1,"ISE start watchdog");
        end
        @(negedge clk);epoch=3;
        repeat(5) @(negedge clk);
        if(mv || busy || !ready) $fatal(1,"active ISE abort failed");
        send_first(3);
        watch=0;
        while(!mv) begin @(negedge clk);watch=watch+1;if(watch>2000000 || fault) $fatal(1,"pending response watchdog");end
        repeat(5) @(negedge clk);
        epoch=4;
        repeat(5) @(negedge clk);
        if(mv || busy || !ready) $fatal(1,"pending response abort failed");
        send_first(4);
        got=0;watch=0;
        while(got<counts[0]) begin
            @(negedge clk);
            while(!mv) begin @(negedge clk);watch=watch+1;if(watch>2000000 || fault) $fatal(1,"recovery KAT watchdog");end
            for(j=0;j<4;j=j+1) if(mk[j]) begin
                expected_byte=expected[got];
                if(got==8) expected_byte=4;
                if(got==32) expected_byte=3;
                if(!(got>=40 && got<48) && md[j*8+:8]!==expected_byte) $fatal(1,"recovery KAT mismatch byte=%0d",got);
                got=got+1;
            end
            if(ml !== (got==counts[0])) $fatal(1,"recovery TLAST");
            mr=1;@(posedge clk);@(negedge clk);mr=0;
        end
        $display("CPU_DMA_TEST_PASS cases=%0d reset_partial=PASS reset_active_ise=PASS reset_pending=PASS recovery_kat=PASS",cases);
        $finish;
    end
    initial begin #10000000000; $fatal(1,"global watchdog"); end
endmodule

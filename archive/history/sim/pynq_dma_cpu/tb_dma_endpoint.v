`timescale 1ns/1ps
module tb_dma_endpoint;
    reg clk=0,rst_n=0;always #5 clk=~clk;
    reg [63:0] epoch=1;
    reg [31:0] sd=0,wd=0;
    reg [3:0] sk=0,ws=15;
    reg sv=0,sl=0,mr=0,re=0,we=0;
    reg [7:0] addr=0;
    wire sr,mv,ml,cr,ready,busy,fault;
    wire [31:0] md,rd;
    wire [3:0] mk;
    dma_cpu_endpoint #(.WATCHDOG_CYCLES(2000)) dut(
        .clk(clk),.rst_n(rst_n),.session_epoch(epoch),
        .s_axis_tdata(sd),.s_axis_tkeep(sk),.s_axis_tvalid(sv),.s_axis_tready(sr),.s_axis_tlast(sl),
        .m_axis_tdata(md),.m_axis_tkeep(mk),.m_axis_tvalid(mv),.m_axis_tready(mr),.m_axis_tlast(ml),
        .cpu_re(re),.cpu_we(we),.cpu_addr(addr),.cpu_wdata(wd),.cpu_wstrb(ws),.cpu_rdata(rd),
        .cpu_rst_n(cr),.ready(ready),.busy(busy),.fault(fault));
    task reset;
        begin @(negedge clk);rst_n=0;sv=0;re=0;we=0;mr=0;ws=15;
            repeat(3) @(negedge clk);rst_n=1;repeat(3) @(negedge clk);
            if(!ready || fault || mv) $fatal(1,"reset state");
        end
    endtask
    task beat(input [31:0] d,input [3:0] k,input l);
        begin @(negedge clk);sd=d;sk=k;sl=l;sv=1;
            @(posedge clk);if(!sr) $fatal(1,"unexpected not ready");
            @(negedge clk);sv=0;
        end
    endtask
    task readreg(input [7:0] a,input [31:0] expected);
        begin @(negedge clk);addr=a;re=1;
            @(posedge clk);#1;if(rd!==expected) $fatal(1,"MMIO a=%h got=%h expected=%h",a,rd,expected);
            @(negedge clk);re=0;
        end
    endtask
    task writereg(input [7:0] a,input [31:0] d);
        begin @(negedge clk);addr=a;wd=d;we=1;
            @(negedge clk);we=0;
        end
    endtask
    integer n,i;
    reg [3:0] keep;
    reg [31:0] mask;
    initial begin
        reset();
        readreg(8,0);readreg(24,1);readreg(28,0);
        for(n=1;n<=4;n=n+1) begin
            keep=(1<<n)-1;mask=32'hffffffff>>(32-8*n);
            beat(32'hfedcba98,keep,1);
            if(sr || !busy || ready) $fatal(1,"single slot gate");
            readreg(4,n);readreg(8,32'hfedcba98 & mask);readreg(8,0);
            for(i=0;i<(48+n+3)/4;i=i+1) writereg(12,32'habababab+i);
            writereg(16,48+n);writereg(20,1);
            if(!mv) $fatal(1,"commit missing");
            readreg(0,2);
            for(i=0;i<(48+n+3)/4;i=i+1) begin
                repeat(4) begin @(negedge clk);
                    if(!mv || md!==32'habababab+i) $fatal(1,"backpressure data");
                    if(ml !== (i==12)) $fatal(1,"last position");
                    if(mk !== (i==12?keep:4'hf)) $fatal(1,"last keep");
                end
                mr=1;@(posedge clk);@(negedge clk);mr=0;
            end
            if(!ready || busy || mv) $fatal(1,"slot not released");
        end
        beat(0,5,1);if(!fault) $fatal(1,"sparse keep accepted");reset();
        beat(0,0,1);if(!fault) $fatal(1,"empty keep accepted");reset();
        beat(0,3,0);if(!fault) $fatal(1,"partial nonlast accepted");reset();
        for(i=0;i<40;i=i+1) beat(i,15,0);
        if(!fault || sr) $fatal(1,"overflow/unbounded packet accepted");reset();
        beat(0,15,0);repeat(2010) @(negedge clk);
        if(!fault || cr || mv) $fatal(1,"watchdog failed");reset();
        beat(0,15,1);readreg(8,0);writereg(16,48);writereg(20,1);
        if(!fault) $fatal(1,"incomplete response accepted");reset();
        beat(1,15,1);readreg(8,1);
        for(i=0;i<12;i=i+1) writereg(12,i);
        writereg(16,48);writereg(20,1);
        @(negedge clk);epoch=2;
        #1;if(mv || cr) $fatal(1,"epoch change must gate immediately");
        repeat(4) @(negedge clk);
        if(!ready || busy || fault) $fatal(1,"epoch abort response");
        readreg(8,0);readreg(24,2);
        $display("DMA_ENDPOINT_TEST_PASS keeps=4 backpressure malformed watchdog overflow commit epoch");$finish;
    end
    initial begin #1000000;$fatal(1,"global watchdog");end
endmodule

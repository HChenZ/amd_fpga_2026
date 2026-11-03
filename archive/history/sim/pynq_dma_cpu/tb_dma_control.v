`timescale 1ns/1ps
module tb_dma_control;
    reg clk=0,rst_n=0;always #5 clk=~clk;
    reg [7:0] aa=0,ra=0;
    reg av=0,wv=0,bready=0,rv=0,rready=0;
    reg [31:0] wd=0;
    reg [3:0] ws=15;
    wire ar,wr,bv,rr,rvalid,ern;
    wire [1:0] br,rresp;
    wire [31:0] rd;
    wire [63:0] epoch;
    dma_control dut(.clk(clk),.rst_n(rst_n),
        .s_axi_awaddr(aa),.s_axi_awvalid(av),.s_axi_awready(ar),
        .s_axi_wdata(wd),.s_axi_wstrb(ws),.s_axi_wvalid(wv),.s_axi_wready(wr),
        .s_axi_bresp(br),.s_axi_bvalid(bv),.s_axi_bready(bready),
        .s_axi_araddr(ra),.s_axi_arvalid(rv),.s_axi_arready(rr),
        .s_axi_rdata(rd),.s_axi_rresp(rresp),.s_axi_rvalid(rvalid),.s_axi_rready(rready),
        .endpoint_ready(1'b1),.endpoint_busy(1'b0),.endpoint_fault(1'b0),
        .endpoint_rst_n(ern),.session_epoch(epoch));
    task write(input [7:0] a,input [31:0] d,input [3:0] s,input reverse,input [1:0] expected);
        begin
            @(negedge clk);aa=a;wd=d;ws=s;
            if(reverse) wv=1;else av=1;
            @(posedge clk);@(negedge clk);av=0;wv=0;
            repeat(4) @(negedge clk);
            if(bv) $fatal(1,"write prematurely answered");
            if(reverse) av=1;else wv=1;
            @(posedge clk);@(negedge clk);av=0;wv=0;
            while(!bv) @(negedge clk);
            repeat(4) begin @(negedge clk);if(!bv || br!==expected) $fatal(1,"B stalled response");end
            bready=1;@(posedge clk);@(negedge clk);bready=0;
        end
    endtask
    task read(input [7:0] a,input [31:0] expected);
        begin @(negedge clk);ra=a;rv=1;
            @(posedge clk);@(negedge clk);rv=0;
            repeat(4) begin @(negedge clk);
                if(!rvalid || rd!==expected || rresp!==0) $fatal(1,"R read/stall addr=%h got=%h expected=%h",a,rd,expected);
            end
            rready=1;@(posedge clk);@(negedge clk);rready=0;
        end
    endtask
    initial begin
        repeat(4) @(negedge clk);rst_n=1;
        read(0,32'h32414d44);read(4,2);read(8,1);read(32,0);
        read(20,32);read(24,32);read(28,7);
        read('h30,32);read('h34,32);read('h38,16);read('h3c,16);
        read('h40,32);read('h44,32);read('h48,0);read('h4c,0);
        write(12,32'h12345678,15,0,0);
        write(16,32'habcdef98,15,1,0);
        write(12,32'hffffffaa,1,0,0);
        if(epoch!==64'habcdef98123456aa) $fatal(1,"epoch strobes");
        write(8,0,0,1,0);if(ern) $fatal(1,"zero strobe reset changed");
        write(8,0,1,1,0);if(!ern) $fatal(1,"reset release");read(32,1);
        write(12,0,15,0,2);if(epoch!==64'habcdef98123456aa) $fatal(1,"live epoch changed");
        write(0,0,15,1,2);
        write(8,1,1,0,0);if(ern) $fatal(1,"reset hold");
        $display("DMA_CONTROL_TEST_PASS AW_W_order WSTRB backpressure identity capabilities reset epoch");$finish;
    end
    initial begin #1000000;$fatal(1,"watchdog");end
endmodule

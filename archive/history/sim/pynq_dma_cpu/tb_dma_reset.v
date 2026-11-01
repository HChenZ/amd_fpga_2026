`timescale 1ns/1ps
module tb_dma_reset;
    reg clk=0,raw_resetn=0;
    always #5 clk=~clk;
    wire resetn;
    dma_cpu_reset_sync dut(.clk(clk),.raw_resetn(raw_resetn),.resetn(resetn));
    initial begin
        #2;raw_resetn=1;
        #1;raw_resetn=0;
        #1;if(resetn!==0) $fatal(1,"asynchronous reset assertion");
        #3;raw_resetn=1;
        #1;if(resetn!==0) $fatal(1,"premature reset release");
        @(posedge clk);#1;if(resetn!==0) $fatal(1,"release before two clock edges");
        @(posedge clk);#1;if(resetn!==1) $fatal(1,"two-clock release missing");
        #2;raw_resetn=0;
        #1;if(resetn!==0) $fatal(1,"mid-cycle abort did not assert immediately");
        #1;raw_resetn=1;
        @(posedge clk);#1;if(resetn!==0) $fatal(1,"recovery first edge");
        @(posedge clk);#1;if(resetn!==1) $fatal(1,"recovery second edge");
        $display("DMA_RESET_TEST_PASS async_abort synchronous_release");$finish;
    end
    initial begin #1000;$fatal(1,"watchdog");end
endmodule

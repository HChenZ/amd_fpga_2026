`timescale 1ns/1ps
module tb_ro_health_v2;
    reg clk=0,ro_clk=0,rst_n=0,start=0,fast=0,slow=0;
    reg run_ro=1,run_osc=1;
    always #5 clk=~clk;
    always #7 if(run_ro) ro_clk=~ro_clk;
    always #2 if(run_osc) fast=~fast;
    always #4 if(run_osc) slow=~slow;
    reg [1:0] mode=0;
    wire [3:0] osc=(mode==1)?{fast,fast,fast,fast}:
                   (mode==2)?{slow,slow,fast,fast}:
                   (mode==3)?{slow,fast,fast,fast}:{fast,slow,slow,fast};
    wire done,valid,busy,locked;
    wire [1:0] raw;
    wire [7:0] error;
    ro_puf_core_v2 #(.BITS(2),.CW(10),.WINDOW(64),.RO_DEADLINE(256),.CORE_DEADLINE(1024)) dut(
        .clk(clk),.ro_clk(ro_clk),.rst_n(rst_n),.start(start),.osc(osc),.raw(raw),
        .valid(valid),.done(done),.busy(busy),.error_code(error),.locked(locked),
        .transaction_id(),.diagnostic_counts());
    wire odone,ovalid;
    wire [7:0] oerror;
    ro_puf_core_v2 #(.BITS(2),.CW(4),.WINDOW(64),.RO_DEADLINE(256),.CORE_DEADLINE(1024)) overflow_dut(
        .clk(clk),.ro_clk(ro_clk),.rst_n(rst_n),.start(start),.osc(osc),.raw(),
        .valid(ovalid),.done(odone),.busy(),.error_code(oerror),.locked(),
        .transaction_id(),.diagnostic_counts());
    task tick; begin @(posedge clk); #1; end endtask
    task reset; begin
        @(negedge clk); rst_n=0; repeat(5) tick();
        @(negedge clk); rst_n=1; repeat(8) tick();
    end endtask
    task launch; begin @(negedge clk); start=1; tick(); @(negedge clk); start=0; end endtask
    task finish_sample(input [7:0] expected_bits); integer n; begin
        n=0; while(!done && n<1500) begin tick(); n=n+1; end
        if(n==1500 || busy || ((error & expected_bits)!=expected_bits)) $fatal(1,"health error %h expected %h",error,expected_bits);
        if(expected_bits==0) begin
            if(!valid || error!=0 || raw!=2'b01) $fatal(1,"normal raw/valid");
        end else if(valid || raw!=0 || !locked) $fatal(1,"health failure published raw");
        tick();
    end endtask
    initial begin
        reset(); launch(); finish_sample(0);
        if(ovalid || !oerror[4]) $fatal(1,"saturation not detected");
        mode=1; reset(); launch(); finish_sample(8'h08);
        mode=3; reset(); launch(); finish_sample(8'h08); // just one tied pair rejects whole sample
        mode=2; reset(); launch(); finish_sample(8'h20);
        mode=0; reset(); launch();
        // Stable-bus fault injection, after stop ack: emulate zero/stale counts.
        wait(dut.state==4); force dut.counts=40'b0;
        finish_sample(8'h0c); release dut.counts;
        reset(); launch(); wait(dut.state==4); force dut.counts=40'hffffffffff;
        finish_sample(8'h10); release dut.counts;
        // Explicit watchdog injection, cannot return old successful data.
        reset(); launch(); repeat(10) tick(); force dut.timer=256;
        finish_sample(8'h01); release dut.timer;
        reset(); launch(); finish_sample(0);
        // Completion capture and publication must be separate core edges.
        reset(); launch(); wait(dut.capture_pending); #1;
        if(done || valid || !busy || dut.captured_error!=0 || dut.captured_result!=2'b01)
            $fatal(1,"completion capture did not isolate payload");
        // Deliberately violate source hold after capture: publication must use
        // captured core registers, not a fresh decode of asynchronous payload.
        force dut.sample_error=8'h08; force dut.result=2'b00;
        finish_sample(0); release dut.sample_error; release dut.result;
        // START has precedence over a pending successful completion.
        reset(); launch(); wait(dut.capture_pending); launch(); finish_sample(8'h40);
        if(dut.capture_pending || dut.captured_result!=0 || dut.captured_error!=0)
            $fatal(1,"START retained pending capture");
        repeat(8) tick(); if(valid || raw!=0) $fatal(1,"late publication after START");
        // Deadline likewise wins even when a success was already captured.
        reset(); launch(); wait(dut.capture_pending); force dut.core_timer=1024;
        finish_sample(8'h02); release dut.core_timer;
        if(dut.capture_pending || dut.captured_result!=0 || dut.captured_error!=0)
            $fatal(1,"deadline retained pending capture");
        reset(); launch(); wait(dut.capture_pending); reset();
        if(done || valid || busy || dut.capture_pending || dut.captured_result!=0 || dut.captured_error!=0)
            $fatal(1,"reset retained pending capture");
        // Reset assertion works without either destination clock. Release waits
        // for two local rising edges, not two source/core edges.
        @(negedge clk); run_ro=0; run_osc=0; rst_n=0; #1;
        if(dut.ro_rst_n!==0 || dut.counters[0].u_counter.osc_rst_n!==0)
            $fatal(1,"stopped-clock reset assertion failed");
        repeat(3) tick(); @(negedge clk); rst_n=1; repeat(8) tick();
        if(dut.ro_rst_n!==0 || dut.counters[0].u_counter.osc_rst_n!==0)
            $fatal(1,"reset released without destination clock");
        @(negedge clk); run_ro=1; run_osc=1;
        fork
            begin
                @(posedge ro_clk); #1; if(dut.ro_rst_n!==0) $fatal(1,"management reset released too early");
                @(posedge ro_clk); #1; if(dut.ro_rst_n!==1) $fatal(1,"management reset failed to release");
            end
            begin
                @(posedge osc[0]); #1; if(dut.counters[0].u_counter.osc_rst_n!==0) $fatal(1,"osc reset released too early");
                @(posedge osc[0]); #1; if(dut.counters[0].u_counter.osc_rst_n!==1) $fatal(1,"osc reset failed to release");
            end
        join
        repeat(8) tick(); launch(); finish_sample(0);
        $display("TEST_PASS tb_ro_health_v2"); $finish;
    end
    initial begin #200000; $fatal(1,"global watchdog"); end
endmodule

`timescale 1ns/1ps
module tb_ascon_permutation_regression;
  reg clk=0, rst_n=0, start8=0, start12=0;
  always #5 clk=~clk;
  reg [319:0] input8=0, input12=0, round_input=0;
  reg [7:0] constant=0;
  wire [319:0] output8, output12, round_output;
  wire done8, done12, busy8, busy12;
  p8 u8(.clk(clk),.rst_n(rst_n),.start(start8),.s_in(input8),.s_out(output8),.done(done8),.busy(busy8));
  p12 u12(.clk(clk),.rst_n(rst_n),.start(start12),.s_in(input12),.s_out(output12),.done(done12),.busy(busy12));
  round ur(.s_in(round_input),.C(constant),.s_out(round_output));
  reg [655:0] vectors[0:307];
  reg [1023:0] vector_path;
  integer errors=0, i, byte_idx, cycles, op;
  reg [319:0] actual, expected;

  task compare_state;
    input [319:0] got, want;
    input integer kind, case_id;
    integer b, first;
    begin
      first=-1;
      for(b=0;b<40;b=b+1)
        if(first<0 && got[b*8+:8] !== want[b*8+:8]) first=b;
      if(first>=0) begin
        $display("FAIL permutation/op=%0d/case=%0d byte=%0d expected=%02h actual=%02h",kind,case_id,first,want[first*8+:8],got[first*8+:8]);
        errors=errors+1;
      end else $display("PASS permutation/op=%0d/case=%0d",kind,case_id);
    end
  endtask

  task run_permutation;
    input integer kind, case_id;
    input [319:0] inp, want;
    integer count;
    reg finished;
    begin
      @(negedge clk);
      if(kind==8) begin input8=inp;start8=1;end
      else begin input12=inp;start12=1;end
      @(negedge clk);
      start8=0;start12=0;
      if((kind==8 ? busy8 : busy12)!==1'b1) begin
        $display("FAIL handshake/op=%0d/case=%0d busy did not assert",kind,case_id);errors=errors+1;
      end
      count=0;finished=0;
      while(!finished && count<20) begin
        @(negedge clk);count=count+1;
        finished=(kind==8 ? done8 : done12)===1'b1;
      end
      if(!finished) begin
        $display("FAIL timeout/op=%0d/case=%0d",kind,case_id);errors=errors+1;
      end else begin
        compare_state(kind==8 ? output8 : output12,want,kind,case_id);
        if(count!=(kind==8 ? 9 : 13) || (kind==8 ? busy8 : busy12)!==1'b0) begin
          $display("FAIL completion/op=%0d/case=%0d latency=%0d",kind,case_id,count);errors=errors+1;
        end else $display("PASS completion/op=%0d/case=%0d latency=%0d",kind,case_id,count);
      end
      @(negedge clk);
      if((kind==8 ? done8 : done12)!==1'b0) begin
        $display("FAIL done_pulse/op=%0d/case=%0d",kind,case_id);errors=errors+1;
      end else $display("PASS done_pulse/op=%0d/case=%0d",kind,case_id);
    end
  endtask

  task reset_during_operation;
    input integer kind;
    begin
      @(negedge clk);
      if(kind==8) begin input8=vectors[12][639:320];start8=1;end
      else begin input12=vectors[13][639:320];start12=1;end
      @(negedge clk);start8=0;start12=0;
      repeat(3) @(negedge clk);
      rst_n=0;
      @(negedge clk);
      if(busy8!==0 || busy12!==0 || done8!==0 || done12!==0 || output8!==320'd0 || output12!==320'd0) begin
        $display("FAIL reset_abort/op=%0d",kind);errors=errors+1;
      end else $display("PASS reset_abort/op=%0d",kind);
      rst_n=1;
      run_permutation(kind,1000+kind,vectors[kind==8 ? 12 : 13][639:320],vectors[kind==8 ? 12 : 13][319:0]);
    end
  endtask

  // Observe current policy: a start while busy restarts with the new input.
  // This checks the observed implementation, not a frozen project protocol.
  task observe_busy_restart;
    input integer kind;
    integer count;
    reg finished;
    begin
      @(negedge clk);
      if(kind==8) begin input8=vectors[12][639:320];start8=1;end
      else begin input12=vectors[13][639:320];start12=1;end
      @(negedge clk);start8=0;start12=0;
      repeat(3) @(negedge clk);
      if(kind==8) begin input8=vectors[26][639:320];start8=1;end
      else begin input12=vectors[27][639:320];start12=1;end
      @(negedge clk);start8=0;start12=0;
      count=0;finished=0;
      while(!finished && count<20) begin
        @(negedge clk);count=count+1;finished=(kind==8 ? done8 : done12)===1'b1;
      end
      if(!finished) begin $display("FAIL busy_restart_timeout/op=%0d",kind);errors=errors+1;end
      else begin
        compare_state(kind==8 ? output8 : output12,vectors[kind==8 ? 26 : 27][319:0],kind,5000+kind);
        $display("OBSERVATION permutation_busy_start=restart op=%0d latency=%0d",kind,count);
      end
      @(negedge clk);
    end
  endtask

  initial begin
    if(!$value$plusargs("vectors=%s",vector_path)) $fatal(1,"Missing permutation vector path");
    $readmemh(vector_path,vectors);
    repeat(3) @(negedge clk);
    rst_n=1;
    for(i=0;i<308;i=i+1) begin
      op=vectors[i][655:648];
      if(op==1) begin
        round_input=vectors[i][639:320];constant=vectors[i][647:640];#1;
        compare_state(round_output,vectors[i][319:0],1,i);
      end else run_permutation(op,i,vectors[i][639:320],vectors[i][319:0]);
    end
    // Same instance, many calls without resetting, then abort and restart.
    for(i=0;i<4;i=i+1) begin
      run_permutation(8,2000+i,vectors[12][639:320],vectors[12][319:0]);
      run_permutation(12,3000+i,vectors[13][639:320],vectors[13][319:0]);
    end
    reset_during_operation(8);reset_during_operation(12);
    observe_busy_restart(8);observe_busy_restart(12);
    if(errors) $fatal(1,"FAIL permutation SUMMARY errors=%0d",errors);
    $display("PASS permutation SUMMARY errors=0");$finish;
  end
  initial begin #200000;$fatal(1,"FAIL permutation watchdog");end
endmodule

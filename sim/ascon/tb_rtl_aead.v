`timescale 1ns/1ps
module tb_ascon_aead_regression;
  reg clk=0, rst_n=0, start=0;
  always #5 clk=~clk;
  reg [127:0] k=0,npub=0,ad=0,m=0;
  reg [4:0] adlen=0,mlen=0;
  wire [127:0] c,tag;
  wire busy,done;
  crypto_aead_encrypt dut(.clk(clk),.rst_n(rst_n),.start(start),.m(m),.ad(ad),
    .npub(npub),.k(k),.adlen(adlen),.mlen(mlen),.c(c),.tag(tag),.done(done),.busy(busy));
  parameter CASES=60;
  reg [783:0] vectors[0:CASES-1];
  reg [1023:0] vector_path;
  integer errors=0,i;

  task compare_bytes;
    input [127:0] got,want;
    input integer length,kind,case_id;
    integer b,first;
    begin
      first=-1;
      for(b=0;b<length;b=b+1)
        if(first<0 && got[b*8+:8] !== want[b*8+:8]) first=b;
      if(first>=0) begin
        $display("FAIL aead/field=%0d/case=%0d byte=%0d expected=%02h actual=%02h",kind,case_id,first,want[first*8+:8],got[first*8+:8]);
        errors=errors+1;
      end else $display("PASS aead/field=%0d/case=%0d length=%0d",kind,case_id,length);
    end
  endtask

  task load_case;
    input integer index;
    begin
      mlen=vectors[index][783:776];adlen=vectors[index][775:768];
      k=vectors[index][767:640];npub=vectors[index][639:512];
      ad=vectors[index][511:384];m=vectors[index][383:256];
    end
  endtask

  task run_case;
    input integer index, case_id, busy_start;
    integer count;
    reg finished;
    begin
      @(negedge clk);load_case(index);start=1;
      @(negedge clk);start=0;
      if(busy!==1 || done!==0) begin
        $display("FAIL aead_start/case=%0d busy=%b done=%b",case_id,busy,done);errors=errors+1;
      end
      count=0;finished=0;
      while(!finished && count<200) begin
        @(negedge clk);count=count+1;
        // Additional pulse while busy with changed message inputs must be ignored.
        if(busy_start && count==2) begin start=1;ad=~ad;m=~m;adlen=1;mlen=1;end
        if(busy_start && count==3) start=0;
        finished=done===1;
      end
      if(!finished) begin
        $display("FAIL aead_timeout/case=%0d",case_id);errors=errors+1;
      end else begin
        compare_bytes(c,vectors[index][255:128],vectors[index][783:776],0,case_id);
        compare_bytes(tag,vectors[index][127:0],16,1,case_id);
        if(busy!==0) begin
          $display("FAIL aead_completion/case=%0d busy=%b",case_id,busy);errors=errors+1;
        end else $display("PASS aead_completion/case=%0d latency=%0d",case_id,count);
      end
      @(negedge clk);
      if(done!==0) begin
        $display("FAIL aead_done_pulse/case=%0d",case_id);errors=errors+1;
      end else $display("PASS aead_done_pulse/case=%0d",case_id);
    end
  endtask

  task abort_and_reset;
    input integer delay_cycles;
    begin
      @(negedge clk);load_case(2);start=1;
      @(negedge clk);start=0;
      repeat(delay_cycles) @(negedge clk);
      rst_n=0;
      @(negedge clk);
      if(busy!==0 || done!==0 || tag!==128'd0) begin
        $display("FAIL aead_reset_abort/delay=%0d",delay_cycles);errors=errors+1;
      end else $display("PASS aead_reset_abort/delay=%0d",delay_cycles);
      rst_n=1;
      run_case(2,4000+delay_cycles,0);
    end
  endtask

  task observe_key_and_unused_output;
    integer count;
    reg finished;
    begin
      @(negedge clk);load_case(1);start=1;
      @(negedge clk);start=0;
      @(negedge clk);k=~k;
      count=0;finished=0;
      while(!finished && count<200) begin
        @(negedge clk);count=count+1;finished=done===1;
      end
      if(!finished) begin $display("FAIL key_stability_probe_timeout");errors=errors+1;end
      else begin
        $display("OBSERVATION key_changed_after_start original_request_tag=%032h actual_tag=%032h matches_original=%0d",
          vectors[1][127:0],tag,tag===vectors[1][127:0]);
      end
      run_case(4,6000,0);
      $display("OBSERVATION short_ciphertext_bus length=3 bus=%032h",c);
      run_case(0,6001,0);
      $display("OBSERVATION empty_ciphertext_bus valid_bytes=0 bus=%032h",c);
    end
  endtask

  initial begin
    if(!$value$plusargs("vectors=%s",vector_path)) $fatal(1,"Missing AEAD vector path");
    $readmemh(vector_path,vectors);
    repeat(3) @(negedge clk);rst_n=1;
    for(i=0;i<CASES;i=i+1) run_case(i,i,0);
    // Nonempty -> empty -> another nonempty request, with no reset between.
    run_case(2,2000,0);run_case(0,2001,0);run_case(1,2002,0);
    run_case(2,3000,1);
    abort_and_reset(3);abort_and_reset(25);abort_and_reset(45);
    observe_key_and_unused_output();
    if(errors) $fatal(1,"FAIL encryption SUMMARY errors=%0d",errors);
    $display("PASS encryption SUMMARY errors=0; decryption=not_implemented");$finish;
  end
  initial begin #500000;$fatal(1,"FAIL AEAD watchdog");end
endmodule

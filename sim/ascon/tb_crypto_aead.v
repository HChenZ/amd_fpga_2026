`timescale 1ns/1ps
// Unified crypto_aead regression: encrypt + independent decrypt + tamper
// reject + unsupported-length reject, all against the same frozen vector set.
// Vector layout (784 bits, little-endian buses):
//   [783:776] plaintext_bytes | [775:768] ad_bytes | [767:640] key
//   [639:512] nonce | [511:384] ad | [383:256] plaintext
//   [255:128] ciphertext | [127:0] tag
module tb_crypto_aead;
  reg clk=0, rst_n=0, start=0, mode=0;
  always #5 clk=~clk;
  reg [127:0] k=0,npub=0,ad=0,data_in=0,tag_in=0;
  reg [4:0] adlen=0,datalen=0;
  wire [127:0] data_out,tag;
  wire correct,done,busy,error;
  crypto_aead dut(.clk(clk),.rst_n(rst_n),.start(start),.mode(mode),
    .data_in(data_in),.ad(ad),.npub(npub),.k(k),.adlen(adlen),.datalen(datalen),
    .tag_in(tag_in),.data_out(data_out),.tag(tag),.correct(correct),
    .done(done),.busy(busy),.error(error));

  parameter CASES=289;
  reg [783:0] vectors[0:CASES-1];
  reg [1023:0] vector_path;
  integer errors=0,i,n,a,accepted=0,rejected=0,invalid_lengths=0;

  task load_common;
    input integer index;
    begin
      datalen=vectors[index][783:776];adlen=vectors[index][775:768];
      k=vectors[index][767:640];npub=vectors[index][639:512];
      ad=vectors[index][511:384];
    end
  endtask

  task compare_bytes;
    input [127:0] got,want;
    input integer length,kind,case_id;
    integer b,first;
    begin
      first=-1;
      for(b=0;b<length;b=b+1)
        if(first<0 && got[b*8+:8]!==want[b*8+:8]) first=b;
      if(first>=0) begin
        $display("FAIL %0s/case=%0d byte=%0d expected=%02h actual=%02h",kind,case_id,first,want[first*8+:8],got[first*8+:8]);
        errors=errors+1;
      end
    end
  endtask

  task run_encrypt;
    input integer index;
    integer count;
    reg finished;
    begin
      @(negedge clk);load_common(index);
      data_in=vectors[index][383:256];mode=0;start=1;
      @(negedge clk);start=0;
      if(busy!==1 || done!==0) begin
        $display("FAIL enc_start/case=%0d busy=%b done=%b",index,busy,done);errors=errors+1;
      end
      count=0;finished=0;
      while(!finished && count<200) begin
        @(negedge clk);count=count+1;finished=done===1;
      end
      if(!finished) begin
        $display("FAIL enc_timeout/case=%0d",index);errors=errors+1;
      end else begin
        compare_bytes(data_out,vectors[index][255:128],datalen,"enc_ct",index);
        if(tag!==vectors[index][127:0]) begin
          $display("FAIL enc_tag/case=%0d",index);errors=errors+1;
        end
        if(busy!==0 || error!==0 || correct!==0) begin
          $display("FAIL enc_completion/case=%0d busy=%b error=%b correct=%b",index,busy,error,correct);errors=errors+1;
        end else begin
          accepted=accepted+1;
          $display("PASS encrypt/case=%0d length=%0d latency=%0d",index,datalen,count);
        end
      end
      @(negedge clk);
      if(done!==0) begin
        $display("FAIL enc_done_pulse/case=%0d",index);errors=errors+1;
      end
    end
  endtask

  task run_decrypt;
    input integer index,tamper;
    integer count;
    reg finished;
    begin
      @(negedge clk);load_common(index);
      data_in=vectors[index][255:128];tag_in=vectors[index][127:0];
      if(tamper) tag_in=tag_in^128'h1;
      mode=1;start=1;
      @(negedge clk);start=0;
      if(busy!==1 || done!==0) begin
        $display("FAIL dec_start/case=%0d busy=%b done=%b",index,busy,done);errors=errors+1;
      end
      count=0;finished=0;
      while(!finished && count<200) begin
        @(negedge clk);count=count+1;
        finished=done===1;
        if(!finished && (data_out!==128'd0 || correct!==1'b0)) begin
          $display("FAIL dec_hidden/case=%0d/tamper=%0d data_out=%032h correct=%b",
            index,tamper,data_out,correct);errors=errors+1;
        end
      end
      if(!finished) begin
        $display("FAIL dec_timeout/case=%0d",index);errors=errors+1;
      end else if(tamper) begin
        if(correct!==1'b0 || data_out!==128'd0 || busy!==0) begin
          $display("FAIL dec_reject/case=%0d data_out=%032h correct=%b busy=%b",
            index,data_out,correct,busy);errors=errors+1;
        end else begin
          rejected=rejected+1;
          $display("PASS decrypt_reject/case=%0d",index);
        end
      end else begin
        compare_bytes(data_out,vectors[index][383:256],datalen,"dec_pt",index);
        if(tag!==vectors[index][127:0] || correct!==1'b1 || busy!==0 || error!==0) begin
          $display("FAIL dec_valid/case=%0d correct=%b busy=%b error=%b",index,correct,busy,error);errors=errors+1;
        end else begin
          accepted=accepted+1;
          $display("PASS decrypt/case=%0d length=%0d latency=%0d",index,datalen,count);
        end
      end
      @(negedge clk);
      if(done!==0) begin
        $display("FAIL dec_done_pulse/case=%0d",index);errors=errors+1;
      end
      if(tamper && (data_out!==128'd0 || correct!==1'b0)) begin
        $display("FAIL dec_rejected_hold/case=%0d",index);errors=errors+1;
      end
    end
  endtask

  task reject_length;
    input integer data_len,ad_len;
    begin
      @(negedge clk);load_common(0);
      datalen=data_len;adlen=ad_len;data_in=128'h0;
      mode=0;start=1;
      @(negedge clk);start=0;
      if(done!==1 || busy!==0 || error!==1 || data_out!==128'd0 || tag!==128'd0) begin
        $display("FAIL enc_length/data_len=%0d/ad_len=%0d",data_len,ad_len);errors=errors+1;
      end else invalid_lengths=invalid_lengths+1;
      @(negedge clk);
      if(done!==0) begin
        $display("FAIL enc_length_done_pulse");errors=errors+1;
      end
      mode=1;start=1;
      @(negedge clk);start=0;
      if(done!==1 || busy!==0 || error!==1 || correct!==0 || data_out!==128'd0) begin
        $display("FAIL dec_length/data_len=%0d/ad_len=%0d",data_len,ad_len);errors=errors+1;
      end else invalid_lengths=invalid_lengths+1;
      @(negedge clk);
      if(done!==0) begin
        $display("FAIL dec_length_done_pulse");errors=errors+1;
      end
    end
  endtask

  initial begin
    if(!$value$plusargs("vectors=%s",vector_path)) $fatal(1,"Missing crypto vector path");
    $readmemh(vector_path,vectors);
    repeat(3) @(negedge clk);rst_n=1;
    for(i=0;i<CASES;i=i+1) begin
      run_encrypt(i);
      run_decrypt(i,0);
      run_decrypt(i,1);
    end
    // Nonempty -> empty -> nonempty with no reset between (single module reuse).
    run_encrypt(1);run_encrypt(0);run_encrypt(2);
    run_decrypt(1,0);run_decrypt(0,0);run_decrypt(2,0);
    for(n=0;n<32;n=n+1)
      for(a=0;a<32;a=a+1)
        if(n>16 || a>16) reject_length(n,a);
    if(errors) $fatal(1,"FAIL crypto SUMMARY errors=%0d",errors);
    $display("PASS crypto SUMMARY errors=0 accepted=%0d rejected=%0d invalid_lengths=%0d",
      accepted,rejected,invalid_lengths);
    $finish;
  end
  initial begin #20000000;$fatal(1,"FAIL crypto watchdog");end
endmodule

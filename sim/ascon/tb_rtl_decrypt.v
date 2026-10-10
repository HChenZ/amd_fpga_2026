`timescale 1ns/1ps
module tb_ascon_decrypt_regression;
  reg clk=0, rst_n=0, start=0;
  always #5 clk=~clk;
  reg [127:0] k=0,npub=0,ad=0,c=0,tag=0;
  reg [4:0] adlen=0,clen=0;
  wire [127:0] m;
  wire correct,busy,done;
  wire [127:0] computed_tag;
  crypto_aead_decrypt dut(.clk(clk),.rst_n(rst_n),.start(start),.c(c),.tag_in(tag),
    .ad(ad),.npub(npub),.k(k),.adlen(adlen),.clen(clen),.m(m),.tag(computed_tag),
    .correct(correct),.done(done),.busy(busy));
  wire [127:0] positional_m,positional_tag;
  wire positional_correct,positional_done,positional_busy;
  crypto_aead_decrypt positional_dut(clk,rst_n,start,c,ad,npub,k,adlen,clen,tag,
    positional_m,positional_tag,positional_correct,positional_done,positional_busy);
  always @(negedge clk) begin
    if(rst_n && {positional_m,positional_tag,positional_correct,positional_done,positional_busy}
          !== {m,computed_tag,correct,done,busy})
      $fatal(1,"FAIL decrypt_positional_interface");
  end
  parameter CASES=300;
  reg [783:0] vectors[0:CASES-1];
  reg [1023:0] vector_path;
  integer errors=0,i,j,a,n,accepted=0,rejected=0,invalid_lengths=0;

  task load_case;
    input integer index;
    begin
      clen=vectors[index][783:776];adlen=vectors[index][775:768];
      k=vectors[index][767:640];npub=vectors[index][639:512];
      ad=vectors[index][511:384];c=vectors[index][255:128];tag=vectors[index][127:0];
    end
  endtask

  task check_hidden;
    input integer case_id;
    begin
      if(m!==128'd0 || correct!==0 || busy!==1) begin
        $display("FAIL decrypt_unverified/case=%0d m=%032h correct=%b busy=%b",
          case_id,m,correct,busy);errors=errors+1;
        if($test$plusargs("fail_fast")) $fatal(1,"FAIL unverified plaintext/status");
      end
    end
  endtask

  // Inputs come from independent frozen C||T, never this DUT's encrypt output.
  // mode 1/2: tag ends, 3/4: ciphertext ends, 5/6: key/nonce, 7/8: AD ends.
  // mode 9/10: individual tag/ciphertext bits. mode 0 is valid.
  task run_case;
    input integer index,mode,bit_index,busy_start;
    integer count,b,first;
    reg finished;
    begin
      @(negedge clk);load_case(index);
      case(mode)
        1: tag[0]=~tag[0];
        2: tag[127]=~tag[127];
        3: c[0]=~c[0];
        4: c[(clen-1)*8+7]=~c[(clen-1)*8+7];
        5: k[0]=~k[0];
        6: npub[127]=~npub[127];
        7: ad[0]=~ad[0];
        8: ad[(adlen-1)*8+7]=~ad[(adlen-1)*8+7];
        9: tag[bit_index]=~tag[bit_index];
        10: c[bit_index]=~c[bit_index];
      endcase
      start=1;
      @(negedge clk);start=0;check_hidden(index);
      count=0;finished=0;
      while(!finished && count<200) begin
        @(negedge clk);count=count+1;
        if(busy_start && count==2) begin
          start=1;c=~c;ad=~ad;clen=1;adlen=1;
        end
        if(busy_start && count==3) start=0;
        finished=done===1;
        if(!finished) check_hidden(index);
      end
      if(!finished) begin
        $display("FAIL decrypt_timeout/case=%0d/mode=%0d",index,mode);errors=errors+1;
      end else if(mode==0) begin
        first=-1;
        for(b=0;b<vectors[index][783:776];b=b+1)
          if(first<0 && m[b*8+:8]!==vectors[index][256+b*8+:8]) first=b;
        if(first>=0 || correct!==1 || busy!==0 || computed_tag!==vectors[index][127:0]) begin
          $display("FAIL decrypt_valid/case=%0d byte=%0d m=%032h correct=%b busy=%b",
            index,first,m,correct,busy);errors=errors+1;
        end else begin
          accepted=accepted+1;
          $display("PASS decrypt_valid/case=%0d length=%0d latency=%0d",index,vectors[index][783:776],count);
        end
      end else begin
        if(correct!==0 || busy!==0 || m!==128'd0) begin
          $display("FAIL decrypt_reject/case=%0d/mode=%0d/bit=%0d m=%032h correct=%b busy=%b",
            index,mode,bit_index,m,correct,busy);errors=errors+1;
        end else begin
          rejected=rejected+1;
          $display("PASS decrypt_reject/case=%0d/mode=%0d/bit=%0d",index,mode,bit_index);
        end
      end
      @(negedge clk);
      if(done!==0) begin $display("FAIL decrypt_done_pulse/case=%0d",index);errors=errors+1;end
      // A rejected request must stay hidden even after the completion pulse.
      if(mode!=0 && (m!==128'd0 || correct!==0)) begin
        $display("FAIL decrypt_rejected_output_hold/case=%0d",index);errors=errors+1;
      end
    end
  endtask

  task reject_length;
    input integer ct_len,ad_len;
    begin
      @(negedge clk);load_case(2);clen=ct_len;adlen=ad_len;start=1;
      @(negedge clk);start=0;
      if(done!==1 || busy!==0 || correct!==0 || m!==128'd0) begin
        $display("FAIL decrypt_length/clen=%0d/adlen=%0d",ct_len,ad_len);errors=errors+1;
      end else begin
        invalid_lengths=invalid_lengths+1;
        $display("PASS decrypt_length/clen=%0d/adlen=%0d",ct_len,ad_len);
      end
      @(negedge clk);
      if(done!==0) begin $display("FAIL decrypt_length_done_pulse");errors=errors+1;end
    end
  endtask

  task abort_and_reset;
    input integer delay_cycles;
    begin
      @(negedge clk);load_case(2);start=1;
      @(negedge clk);start=0;
      repeat(delay_cycles) @(negedge clk);
      if(busy!==1 || done!==0) begin
        $display("FAIL decrypt_reset_not_in_flight/delay=%0d",delay_cycles);errors=errors+1;
      end
      rst_n=0;
      @(negedge clk);
      if(busy!==0 || done!==0 || correct!==0 || m!==128'd0) begin
        $display("FAIL decrypt_reset_abort/delay=%0d",delay_cycles);errors=errors+1;
      end else $display("PASS decrypt_reset_abort/delay=%0d",delay_cycles);
      rst_n=1;run_case(2,0,0,0);
    end
  endtask

  initial begin
    if(!$value$plusargs("vectors=%s",vector_path)) $fatal(1,"Missing AEAD vector path");
    $readmemh(vector_path,vectors);
    repeat(3) @(negedge clk);rst_n=1;
    for(i=0;i<CASES;i=i+1) begin
      run_case(i,0,0,0);run_case(i,1,0,0);run_case(i,2,0,0);
      if(vectors[i][783:776]!=0) begin run_case(i,3,0,0);run_case(i,4,0,0);end
      run_case(i,5,0,0);run_case(i,6,0,0);
      if(vectors[i][775:768]!=0) begin run_case(i,7,0,0);run_case(i,8,0,0);end
    end
    // Every tag bit and every full-block ciphertext bit must be authenticated.
    for(j=0;j<128;j=j+1) begin run_case(2,9,j,0);run_case(2,10,j,0);end
    run_case(2,0,0,1);
    run_case(2,1,0,0);run_case(0,0,0,0);run_case(2,0,0,0);
    // Abort initialization, AD P8, data P8, final P12, and pre-publication.
    abort_and_reset(3);abort_and_reset(25);abort_and_reset(45);
    abort_and_reset(60);abort_and_reset(69);
    for(n=0;n<32;n=n+1)
      for(a=0;a<32;a=a+1)
        if(n>16 || a>16) reject_length(n,a);
    run_case(2,0,0,0);run_case(0,0,0,0);
    if(errors) $fatal(1,"FAIL decryption SUMMARY errors=%0d",errors);
    $display("PASS decryption SUMMARY errors=0 accepted=%0d rejected=%0d invalid_lengths=%0d",accepted,rejected,invalid_lengths);
    $finish;
  end
  initial begin #20000000;$fatal(1,"FAIL decrypt watchdog");end
endmodule

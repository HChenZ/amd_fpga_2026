`timescale 1ns/1ps
// Independent KAT bytes; internal state only observed to target aborts.
module tb_core_lifecycle;
  reg clk=0; always #5 clk=~clk;
  reg rst_n=0, clear=0, load_valid=0, load_ad=0, start=0, encrypt=0;
  reg [9:0] load_addr=0, result_addr=0;
  reg [7:0] load_data=0;
  reg [15:0] adlen=0, mlen=0;
  reg [127:0] key=0, nonce=0, tag_in=0;
  wire ready,busy,done,success,length_error;
  wire [127:0] tag_out;
  wire [63:0] cycles;
  wire [7:0] result_data;
  ascon_aead_multiblock dut(.*);
  reg [7:0] av[0:1023],pv[0:1023],cv[0:1023];
  reg [127:0] kv,nv,tv;
  integer al,ml,fd,rc,i,j,b,mode,target,tests=0,phase=0;
  reg [7:0] held;
  reg [1023:0] vector_path;
  initial begin #200000000; $fatal(1,"LIFECYCLE_WATCHDOG phase=%0d state=%0d",phase,dut.state); end
  always @(posedge clk) begin
    #1;
    if (rst_n && !clear) begin
      if ((busy || !success) && result_data !== 0)
        $fatal(1,"EARLY_OUTPUT phase=%0d state=%0d",phase,dut.state);
      if (busy && (success || tag_out !== 0)) $fatal(1,"EARLY_PUBLISH");
      if (busy && done) $fatal(1,"BUSY_DONE");
    end
  end
  task tick; begin @(posedge clk); #2; end endtask
  task wait_ready;
    integer n;
    begin n=0; while(!ready && n<20000)begin tick; n=n+1; end
      if(!ready)$fatal(1,"READY_TIMEOUT phase=%0d",phase);
    end
  endtask
  task scrub_check;
    integer n;
    begin
      if(success || tag_out!==0 || result_data!==0)$fatal(1,"SCRUB_PUBLIC");
      if({dut.s0,dut.s1,dut.s2,dut.s3,dut.s4,dut.k0,dut.k1,dut.expected_tag} !== 0)
        $fatal(1,"SCRUB_SECRET");
      for(n=0;n<1024;n=n+1)
        if(dut.ad_mem[n]!==0 || dut.msg_mem[n]!==0 || dut.result_mem[n]!==0)
          $fatal(1,"SCRUB_MEMORY addr=%0d",n);
    end
  endtask
  task abort_op(input integer reset_kind);
    begin
      @(negedge clk); if(reset_kind)rst_n=0;else clear=1;
      tick;
      if(done || success || tag_out!==0 || result_data!==0)$fatal(1,"ABORT_PUBLIC");
      @(negedge clk); rst_n=1;clear=0;start=0;load_valid=0;
      wait_ready; scrub_check;
      repeat(3)begin tick;if(done)$fatal(1,"ABORT_GHOST_DONE");end
    end
  endtask
  task load_inputs(input integer encmode);
    integer n;
    begin
      wait_ready;
      for(n=0;n<al+ml;n=n+1)begin
        @(negedge clk);load_valid=1;load_ad=n<al;
        load_addr=n<al?n:n-al;
        load_data=n<al?av[n]:(encmode?pv[n-al]:cv[n-al]);
        tick;
      end
      @(negedge clk);load_valid=0;
    end
  endtask
  task kick(input integer encmode,input integer badbit);
    begin
      @(negedge clk);encrypt=encmode;adlen=al;mlen=ml;key=kv;nonce=nv;
      tag_in=tv;if(badbit>=0)tag_in[badbit]=~tag_in[badbit];start=1;
      // START wins over a colliding input-memory load.
      load_valid=1;load_ad=0;load_addr=0;load_data=8'hd3;
      tick;
      if(!busy || success || tag_out!==0 || result_data!==0)$fatal(1,"START_REVOKE");
      @(negedge clk);start=0;load_valid=0;
    end
  endtask
  task finish_op(input integer encmode,input integer badbit,input integer attack);
    integer n;
    begin
      n=0;
      while(!done && n<20000)begin
        if(attack)begin
          @(negedge clk);
          key=~key;nonce=nonce+1;tag_in=~tag_in;adlen=16'hffff;mlen=16'hffff;
          encrypt=~encrypt;start=busy;load_valid=busy;load_ad=n%2;
          load_addr=n%1024;load_data=n;
        end
        tick;n=n+1;
      end
      if(!done)$fatal(1,"DONE_TIMEOUT");
      @(negedge clk);start=0;load_valid=0;
      if(length_error)$fatal(1,"LATCHED_LENGTH");
      if(badbit>=0)begin
        if(success)$fatal(1,"BAD_TAG_ACCEPTED bit=%0d",badbit);
        scrub_check;
      end else begin
        if(!success || tag_out!==tv)$fatal(1,"KAT_TAG ml=%0d al=%0d expected=%h actual=%h",ml,al,tv,tag_out);
        for(n=0;n<ml;n=n+1)begin
          @(negedge clk);result_addr=n;tick;
          if(result_data!==(encmode?cv[n]:pv[n]))$fatal(1,"KAT_DATA addr=%0d",n);
        end
        if(ml<1024)begin @(negedge clk);result_addr=ml;tick;
          if(result_data!==0)$fatal(1,"INVALID_READ");end
        // Synchronous RAM: between valid addresses, output waits for posedge.
        if(ml>1)begin
          @(negedge clk);result_addr=0;tick;held=result_data;
          @(negedge clk);result_addr=1;#1;
          if(result_data!==held)$fatal(1,"ASYNC_RESULT_READ");
          tick;if(result_data!==(encmode?cv[1]:pv[1]))$fatal(1,"SYNC_RESULT_READ");
        end
      end
      tick;if(done)$fatal(1,"DONE_NOT_PULSE");
      tests=tests+1;
    end
  endtask
  task read_vector;
    integer n;
    begin
      rc=$fscanf(fd,"%d %d %h %h %h",al,ml,kv,nv,tv);
      if(rc!=5)$fatal(1,"VECTOR_HEADER");
      for(n=0;n<al;n=n+1)rc=$fscanf(fd,"%h",av[n]);
      for(n=0;n<ml;n=n+1)rc=$fscanf(fd,"%h",pv[n]);
      for(n=0;n<ml;n=n+1)rc=$fscanf(fd,"%h",cv[n]);
    end
  endtask
  initial begin
    if(!$value$plusargs("VECTORS=%s",vector_path))$fatal(1,"VECTORS required");
    fd=$fopen(vector_path,"r");if(!fd)$fatal(1,"VECTOR_OPEN");
    repeat(3)tick;
    @(negedge clk);rst_n=1;wait_ready;scrub_check;
    for(j=0;j<5;j=j+1)begin
      read_vector;phase=10+j;
      load_inputs(1);kick(1,-1);finish_op(1,-1,1);
      if(j==1 && $test$plusargs("PROBE_LOAD_REVOKE"))begin
        @(negedge clk);load_valid=1;load_ad=0;load_addr=0;load_data=8'ha5;tick;
        if(success || tag_out!==0 || result_data!==0)
          $fatal(1,"NEW_LOAD_STALE_RESULT: accepted input load keeps prior authenticated result valid");
        @(negedge clk);load_valid=0;
      end
      if(j==1 && $test$plusargs("PROBE_SYNC_GATE"))begin
        @(negedge clk);result_addr=0;tick;held=result_data;
        @(negedge clk);result_addr=ml;#1;
        if(result_data!==held)
          $fatal(1,"SYNC_ADDRESS_GATE: unsampled invalid address changes synchronous result output");
        tick;if(result_data!==0)$fatal(1,"INVALID_READ");
      end
      load_inputs(0);kick(0,-1);finish_op(0,-1,1);
      load_inputs(0);kick(0,127);finish_op(0,127,1);
    end
    $fclose(fd);
    fd=$fopen(vector_path,"r");repeat(3)read_vector;$fclose(fd);phase=30;
    for(b=0;b<128;b=b+1)begin
      load_inputs(0);kick(0,b);finish_op(0,b,0);
    end
    // 17 bytes reaches full-block permutation, tails and fetch stages.
    for(mode=0;mode<2;mode=mode+1)begin
      for(target=0;target<=13;target=target+1)begin
        phase=100+mode*20+target;
        if(target==0)begin
          @(negedge clk);clear=1;tick;@(negedge clk);clear=0;
        end else if(target!=1)begin
          load_inputs(0);kick(0,target==11?0:-1);
          i=0;while(dut.state!=target && i<20000)begin tick;i=i+1;end
          if(dut.state!=target)$fatal(1,"UNREACHED_STAGE %0d",target);
        end
        abort_op(mode);tests=tests+1;
        load_inputs(0);kick(0,-1);finish_op(0,-1,0);
        $display("STAGE_ABORT_PASS reset=%0d stage=%0d",mode,target);
      end
    end
    phase=200;
    @(negedge clk);adlen=1025;mlen=17;start=1;tick;
    @(negedge clk);start=0;wait_ready;
    if(!done || !length_error)$fatal(1,"INVALID_LENGTH_STATUS");scrub_check;
    $display("TEST_PASS lifecycle checks=%0d all_bad_tag_bits=128 abort_stages=14 reset_and_clear=1",tests);
    $finish;
  end
endmodule

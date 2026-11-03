`timescale 1ns/1ps
module tb_puf_aead_v2;
    reg clk=0, ro_clk=0, run_ro=1, rst_n=0, clear=0;
    always #5 clk=~clk;
    always #7 if(run_ro) ro_clk=~ro_clk;
    wire [255:0] osc;
    genvar g;
    generate for(g=0;g<256;g=g+1) begin: models
        reg q=0;
        localparam PERIOD=(g<128)?((g%2)?4:2):((g%2)?2:4);
        always #(PERIOD) q=~q;
        assign osc[g]=q;
    end endgenerate
    reg key_start=0,enroll=0,helper_load=0,start=0,decrypt=0;
    reg [127:0] href=0,hmask=0,data_in=128'hffeeddccbbaa99887766554433221100;
    reg [127:0] tag_in=0;
    reg [4:0] datalen=16,adlen=16;
    wire ready,kbusy,kdone,busy,done,success;
    wire [7:0] ke,ae;
    wire [127:0] data_out,tag_out;
    puf_aead_v2 #(.CW(10),.WINDOW(64),.RO_DEADLINE(256),.CORE_DEADLINE(1024)) dut(
        .clk(clk),.ro_clk(ro_clk),.rst_n(rst_n),.clear(clear),.osc(osc),.board_dna(57'h1234),
        .key_start(key_start),.enroll(enroll),.helper_load(helper_load),
        .helper_ref_in(href),.helper_mask_in(hmask),.key_ready(ready),.key_busy(kbusy),
        .key_done(kdone),.key_error(ke),.start(start),.decrypt(decrypt),.data_in(data_in),
        .ad(128'h01234567),.nonce(128'h11223344),.tag_in(tag_in),.datalen(datalen),.adlen(adlen),
        .busy(busy),.done(done),.success(success),.error_code(ae),.data_out(data_out),.tag_out(tag_out));
    task tick; begin @(posedge clk); #1; end endtask
    task reset_all; begin
        @(negedge clk); rst_n=0; repeat(4) tick(); @(negedge clk); rst_n=1; repeat(8) tick();
    end endtask
    task revoke; begin
        @(negedge clk); clear=1; repeat(4) tick();
        if(ready || data_out!=0 || tag_out!=0) $fatal(1,"clear did not erase");
        @(negedge clk); clear=0; repeat(8) tick();
    end endtask
    task begin_key(input bit e); begin
        @(negedge clk); enroll=e; key_start=1; tick();
        if(ready || dut.internal_key!=0) $fatal(1,"stale key on start");
        @(negedge clk); key_start=0;
    end endtask
    task finish_key(input bit ok); integer n; begin
        n=0; while(!kdone && n<5000) begin tick(); n=n+1; end
        if(n==5000 || ready!==ok || kbusy || ((ke==0)!==ok)) $fatal(1,"key completion ok=%0d err=%h",ok,ke);
        if(!ok && dut.internal_key!=0) $fatal(1,"failed key retained");
        tick();
    end endtask
    task crypt(input bit dec,input bit ok); integer n; begin
        @(negedge clk); decrypt=dec; start=1; tick(); @(negedge clk); start=0;
        n=0; while(!done && n<600) begin
            if(data_out!=0 || tag_out!=0 || success) $fatal(1,"premature cipher output");
            tick(); n=n+1;
        end
        if(n==600 || success!==ok || busy) $fatal(1,"AEAD completion err=%h",ae);
        if(!ok && (data_out!=0 || tag_out!=0)) $fatal(1,"failed AEAD leaked output");
        tick();
    end endtask
    reg [127:0] ct,tg, saved_ref,saved_mask;
    integer i;
    initial begin
        reset_all();
        begin_key(0); finish_key(0); crypt(0,0);
        begin_key(1); finish_key(1);
        saved_ref=dut.keys.reference; saved_mask=dut.keys.mask;
        crypt(0,1); ct=data_out; tg=tag_out;
        begin_key(0); finish_key(1); crypt(0,1);
        if(ct!==data_out || tg!==tag_out) $fatal(1,"reconstruction changed AEAD");
        data_in=ct; tag_in=tg; crypt(1,1);
        if(data_out!==128'hffeeddccbbaa99887766554433221100) $fatal(1,"plaintext mismatch");
        for(i=0;i<128;i=i+1) begin tag_in=tg^(128'b1<<i); crypt(1,0); end
        $display("PASS reconstruct consistency and 128 bad tag bits");
        // Different trusted DNA input yields a different internal key; old tag fails.
        force dut.board_dna=57'h4321;
        begin_key(0); finish_key(1); tag_in=tg; data_in=ct; crypt(1,0);
        release dut.board_dna;
        // Persisted helper reload after reset, no reenrollment.
        reset_all(); href=saved_ref; hmask=saved_mask;
        @(negedge clk); helper_load=1; tick(); @(negedge clk); helper_load=0;
        begin_key(0); finish_key(1); data_in=128'hffeeddccbbaa99887766554433221100; crypt(0,1);
        if(ct!==data_out || tg!==tag_out) $fatal(1,"loaded helper changed AEAD");
        href=saved_ref^1;
        @(negedge clk); helper_load=1; tick(); @(negedge clk); helper_load=0;
        begin_key(0); finish_key(0); crypt(0,0);
        // Stop management clock: core deadline must still terminate.
        revoke(); run_ro=0; begin_key(1); finish_key(0);
        if(dut.keys.sample_error!==8'h02) $fatal(1,"core deadline missing");
        run_ro=1; revoke(); begin_key(1); finish_key(1);
        // Dead oscillator: stop/clear acknowledgement cannot complete.
        revoke(); force dut.keys.sampler.osc[0]=0;
        begin_key(1); finish_key(0);
        if(dut.keys.sample_error!==8'h01) $fatal(1,"RO watchdog missing");
        release dut.keys.sampler.osc[0]; revoke(); begin_key(1); finish_key(1);
        // Overlapping START aborts and revokes rather than silently dropping.
        begin_key(0); repeat(4) tick(); begin_key(0); finish_key(0); revoke();
        begin_key(1); finish_key(1);
        // Key change during cipher execution must cancel, with no output.
        @(negedge clk); start=1; tick(); @(negedge clk); start=0;
        repeat(5) tick(); begin_key(0);
        if(busy || success || data_out!=0 || tag_out!=0) $fatal(1,"revocation failed");
        finish_key(1); datalen=17; crypt(0,0); datalen=16;
        crypt(0,1);
        // Missing sampler completion: no late completion may resurrect a key.
        revoke(); force dut.keys.sampler.complete=0;
        begin_key(1); finish_key(0);
        release dut.keys.sampler.complete;
        repeat(20) tick();
        if(ready) $fatal(1,"late completion resurrected key");
        revoke(); begin_key(1); finish_key(1);
        // KDF completion missing: outer core-domain deadline is independent.
        force dut.keys.derived_done=0;
        begin_key(0); finish_key(0); release dut.keys.derived_done;
        if(ke!=8'h85) $fatal(1,"KDF deadline missing");
        revoke(); begin_key(1); finish_key(1);
        force dut.cd=0; crypt(0,0); release dut.cd;
        if(ae!=4) $fatal(1,"AEAD deadline missing");
        crypt(0,1);
        // Reset at each sampler FSM stage. Never accept a partial old sample.
        for(i=1;i<=5;i=i+1) begin
            begin_key(0); wait(dut.keys.sampler.state==i);
            reset_all();
            if(ready || kbusy || dut.internal_key!=0) $fatal(1,"reset state retained");
            begin_key(1); finish_key(1);
        end
        // Serial popcount boundary/exactness: every nonzero population 1..128.
        // Below MIN_BITS must fail, with the exact observed engineering count.
        for(i=1;i<=128;i=i+1) begin
            href=saved_ref; hmask=128'hffffffffffffffffffffffffffffffff>>(128-i);
            @(negedge clk); helper_load=1; tick(); @(negedge clk); helper_load=0;
            begin_key(0); finish_key(i>=64);
            if(dut.keys.quality!==i[7:0]) $fatal(1,"popcount mismatch expected=%0d actual=%0d",i,dut.keys.quality);
        end
        // Abort in the newly introduced quality-count phase, then recover.
        begin_key(0); wait(dut.keys.state==5); repeat(4) tick(); begin_key(0); finish_key(0);
        if(dut.keys.quality_shift!=0 || dut.keys.quality_acc!=0 || dut.keys.material!=0)
            $fatal(1,"quality abort retained candidate");
        revoke(); begin_key(1); finish_key(1);
        begin_key(0); wait(dut.keys.state==5); revoke();
        if(ready || dut.keys.quality_shift!=0 || dut.keys.material!=0) $fatal(1,"clear during quality count");
        begin_key(1); finish_key(1);
        // All-zero imported mask is explicitly refused.
        hmask=0; @(negedge clk); helper_load=1; tick();
        if(ke!=8'h84 || ready) $fatal(1,"empty helper accepted");
        @(negedge clk); helper_load=0; begin_key(0); finish_key(0);
        $display("TEST_PASS tb_puf_aead_v2"); $finish;
    end
    initial begin #2000000; $fatal(1,"global watchdog"); end
endmodule

`timescale 1ns/1ps
// Cycle-by-cycle miter against the pre-optimization core. Golden-answer
// correctness is covered separately by run_rtl_regression.py.
module tb_tail_equivalence;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0, start=0, mode=0;
    reg [127:0] data_in=0, ad=0, npub=0, k=0, tag_in=0;
    reg [4:0] adlen=0, datalen=0;
    wire [127:0] data_new,tag_new,data_old,tag_old;
    wire correct_new,done_new,busy_new,error_new;
    wire correct_old,done_old,busy_old,error_old;
    crypto_aead dut(.clk(clk),.rst_n(rst_n),.start(start),.mode(mode),
        .data_in(data_in),.ad(ad),.npub(npub),.k(k),.tag_in(tag_in),
        .adlen(adlen),.datalen(datalen),.data_out(data_new),.tag(tag_new),
        .correct(correct_new),.done(done_new),.busy(busy_new),.error(error_new));
    crypto_aead_before old(.clk(clk),.rst_n(rst_n),.start(start),.mode(mode),
        .data_in(data_in),.ad(ad),.npub(npub),.k(k),.tag_in(tag_in),
        .adlen(adlen),.datalen(datalen),.data_out(data_old),.tag(tag_old),
        .correct(correct_old),.done(done_old),.busy(busy_old),.error(error_old));
    integer ticks=0, cases=0, a,b,j;
    reg [31:0] rng=32'h9a163bc7;
    reg [127:0] plain,cipher,saved_tag;
    task random128(output reg [127:0] value);
        integer i;
        begin
            for(i=0;i<4;i=i+1) begin
                rng=rng^(rng<<13); rng=rng^(rng>>17); rng=rng^(rng<<5);
                value[32*i+:32]=rng;
            end
        end
    endtask
    always @(posedge clk) begin
        #1;
        if ({data_new,tag_new,correct_new,done_new,busy_new,error_new} !==
            {data_old,tag_old,correct_old,done_old,busy_old,error_old})
            $fatal(1,"cycle mismatch case=%0d ad=%0d data=%0d",cases,adlen,datalen);
        ticks=ticks+1;
        if(ticks>200000) $fatal(1,"timeout");
    end
    task transact;
        begin
            @(negedge clk); start=1;
            @(negedge clk); start=0;
            while(!done_new) @(negedge clk);
            cases=cases+1;
            @(negedge clk);
        end
    endtask
    initial begin
        repeat(3) @(negedge clk);
        rst_n=1;
        for(a=0;a<=16;a=a+1) for(b=0;b<=16;b=b+1) begin
            adlen=a; datalen=b;
            random128(k); random128(npub); random128(ad); random128(plain);
            data_in=plain; mode=0; tag_in=0;
            transact(); cipher=data_new; saved_tag=tag_new;
            data_in=cipher; mode=1; tag_in=saved_tag;
            transact();
            if(!correct_new) $fatal(1,"valid decrypt rejected");
            for(j=0;j<b;j=j+1)
                if(data_new[8*j+:8]!==plain[8*j+:8]) $fatal(1,"plaintext mismatch");
            tag_in=saved_tag^128'h1; transact();
            if(correct_new || data_new!==0) $fatal(1,"failed authentication exposed data");
        end
        $display("PASS tail equivalence cases=%0d cycles=%0d latency and outputs identical",cases,ticks);
        $finish;
    end
endmodule

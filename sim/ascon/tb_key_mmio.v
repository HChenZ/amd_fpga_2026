`timescale 1ns/1ps
module tb_key_mmio;
    reg clk=0, rst_n=0, re=0, we=0;
    reg [5:0] addr=0;
    reg [31:0] wd=0;
    wire [31:0] rd;
    wire irq;
    always #5 clk=~clk;
    ascon_mmio dut(clk,rst_n,re,we,addr,wd,rd,irq);
    reg [783:0] vectors[0:20];
    reg [127:0] k,n,a,m,c,t;
    reg [31:0] got;
    integer ml,al,i,j,b,timeout,checks=0,errors=0;
    task check(input bit ok, input [255:0] label);
        begin checks=checks+1; if(!ok) begin errors=errors+1; $display("FAIL %0s",label); end end
    endtask
    task wr(input [5:0] r, input [31:0] v);
        begin @(negedge clk); addr=r;wd=v;we=1;re=0; @(negedge clk);we=0; end
    endtask
    task read_reg(input [5:0] r);
        begin @(negedge clk);addr=r;re=1; @(negedge clk);got=rd;re=0; end
    endtask
    task setup(input bit enc, input [127:0] key_value, input [127:0] input_data, input [127:0] tag_value);
        begin
            wr(2,al);wr(3,ml);
            for(j=0;j<4;j=j+1) begin wr(4+j,key_value[32*j+:32]);wr(8+j,n[32*j+:32]);wr(12+j,tag_value[32*j+:32]);end
            for(j=0;j<(al+3)/4;j=j+1) wr(16,a[32*j+:32]);
            for(j=0;j<(ml+3)/4;j=j+1) wr(17,input_data[32*j+:32]);
            wr(0,enc?3:1);
        end
    endtask
    task finish_op(input bit success, input [127:0] expected);
        reg [127:0] masked;
        begin
            timeout=0;
            while(dut.busy_r && timeout<250) begin
                read_reg(1);timeout=timeout+1;
            end
            read_reg(1);check(got===(success?32'd2:32'd6),"DONE/FAIL status");
            masked=expected & (ml==16 ? {128{1'b1}} : ((128'd1<<(8*ml))-1));
            for(j=0;j<(ml+3)/4;j=j+1) begin
                read_reg(18);check(got===(success?masked[32*j+:32]:32'd0),"output bytes/tail/failure");
            end
            // Arbitrary excess reads must not expose old words or wrap around.
            repeat(70) begin read_reg(18);check(got===0,"OUT bound/stale");end
            for(j=0;j<4;j=j+1) begin
                read_reg(19+j);check(got===(success?t[32*j+:32]:32'd0),"tag/failure oracle hidden");
            end
        end
    endtask
    task clean_check;
        begin
            read_reg(1);check(got===0,"clear status");
            for(j=0;j<64;j=j+1) begin read_reg(j);check(got===0,"clear MMIO observable");end
            check({dut.key_r,dut.run_key,dut.nonce_r,dut.run_nonce,dut.tagin_r,dut.run_tagin,dut.tagout_r}===896'd0,"wrapper clear");
            for(j=0;j<64;j=j+1) check({dut.AD_BUF[j],dut.MSG_BUF[j],dut.OUT_BUF[j]}===96'd0,"buffers clear");
            check({dut.u_ascon_core.key_r,dut.u_ascon_core.nonce_r,dut.u_ascon_core.ad_shf,dut.u_ascon_core.data_shf,dut.u_ascon_core.out_shf}===640'd0,"adapter clear");
            check({dut.u_ascon_core.u_crypto_aead.s0,dut.u_ascon_core.u_crypto_aead.s1,dut.u_ascon_core.u_crypto_aead.s2,dut.u_ascon_core.u_crypto_aead.s3,dut.u_ascon_core.u_crypto_aead.s4}===320'd0,"AEAD state clear");
            check({dut.u_ascon_core.u_crypto_aead.p12_in,dut.u_ascon_core.u_crypto_aead.p8_in,dut.u_ascon_core.u_crypto_aead.p12_inst.s_reg,dut.u_ascon_core.u_crypto_aead.p12_inst.s_out,dut.u_ascon_core.u_crypto_aead.p8_inst.s_reg,dut.u_ascon_core.u_crypto_aead.p8_inst.s_out}===1920'd0,"permutation copies clear");
        end
    endtask
    initial begin
        $readmemh("build/local/key_audit/key_cases.mem",vectors);
        repeat(3) @(negedge clk);rst_n=1;clean_check();
        for(i=0;i<21;i=i+1) begin
            {ml[7:0],al[7:0],k,n,a,m,c,t}=vectors[i];ml=ml&255;al=al&255;
            setup(1,k,m,0);
            // BUSY key/nonce/data writes and START/ZEROIZE must not disturb run.
            wr(4,32'hbad);wr(8,32'hbad);wr(16,32'hbad);wr(17,32'hbad);wr(0,7);
            read_reg(18);check(got===0,"busy OUT hidden");
            check(dut.run_key===k && dut.run_nonce===n,"START snapshot");
            finish_op(1,c);
            for(j=4;j<16;j=j+1) begin read_reg(j);check(got===0,"write-only secrets");end
            setup(0,k,c,t);finish_op(1,m);
            for(b=0;b<3;b=b+1) begin
                setup(0,b==0?k^128'd1:k,b==2?c^128'd1:c,b==1?t^128'd1:t);
                if(b==2 && ml==0) finish_op(1,m); else finish_op(0,0);
            end
            wr(0,7); // idle ZEROIZE wins even when START is set
            clean_check();
            setup(1,k,m,0);finish_op(1,c); // reload after ZEROIZE
            // Unsupported lengths must revoke the previous result too.
            wr(3,17);wr(0,1);repeat(10) @(negedge clk);
            read_reg(1);check(got===6,"length reject");read_reg(18);check(got===0,"length reject stale output");
        end
        // Reset aborts during a real operation and erases all copies.
        setup(0,k,c,t);repeat(4) @(negedge clk);rst_n=0;
        repeat(3) @(negedge clk);rst_n=1;clean_check();
        setup(1,k,m,0);finish_op(1,c);
        $display("SUMMARY MMIO checks=%0d errors=%0d",checks,errors);
        if(errors) $fatal(1,"MMIO lifecycle");$finish;
    end
    initial begin #20000000; $fatal(1,"watchdog"); end
endmodule

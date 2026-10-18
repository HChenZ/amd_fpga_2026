`timescale 1ns/1ps
module tb_key_ise;
    reg clk=0,rst_n=0,cancel=0,ack=0,wr=0,start=0,p12=0;
    reg [3:0] wi=0,ri=0;
    reg [31:0] wd=0;
    wire [31:0] rd;
    wire done;
    reg [655:0] rows[0:307];
    reg [319:0] expected;
    integer i,j,limit,checks=0,errors=0;
    always #5 clk=~clk;
    ascon_ise dut(.clk(clk),.rst_n(rst_n),.wr_en(wr),.wr_idx(wi),.wr_data(wd),
        .rd_idx(ri),.rd_data(rd),.perm_start(start),.perm_p12(p12),.perm_done(done)
`ifndef LEGACY
        ,.cancel(cancel),.perm_ack(ack)
`endif
    );
    task check(input bit ok,input [255:0] label);
        begin checks=checks+1;if(!ok) begin errors=errors+1;$display("FAIL %0s",label);end end
    endtask
    task put(input [3:0] idx,input [31:0] data);
        begin @(negedge clk);wr=1;wi=idx;wd=data;@(negedge clk);wr=0;end
    endtask
    task state_check(input [319:0] value);
        begin for(j=0;j<10;j=j+1) begin ri=j;#1;check(rd===value[32*j+:32],"state word");end end
    endtask
    initial begin
        $readmemh("data/ascon/permutation.mem",rows);
        repeat(3) @(negedge clk);rst_n=1;state_check(0);
        for(i=10;i<16;i=i+1) begin put(i,32'hbad);ri=i;#1;check(rd===0,"illegal index read zero");end
        state_check(0);
        for(i=0;i<308;i=i+1) if(rows[i][655:648]==8 || rows[i][655:648]==12) begin
            for(j=0;j<10;j=j+1) put(j,rows[i][320+32*j+:32]);
            @(negedge clk);p12=(rows[i][655:648]==12);start=1;
            @(negedge clk);start=0;
            // Mode changes and word writes while running cannot corrupt this request.
            p12=~p12;put(0,32'hbad);
            limit=0;while(!done && limit<40) begin @(negedge clk);limit=limit+1;end
            check(done===1,"permutation completion");expected=rows[i][319:0];state_check(expected);
            // Simulate downstream CPU hold covering completion. No re-entry/lost done.
            start=1;repeat(24) @(negedge clk);check(done===1,"done held until ack");state_check(expected);
            start=0;ack=1;@(negedge clk);ack=0;
            for(j=0;j<10;j=j+1) put(j,0);
            state_check(0);
`ifndef LEGACY
            check({dut.u_p12.s_reg,dut.u_p12.s_out,dut.u_p8.s_reg,dut.u_p8.s_out}===1280'd0,"private copies scrubbed");
`endif
        end
        put(0,32'h123);@(negedge clk);start=1;p12=1;
        repeat(4) @(negedge clk);cancel=1;start=0;
        @(negedge clk);cancel=0;
        check(dut.state===320'd0 && !done,"cancel architectural clear");
        @(negedge clk);
        check({dut.u_p12.s_reg,dut.u_p12.s_out,dut.u_p8.s_reg,dut.u_p8.s_out}===1280'd0,
              "cancel private clear next edge");
        repeat(24) @(negedge clk);
        state_check(0);check(!done,"cancel no stale completion");
        put(0,32'h456);@(negedge clk);start=1;
        repeat(4) @(negedge clk);rst_n=0;start=0;
        repeat(3) @(negedge clk);rst_n=1;repeat(25) @(negedge clk);
        state_check(0);check(!done,"reset abort");
        $display("SUMMARY ISE checks=%0d errors=%0d",checks,errors);
        if(errors) $fatal(1,"ISE lifecycle");$finish;
    end
    initial begin #2000000;$fatal(1,"watchdog");end
endmodule

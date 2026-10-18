`timescale 1ns/1ps
`include "defines.v"
module tb_multiplier_pipeline;
    reg clk=0, rst_n=0, start=0, ack=0, cancel=0;
    reg [31:0] a=0,b=0;
    reg [5:0] op=`EXE_MUL_OP;
    wire [31:0] result;
    wire done;
    integer seed=32'h4d554c31, i,j,k,checks=0;
    reg [31:0] edge_values[0:7];
    reg [5:0] ops[0:3];
    always #5 clk=~clk;
    multiplier dut(.clk(clk),.rst_n(rst_n),.mul_start(start),.rs1_data(a),
        .rs2_data(b),.func_sel(op),.mul_result(result),.mul_done(done),
        .mul_ack(ack),.cancel(cancel));
    task run_case(input [31:0] av,bv,input [5:0] fv);
        reg signed [32:0] aa,bb;
        reg signed [65:0] product;
        reg [31:0] expected;
        integer n;
        begin
            aa={((fv==`EXE_MULH_OP)||(fv==`EXE_MULHSU_OP)) && av[31],av};
            bb={(fv==`EXE_MULH_OP) && bv[31],bv};
            product=aa*bb;
            expected=(fv==`EXE_MUL_OP)?product[31:0]:product[63:32];
            @(negedge clk);a=av;b=bv;op=fv;start=1;
            @(negedge clk);
            if(done) $fatal(1,"early done");
            // Inputs and decode may change while operation is in flight.
            a=~av;b=~bv;op=`EXE_NOP_OP;
            @(negedge clk);
            if(!done || result!==expected)
                $fatal(1,"multiply op=%h a=%h b=%h got=%h expected=%h",fv,av,bv,result,expected);
            // Exercise both level start and dropped start across completion hold.
            for(n=0;n<5;n=n+1) begin
                start=n[0];@(negedge clk);
                if(!done || result!==expected) $fatal(1,"completion lost/reentered");
            end
            start=0;ack=1;@(negedge clk);ack=0;
            if(done) $fatal(1,"ack did not retire");
            checks=checks+1;
        end
    endtask
    initial begin
        edge_values[0]=0;edge_values[1]=1;edge_values[2]=32'hffffffff;
        edge_values[3]=32'h80000000;edge_values[4]=32'h7fffffff;
        edge_values[5]=32'hffff0000;edge_values[6]=32'h55555555;edge_values[7]=32'haaaaaaaa;
        ops[0]=`EXE_MUL_OP;ops[1]=`EXE_MULH_OP;ops[2]=`EXE_MULHSU_OP;ops[3]=`EXE_MULHU_OP;
        repeat(3) @(negedge clk);rst_n=1;
        for(i=0;i<8;i=i+1) for(j=0;j<8;j=j+1) for(k=0;k<4;k=k+1)
            run_case(edge_values[i],edge_values[j],ops[k]);
        for(i=0;i<1000;i=i+1) run_case($random(seed),$random(seed),ops[i%4]);
        // Cancel in PRODUCT and COMPLETE, then issue a distinct request immediately.
        for(i=0;i<2;i=i+1) begin
            @(negedge clk);a=123;b=456;op=`EXE_MUL_OP;start=1;
            repeat(i+1) @(negedge clk);cancel=1;start=0;
            @(negedge clk);cancel=0;
            if(done) $fatal(1,"cancel completion");
            run_case(32'h80000000,32'hffffffff,`EXE_MULH_OP);
        end
        @(negedge clk);start=1;
        @(negedge clk);rst_n=0;start=0;
        @(negedge clk);rst_n=1;
        if(done) $fatal(1,"reset completion");
        run_case(17,19,`EXE_MUL_OP);
        $display("TEST_PASS multiplier_pipeline checks=%0d seed=4d554c31",checks);$finish;
    end
    initial begin #2000000;$fatal(1,"watchdog");end
endmodule

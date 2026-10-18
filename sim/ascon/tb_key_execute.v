`timescale 1ns/1ps
`include "defines.v"
module tb_key_execute;
    reg clk=0,rst_n=0,hold=0,irq=0;
    reg [5:0] func=`EXE_NOP_OP;
    reg [31:0] rs1=0,rs2=0;
    wire stall;
    integer checks=0,errors=0;
    always #5 clk=~clk;
    ex_stage dut(.clk(clk),.rst_n(rst_n),.ex_hold(hold),.id_pc(32'h10000000),
        .id_rs1(rs1),.id_rs2(rs2),.id_op_sel(3'd0),.id_func_sel(func),
        .id_reg_w_en(1'b0),.id_mem_w_en(1'b0),.id_imm(32'd0),.id_w_reg_waddr(5'd0),
        .id_mem_r_en(1'b0),.csr_w_en(1'b0),.id_csr_addr(12'd0),.csr_rdata(32'd0),
        .is_word_op(1'b0),.is_branch(1'b0),.pred_taken(1'b0),.pred_target(32'd0),
        .inter_req(irq),.id_illegal_inst_en(1'b0),.id_inst(32'h13),.ex_stall_req(stall));
    task check(input bit ok,input [255:0] label);
        begin checks=checks+1;if(!ok) begin errors=errors+1;$display("FAIL %0s",label);end end
    endtask
    initial begin
        repeat(3) @(negedge clk);rst_n=1;
        func=`EXE_ASCON_W_OP;rs1=32'h12345678;rs2=0;hold=1;
        repeat(3) @(negedge clk);check(dut.u_ascon_ise.state===0,"held word does not commit");
        hold=0;@(negedge clk);func=`EXE_NOP_OP;
        check(dut.u_ascon_ise.state[31:0]===32'h12345678,"write commits on advance");
        func=`EXE_ASCON_W_OP;rs1=32'hbad;rs2=32'h10000000;
        @(negedge clk);func=`EXE_ASCON_RD_OP;rs1=32'h10000000;#1;
        check(dut.ascon_rd_data===0,"full index range checked");
        check(dut.u_ascon_ise.state[31:0]===32'h12345678,"invalid index no alias");
        func=`EXE_ASCON_P12_OP;hold=1;
        repeat(30) @(negedge clk);
        check(dut.ascon_perm_done && !stall,"done survives hold");
        hold=0;@(negedge clk);func=`EXE_ASCON_P8_OP;
        repeat(4) @(negedge clk);irq=1;
        @(negedge clk);func=`EXE_NOP_OP;irq=0;
        repeat(24) @(negedge clk);
        check(dut.u_ascon_ise.state===0 && !dut.ascon_perm_done,"interrupt cancels and clears");
        func=`EXE_ASCON_W_OP;rs1=32'h55;rs2=1;irq=1;
        @(negedge clk);func=`EXE_NOP_OP;irq=0;
        check(dut.u_ascon_ise.state===0,"squashed write cannot commit");
        // Multiply completion must survive an unrelated downstream hold.
        func=`EXE_MULH_OP;rs1=32'h80000000;rs2=32'hffffffff;hold=1;
        repeat(12) @(negedge clk);
        check(dut.mul_done && !stall && dut.mul_result===0,"multiply held completion");
        repeat(8) @(negedge clk);
        check(dut.mul_done && dut.mul_result===0,"multiply no reentry");
        hold=0;@(negedge clk);func=`EXE_MUL_OP;rs1=7;rs2=9;hold=1;
        repeat(4) @(negedge clk);
        check(dut.mul_done && dut.mul_result===63,"consecutive multiply");
        irq=1;@(negedge clk);func=`EXE_NOP_OP;irq=0;hold=0;
        check(!dut.mul_done,"interrupt aborts multiply");
        $display("SUMMARY EXECUTE checks=%0d errors=%0d",checks,errors);
        if(errors) $fatal(1,"execute interaction");$finish;
    end
    initial begin #20000;$fatal(1,"watchdog");end
endmodule

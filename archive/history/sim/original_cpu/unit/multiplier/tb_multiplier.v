`timescale 1ns / 1ps
`include "defines.v"

module tb_multiplier;
    localparam XLEN = 32;

    reg              clk;
    reg              rst_n;
    reg              mul_start;
    reg  [XLEN-1:0]  rs1_data;
    reg  [XLEN-1:0]  rs2_data;
    reg  [5:0]       func_sel;
    wire [XLEN-1:0]  mul_result;
    wire             mul_done;

    integer errors;

    multiplier #(.XLEN(XLEN)) dut (
        .clk(clk),
        .rst_n(rst_n),
        .mul_start(mul_start),
        .rs1_data(rs1_data),
        .rs2_data(rs2_data),
        .func_sel(func_sel),
        .mul_result(mul_result),
        .mul_done(mul_done)
    );

`ifdef DUMP_FSDB
    initial begin
        $fsdbDumpfile("tb_multiplier.fsdb");
        $fsdbDumpvars(0, tb_multiplier, "+all");
    end
`else
    initial begin
        $dumpfile("tb_multiplier.vcd");
        $dumpvars(0, tb_multiplier);
    end
`endif

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task run_mul;
        input [XLEN-1:0] a;
        input [XLEN-1:0] b;
        input [5:0] op;
        input [XLEN-1:0] expected;
        input [255:0] name;
        integer timeout;
        begin
            rs1_data = a;
            rs2_data = b;
            func_sel = op;
            mul_start = 1'b1;
            timeout = 0;
            while (!mul_done && timeout < 10) begin
                @(posedge clk);
                #1;
                timeout = timeout + 1;
            end
            mul_start = 1'b0;
            if (!mul_done) begin
                $display("[FAIL] %0s timeout", name);
                errors = errors + 1;
            end else if (mul_result !== expected) begin
                $display("[FAIL] %0s actual=0x%08h expected=0x%08h", name, mul_result, expected);
                errors = errors + 1;
            end else begin
                $display("[PASS] %0s = 0x%08h", name, mul_result);
            end
            @(posedge clk);
            #1;
        end
    endtask

    initial begin
        errors = 0;
        rst_n = 1'b0;
        mul_start = 1'b0;
        rs1_data = 32'h0;
        rs2_data = 32'h0;
        func_sel = `EXE_MUL_OP;

        repeat (2) @(posedge clk);
        rst_n = 1'b1;

        run_mul(32'd7, 32'd9, `EXE_MUL_OP, 32'd63, "MUL low result");
        run_mul(32'd0, 32'hDEAD_BEEF, `EXE_MUL_OP, 32'd0, "MUL zero operand boundary");
        run_mul(32'hFFFF_FFFC, 32'd3, `EXE_MUL_OP, 32'hFFFF_FFF4, "MUL wraps low 32 bits");
        run_mul(32'hFFFF_FFFE, 32'hFFFF_FFFD, `EXE_MUL_OP, 32'd6, "MUL negative times negative low result");
        run_mul(32'hFFFF_FFF6, 32'd3, `EXE_MULH_OP, 32'hFFFF_FFFF, "MULH signed high result");
        run_mul(32'hFFFF_FFF6, 32'd3, `EXE_MULHSU_OP, 32'hFFFF_FFFF, "MULHSU signed x unsigned");
        run_mul(32'hFFFF_FFF0, 32'h0001_0000, `EXE_MULHU_OP, 32'h0000_FFFF, "MULHU unsigned high result");
        run_mul(32'h7FFF_FFFF, 32'd2, `EXE_MUL_OP, 32'hFFFF_FFFE, "MUL max positive overflow low part");
        run_mul(32'hFFFF_FFFF, 32'hFFFF_FFFF, `EXE_MULHU_OP, 32'hFFFF_FFFE, "MULHU max unsigned high overflow");

        if (errors == 0) begin
            $display("[RESULT] tb_multiplier PASS");
        end else begin
            $display("[RESULT] tb_multiplier FAIL errors=%0d", errors);
            $fatal(1);
        end
        $finish;
    end
endmodule

`timescale 1ns / 1ps
`include "defines.v"

module tb_divider;
    localparam XLEN = 32;

    reg              clk;
    reg              rst_n;
    reg              div_start;
    reg  [XLEN-1:0]  rs1_data;
    reg  [XLEN-1:0]  rs2_data;
    reg  [5:0]       func_sel;
    reg              is_word_op;
    wire [XLEN-1:0]  div_result;
    wire             div_done;

    integer errors;

    divider #(.XLEN(XLEN)) dut (
        .clk(clk),
        .rst_n(rst_n),
        .div_start(div_start),
        .rs1_data(rs1_data),
        .rs2_data(rs2_data),
        .func_sel(func_sel),
        .is_word_op(is_word_op),
        .div_result(div_result),
        .div_done(div_done)
    );

`ifdef DUMP_FSDB
    initial begin
        $fsdbDumpfile("tb_divider.fsdb");
        $fsdbDumpvars(0, tb_divider, "+all");
    end
`else
    initial begin
        $dumpfile("tb_divider.vcd");
        $dumpvars(0, tb_divider);
    end
`endif

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task run_div;
        input [XLEN-1:0] a;
        input [XLEN-1:0] b;
        input [5:0] op;
        input word_mode;
        input [XLEN-1:0] expected;
        input [255:0] name;
        integer timeout;
        begin
            rs1_data = a;
            rs2_data = b;
            func_sel = op;
            is_word_op = word_mode;
            #1;
            div_start = 1'b1;
            timeout = 0;
            while (!div_done && timeout < 80) begin
                @(posedge clk);
                #1;
                timeout = timeout + 1;
            end
            div_start = 1'b0;
            if (!div_done) begin
                $display("[FAIL] %0s timeout", name);
                errors = errors + 1;
            end else if (div_result !== expected) begin
                $display("[FAIL] %0s actual=0x%08h expected=0x%08h", name, div_result, expected);
                errors = errors + 1;
            end else begin
                $display("[PASS] %0s = 0x%08h", name, div_result);
            end
            @(posedge clk);
            #1;
        end
    endtask

    initial begin
        errors = 0;
        rst_n = 1'b0;
        div_start = 1'b0;
        rs1_data = 32'h0;
        rs2_data = 32'h0;
        func_sel = `EXE_DIV_OP;
        is_word_op = 1'b0;

        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        run_div(32'd0, 32'd7, `EXE_DIVU_OP, 1'b0, 32'd0, "DIVU zero dividend boundary");
        run_div(32'd100, 32'd7, `EXE_DIVU_OP, 1'b0, 32'd14, "DIVU basic quotient");
        run_div(32'd7, 32'd7, `EXE_DIVU_OP, 1'b0, 32'd1, "DIVU equal operands boundary");
        run_div(32'd3, 32'd7, `EXE_DIVU_OP, 1'b0, 32'd0, "DIVU dividend smaller than divisor");
        run_div(32'd3, 32'd7, `EXE_REMU_OP, 1'b0, 32'd3, "REMU dividend smaller than divisor");
        run_div(32'hFFFF_FF9C, 32'd7, `EXE_DIV_OP, 1'b0, -32'sd14, "DIV signed negative quotient");
        run_div(32'd100, 32'hFFFF_FFF9, `EXE_DIV_OP, 1'b0, -32'sd14, "DIV signed negative divisor");
        run_div(32'd100, 32'd7, `EXE_REMU_OP, 1'b0, 32'd2, "REMU basic remainder");
        run_div(32'hFFFF_FF9C, 32'd7, `EXE_REM_OP, 1'b0, -32'sd2, "REM signed negative remainder");
        run_div(32'd100, 32'hFFFF_FFF9, `EXE_REM_OP, 1'b0, 32'd2, "REM signed negative divisor remainder");
        run_div(32'd1234, 32'd0, `EXE_DIVU_OP, 1'b0, 32'hFFFF_FFFF, "divide by zero quotient all ones");
        run_div(32'd1234, 32'd0, `EXE_REMU_OP, 1'b0, 32'd1234, "divide by zero remainder keeps dividend");
        run_div(32'h8000_0000, 32'hFFFF_FFFF, `EXE_DIV_OP, 1'b0, 32'h8000_0000, "DIV signed overflow boundary");

        if (errors == 0) begin
            $display("[RESULT] tb_divider PASS");
        end else begin
            $display("[RESULT] tb_divider FAIL errors=%0d", errors);
            $fatal(1);
        end
        $finish;
    end
endmodule

`timescale 1ns / 1ps

module tb_bypass;
    localparam XLEN = 32;

    reg  [XLEN-1:0] rs1_i;
    reg  [XLEN-1:0] rs2_i;
    reg  [XLEN-1:0] ex_mem_rd_data;
    reg  [XLEN-1:0] mem_wb_rd_data;
    reg             sel_ex_mem_rs1;
    reg             sel_mem_wb_rs1;
    reg             sel_ex_mem_rs2;
    reg             sel_mem_wb_rs2;
    wire [XLEN-1:0] rs1_o;
    wire [XLEN-1:0] rs2_o;

    integer errors;

    bypass #(.XLEN(XLEN)) dut (
        .rs1_i(rs1_i),
        .rs2_i(rs2_i),
        .ex_mem_rd_data(ex_mem_rd_data),
        .mem_wb_rd_data(mem_wb_rd_data),
        .sel_ex_mem_rs1(sel_ex_mem_rs1),
        .sel_mem_wb_rs1(sel_mem_wb_rs1),
        .sel_ex_mem_rs2(sel_ex_mem_rs2),
        .sel_mem_wb_rs2(sel_mem_wb_rs2),
        .rs1_o(rs1_o),
        .rs2_o(rs2_o)
    );

`ifdef DUMP_FSDB
    initial begin
        $fsdbDumpfile("tb_bypass.fsdb");
        $fsdbDumpvars(0, tb_bypass, "+all");
    end
`else
    initial begin
        $dumpfile("tb_bypass.vcd");
        $dumpvars(0, tb_bypass);
    end
`endif

    task expect_word;
        input [XLEN-1:0] actual;
        input [XLEN-1:0] expected;
        input [255:0] name;
        begin
            if (actual !== expected) begin
                $display("[FAIL] %0s actual=0x%08h expected=0x%08h", name, actual, expected);
                errors = errors + 1;
            end else begin
                $display("[PASS] %0s = 0x%08h", name, actual);
            end
        end
    endtask

    initial begin
        errors = 0;
        rs1_i = 32'h1111_1111;
        rs2_i = 32'h2222_2222;
        ex_mem_rd_data = 32'hAAAA_AAAA;
        mem_wb_rd_data = 32'hCCCC_CCCC;

        sel_ex_mem_rs1 = 0; sel_mem_wb_rs1 = 0;
        sel_ex_mem_rs2 = 0; sel_mem_wb_rs2 = 0;
        #1;
        expect_word(rs1_o, rs1_i, "default rs1 path");
        expect_word(rs2_o, rs2_i, "default rs2 path");

        sel_mem_wb_rs1 = 1;
        sel_mem_wb_rs2 = 1;
        #1;
        expect_word(rs1_o, mem_wb_rd_data, "rs1 wb bypass");
        expect_word(rs2_o, mem_wb_rd_data, "rs2 wb bypass");

        sel_ex_mem_rs1 = 1;
        sel_mem_wb_rs1 = 1;
        sel_ex_mem_rs2 = 1;
        sel_mem_wb_rs2 = 1;
        #1;
        expect_word(rs1_o, ex_mem_rd_data, "rs1 priority ex_mem over wb");
        expect_word(rs2_o, ex_mem_rd_data, "rs2 priority ex_mem over wb");

        sel_ex_mem_rs1 = 0;
        sel_mem_wb_rs1 = 0;
        sel_ex_mem_rs2 = 0;
        sel_mem_wb_rs2 = 1;
        #1;
        expect_word(rs2_o, mem_wb_rd_data, "rs2 wb bypass path");

        if (errors == 0) begin
            $display("[RESULT] tb_bypass PASS");
        end else begin
            $display("[RESULT] tb_bypass FAIL errors=%0d", errors);
            $fatal(1);
        end
        $finish;
    end
endmodule

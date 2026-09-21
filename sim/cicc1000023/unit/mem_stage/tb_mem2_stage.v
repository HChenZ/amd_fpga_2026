`timescale 1ns / 1ps
`include "defines.v"

module tb_mem2_stage;
    localparam XLEN = 32;

    reg  [4:0]          mem1_reg_addr;
    reg                 mem1_reg_w_en;
    reg  [XLEN-1:0]     mem1_rd_data;
    reg  [2:0]          mem1_op_sel;
    reg  [5:0]          mem1_func_sel;
    reg  [2:0]          byte_offset;
    reg  [XLEN-1:0]     mem_r_data;
    wire                mem2_reg_w_en;
    wire [XLEN-1:0]     mem2_rd_data;
    wire [4:0]          mem2_reg_addr;

    integer errors;

    mem2_stage #(.XLEN(XLEN)) dut (
        .mem1_reg_addr(mem1_reg_addr),
        .mem1_reg_w_en(mem1_reg_w_en),
        .mem1_rd_data(mem1_rd_data),
        .mem1_op_sel(mem1_op_sel),
        .mem1_func_sel(mem1_func_sel),
        .byte_offset(byte_offset),
        .mem_r_data(mem_r_data),
        .mem2_reg_w_en(mem2_reg_w_en),
        .mem2_rd_data(mem2_rd_data),
        .mem2_reg_addr(mem2_reg_addr)
    );

`ifdef DUMP_FSDB
    initial begin
        $fsdbDumpfile("tb_mem2_stage.fsdb");
        $fsdbDumpvars(0, tb_mem2_stage, "+all");
    end
`else
    initial begin
        $dumpfile("tb_mem2_stage.vcd");
        $dumpvars(0, tb_mem2_stage);
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
        mem1_reg_addr = 5'd3;
        mem1_reg_w_en = 1;
        mem1_rd_data = 32'hCAFE_BABE;
        mem_r_data = 32'h80FF_7F01;
        byte_offset = 0;

        mem1_op_sel = `EXE_RES_LOAD_STORE;
        mem1_func_sel = `EXE_LB_OP;
        #1 expect_word(mem2_rd_data, 32'h0000_0001, "LB sign extend positive");

        byte_offset = 3'd3;
        #1 expect_word(mem2_rd_data, 32'hFFFF_FF80, "LB sign extend negative with offset");

        mem1_func_sel = `EXE_LBU_OP;
        #1 expect_word(mem2_rd_data, 32'h0000_0080, "LBU zero extend");

        mem_r_data = 32'h8001_FF02;
        byte_offset = 3'd2;
        mem1_func_sel = `EXE_LH_OP;
        #1 expect_word(mem2_rd_data, 32'hFFFF_8001, "LH sign extend negative half");

        mem1_func_sel = `EXE_LHU_OP;
        #1 expect_word(mem2_rd_data, 32'h0000_8001, "LHU zero extend half");

        byte_offset = 0;
        mem_r_data = 32'h89AB_CDEF;
        mem1_func_sel = `EXE_LW_OP;
        #1 expect_word(mem2_rd_data, 32'h89AB_CDEF, "LW full word");

        mem1_op_sel = `EXE_RES_ARITH;
        #1 expect_word(mem2_rd_data, 32'hCAFE_BABE, "non-load path bypass");

        if (errors == 0) begin
            $display("[RESULT] tb_mem2_stage PASS");
        end else begin
            $display("[RESULT] tb_mem2_stage FAIL errors=%0d", errors);
            $fatal(1);
        end
        $finish;
    end
endmodule

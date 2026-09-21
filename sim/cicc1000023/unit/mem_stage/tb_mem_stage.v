`timescale 1ns / 1ps
`include "defines.v"

module tb_mem_stage;
    reg                  ex32_reg_w_en;
    reg  [31:0]          ex32_rd_data;
    reg  [31:0]          ex32_mem_addr;
    reg  [4:0]           ex32_reg_addr;
    reg  [2:0]           ex32_op_sel;
    reg  [5:0]           ex32_func_sel;
    reg  [31:0]          mem32_r_data;
    wire                 mem32_reg_w_en;
    wire [31:0]          mem32_rd_data;
    wire [4:0]           mem32_reg_addr;
    wire [2:0]           mem32_op_sel;

    reg                  ex64_reg_w_en;
    reg  [63:0]          ex64_rd_data;
    reg  [63:0]          ex64_mem_addr;
    reg  [4:0]           ex64_reg_addr;
    reg  [2:0]           ex64_op_sel;
    reg  [5:0]           ex64_func_sel;
    reg  [63:0]          mem64_r_data;
    wire                 mem64_reg_w_en;
    wire [63:0]          mem64_rd_data;
    wire [4:0]           mem64_reg_addr;
    wire [2:0]           mem64_op_sel;

    integer errors;

    mem_stage #(.XLEN(32)) dut32 (
        .ex_reg_w_en(ex32_reg_w_en),
        .ex_rd_data(ex32_rd_data),
        .ex_mem_addr(ex32_mem_addr),
        .ex_reg_addr(ex32_reg_addr),
        .ex_op_sel(ex32_op_sel),
        .ex_func_sel(ex32_func_sel),
        .mem_r_data(mem32_r_data),
        .mem_reg_w_en(mem32_reg_w_en),
        .mem_rd_data(mem32_rd_data),
        .mem_reg_addr(mem32_reg_addr),
        .mem_op_sel(mem32_op_sel)
    );

    mem_stage #(.XLEN(64)) dut64 (
        .ex_reg_w_en(ex64_reg_w_en),
        .ex_rd_data(ex64_rd_data),
        .ex_mem_addr(ex64_mem_addr),
        .ex_reg_addr(ex64_reg_addr),
        .ex_op_sel(ex64_op_sel),
        .ex_func_sel(ex64_func_sel),
        .mem_r_data(mem64_r_data),
        .mem_reg_w_en(mem64_reg_w_en),
        .mem_rd_data(mem64_rd_data),
        .mem_reg_addr(mem64_reg_addr),
        .mem_op_sel(mem64_op_sel)
    );

`ifdef DUMP_FSDB
    initial begin
        $fsdbDumpfile("tb_mem_stage.fsdb");
        $fsdbDumpvars(0, tb_mem_stage, "+all");
    end
`else
    initial begin
        $dumpfile("tb_mem_stage.vcd");
        $dumpvars(0, tb_mem_stage);
    end
`endif

    task expect_bit;
        input actual;
        input expected;
        input [255:0] name;
        begin
            if (actual !== expected) begin
                $display("[FAIL] %0s actual=%0b expected=%0b", name, actual, expected);
                errors = errors + 1;
            end else begin
                $display("[PASS] %0s = %0b", name, actual);
            end
        end
    endtask

    task expect5;
        input [4:0] actual;
        input [4:0] expected;
        input [255:0] name;
        begin
            if (actual !== expected) begin
                $display("[FAIL] %0s actual=%0d expected=%0d", name, actual, expected);
                errors = errors + 1;
            end else begin
                $display("[PASS] %0s = %0d", name, actual);
            end
        end
    endtask

    task expect32;
        input [31:0] actual;
        input [31:0] expected;
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

    task expect64;
        input [63:0] actual;
        input [63:0] expected;
        input [255:0] name;
        begin
            if (actual !== expected) begin
                $display("[FAIL] %0s actual=0x%016h expected=0x%016h", name, actual, expected);
                errors = errors + 1;
            end else begin
                $display("[PASS] %0s = 0x%016h", name, actual);
            end
        end
    endtask

    initial begin
        errors = 0;

        ex32_reg_w_en = 1'b1;
        ex32_rd_data = 32'hCAFE_BABE;
        ex32_mem_addr = 32'h0000_0000;
        ex32_reg_addr = 5'd9;
        ex32_op_sel = `EXE_RES_ARITH;
        ex32_func_sel = `EXE_ADD_OP;
        mem32_r_data = 32'h1234_5678;
        #1;
        expect32(mem32_rd_data, 32'hCAFE_BABE, "RV32 non-load passthrough");
        expect_bit(mem32_reg_w_en, 1'b1, "RV32 reg write enable passthrough");
        expect5(mem32_reg_addr, 5'd9, "RV32 register address passthrough");

        ex32_op_sel = `EXE_RES_LOAD_STORE;
        ex32_func_sel = `EXE_LB_OP;
        ex32_mem_addr = 32'h0000_0000;
        mem32_r_data = 32'h80FF_7F01;
        #1;
        expect32(mem32_rd_data, 32'h0000_0001, "RV32 LB positive sign extension");

        ex32_mem_addr = 32'h0000_0003;
        #1;
        expect32(mem32_rd_data, 32'hFFFF_FF80, "RV32 LB negative sign extension");

        ex32_func_sel = `EXE_LBU_OP;
        #1;
        expect32(mem32_rd_data, 32'h0000_0080, "RV32 LBU zero extension");

        ex32_func_sel = `EXE_LH_OP;
        ex32_mem_addr = 32'h0000_0002;
        mem32_r_data = 32'h8001_FF02;
        #1;
        expect32(mem32_rd_data, 32'hFFFF_8001, "RV32 LH sign extension");

        ex32_func_sel = `EXE_LHU_OP;
        #1;
        expect32(mem32_rd_data, 32'h0000_8001, "RV32 LHU zero extension");

        ex32_func_sel = `EXE_LW_OP;
        ex32_mem_addr = 32'h0000_0000;
        mem32_r_data = 32'h89AB_CDEF;
        #1;
        expect32(mem32_rd_data, 32'h89AB_CDEF, "RV32 LW word output");

        ex64_reg_w_en = 1'b1;
        ex64_rd_data = 64'h0123_4567_89AB_CDEF;
        ex64_mem_addr = 64'h0000_0000_0000_0000;
        ex64_reg_addr = 5'd12;
        ex64_op_sel = `EXE_RES_ARITH;
        ex64_func_sel = `EXE_ADD_OP;
        mem64_r_data = 64'hFEDC_BA98_7654_3210;
        #1;
        expect64(mem64_rd_data, 64'h0123_4567_89AB_CDEF, "RV64 non-load passthrough");
        expect_bit(mem64_reg_w_en, 1'b1, "RV64 reg write enable passthrough");
        expect5(mem64_reg_addr, 5'd12, "RV64 register address passthrough");

        ex64_op_sel = `EXE_RES_LOAD_STORE;
        ex64_func_sel = `EXE_LD_OP;
        ex64_mem_addr = 64'h0000_0000_0000_0000;
        mem64_r_data = 64'h1122_3344_5566_7788;
        #1;
        expect64(mem64_rd_data, 64'h1122_3344_5566_7788, "RV64 LD doubleword output");

        ex64_func_sel = `EXE_LW_OP;
        mem64_r_data = 64'h0000_0000_89AB_CDEF;
        #1;
        expect64(mem64_rd_data, 64'hFFFF_FFFF_89AB_CDEF, "RV64 LW sign extension");

        ex64_func_sel = `EXE_LWU_OP;
        #1;
        expect64(mem64_rd_data, 64'h0000_0000_89AB_CDEF, "RV64 LWU zero extension");

        ex64_func_sel = `EXE_LB_OP;
        ex64_mem_addr = 64'h0000_0000_0000_0007;
        mem64_r_data = 64'h8066_5544_3322_1100;
        #1;
        expect64(mem64_rd_data, 64'hFFFF_FFFF_FFFF_FF80, "RV64 LB high-byte sign extension");

        ex64_func_sel = `EXE_LH_OP;
        ex64_mem_addr = 64'h0000_0000_0000_0004;
        mem64_r_data = 64'h0000_8001_1234_5678;
        #1;
        expect64(mem64_rd_data, 64'hFFFF_FFFF_FFFF_8001, "RV64 LH sign extension");

        ex64_func_sel = `EXE_LHU_OP;
        #1;
        expect64(mem64_rd_data, 64'h0000_0000_0000_8001, "RV64 LHU zero extension");

        if (errors == 0) begin
            $display("[RESULT] tb_mem_stage PASS");
        end else begin
            $display("[RESULT] tb_mem_stage FAIL errors=%0d", errors);
            $fatal(1);
        end
        $finish;
    end
endmodule

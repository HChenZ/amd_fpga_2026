`timescale 1ns / 1ps
`include "defines.v"

module tb_ex_mem;
    localparam XLEN = 32;

    reg                  clk;
    reg                  rst_n;
    reg                  flush;
    reg                  stall;
    reg                  ex_reg_w_en_i;
    reg                  ex_mem_w_en_i;
    reg  [XLEN-1:0]      ex_rd_data_i;
    reg  [XLEN-1:0]      ex_mem_addr_i;
    reg  [4:0]           ex_reg_addr_i;
    reg  [2:0]           ex_op_sel_i;
    reg  [5:0]           ex_func_sel_i;
    reg                  ex_mem_r_en_i;
    reg                  ex_is_mul_i;
    reg                  inst_valid_i;

    wire                 ex_reg_w_en_o;
    wire                 ex_mem_w_en_o;
    wire [XLEN-1:0]      ex_rd_data_o;
    wire [XLEN-1:0]      ex_mem_addr_o;
    wire [4:0]           ex_reg_addr_o;
    wire [2:0]           ex_op_sel_o;
    wire [5:0]           ex_func_sel_o;
    wire                 ex_mem_r_en_o;
    wire                 ex_is_mul_o;
    wire                 inst_valid_o;

    integer errors;

    ex_mem #(.XLEN(XLEN)) dut (
        .clk(clk),
        .rst_n(rst_n),
        .ex_reg_w_en_i(ex_reg_w_en_i),
        .ex_mem_w_en_i(ex_mem_w_en_i),
        .ex_rd_data_i(ex_rd_data_i),
        .ex_mem_addr_i(ex_mem_addr_i),
        .ex_reg_addr_i(ex_reg_addr_i),
        .ex_op_sel_i(ex_op_sel_i),
        .ex_func_sel_i(ex_func_sel_i),
        .ex_mem_r_en_i(ex_mem_r_en_i),
        .ex_is_mul_i(ex_is_mul_i),
        .inst_valid_i(inst_valid_i),
        .inst_valid_o(inst_valid_o),
        .flush(flush),
        .stall(stall),
        .ex_reg_w_en_o(ex_reg_w_en_o),
        .ex_mem_w_en_o(ex_mem_w_en_o),
        .ex_rd_data_o(ex_rd_data_o),
        .ex_mem_addr_o(ex_mem_addr_o),
        .ex_reg_addr_o(ex_reg_addr_o),
        .ex_op_sel_o(ex_op_sel_o),
        .ex_func_sel_o(ex_func_sel_o),
        .ex_mem_r_en_o(ex_mem_r_en_o),
        .ex_is_mul_o(ex_is_mul_o)
    );

`ifdef DUMP_FSDB
    initial begin
        $fsdbDumpfile("tb_ex_mem.fsdb");
        $fsdbDumpvars(0, tb_ex_mem, "+all");
    end
`else
    initial begin
        $dumpfile("tb_ex_mem.vcd");
        $dumpvars(0, tb_ex_mem);
    end
`endif

    initial clk = 1'b0;
    always #5 clk = ~clk;

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

    task expect_bus5;
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

    initial begin
        errors = 0;
        rst_n = 0;
        flush = 0;
        stall = 0;
        ex_reg_w_en_i = 0;
        ex_mem_w_en_i = 0;
        ex_rd_data_i = 0;
        ex_mem_addr_i = 0;
        ex_reg_addr_i = 0;
        ex_op_sel_i = `EXE_RES_NOP;
        ex_func_sel_i = `EXE_NOP_OP;
        ex_mem_r_en_i = 0;
        ex_is_mul_i = 0;
        inst_valid_i = 0;

        repeat (2) @(posedge clk);
        #1;
        expect_bit(ex_reg_w_en_o, 1'b0, "reset clears reg write enable");
        expect_word(ex_rd_data_o, {XLEN{1'b0}}, "reset clears rd data");
        expect_bit(inst_valid_o, 1'b0, "reset clears valid");

        rst_n = 1;
        ex_reg_w_en_i = 1'b1;
        ex_mem_w_en_i = 1'b0;
        ex_rd_data_i = 32'hCAFE_BABE;
        ex_mem_addr_i = 32'h1000_1004;
        ex_reg_addr_i = 5'd9;
        ex_op_sel_i = `EXE_RES_LOAD_STORE;
        ex_func_sel_i = `EXE_LW_OP;
        ex_mem_r_en_i = 1'b1;
        ex_is_mul_i = 1'b0;
        inst_valid_i = 1'b1;
        @(posedge clk); #1;
        expect_bit(ex_reg_w_en_o, 1'b1, "normal latch reg write enable");
        expect_bit(ex_mem_r_en_o, 1'b1, "normal latch memory read enable");
        expect_word(ex_rd_data_o, 32'hCAFE_BABE, "normal latch rd data");
        expect_word(ex_mem_addr_o, 32'h1000_1004, "normal latch memory address");
        expect_bus5(ex_reg_addr_o, 5'd9, "normal latch register address");
        expect_bit(inst_valid_o, 1'b1, "normal latch valid");

        stall = 1'b1;
        ex_reg_w_en_i = 1'b0;
        ex_mem_w_en_i = 1'b1;
        ex_rd_data_i = 32'hDEAD_BEEF;
        ex_mem_addr_i = 32'h2000_0000;
        ex_reg_addr_i = 5'd17;
        ex_op_sel_i = `EXE_RES_ARITH;
        ex_func_sel_i = `EXE_ADD_OP;
        ex_mem_r_en_i = 1'b0;
        inst_valid_i = 1'b0;
        @(posedge clk); #1;
        expect_bit(ex_reg_w_en_o, 1'b1, "stall holds reg write enable");
        expect_bit(ex_mem_r_en_o, 1'b1, "stall holds memory read enable");
        expect_word(ex_rd_data_o, 32'hCAFE_BABE, "stall holds rd data");
        expect_word(ex_mem_addr_o, 32'h1000_1004, "stall holds memory address");
        expect_bus5(ex_reg_addr_o, 5'd9, "stall holds register address");
        expect_bit(inst_valid_o, 1'b1, "stall holds valid");

        stall = 1'b0;
        flush = 1'b1;
        @(posedge clk); #1;
        flush = 1'b0;
        expect_bit(ex_reg_w_en_o, 1'b0, "flush clears reg write enable");
        expect_bit(ex_mem_w_en_o, 1'b0, "flush clears memory write enable");
        expect_bit(ex_mem_r_en_o, 1'b0, "flush clears memory read enable");
        expect_bus5(ex_reg_addr_o, 5'd0, "flush clears register address");
        expect_bit(inst_valid_o, 1'b0, "flush clears valid");

        ex_reg_w_en_i = 1'b1;
        ex_mem_w_en_i = 1'b1;
        ex_rd_data_i = 32'h1122_3344;
        ex_mem_addr_i = 32'h3000_0008;
        ex_reg_addr_i = 5'd3;
        ex_op_sel_i = `EXE_RES_LOAD_STORE;
        ex_func_sel_i = `EXE_SW_OP;
        ex_mem_r_en_i = 1'b0;
        inst_valid_i = 1'b1;
        @(posedge clk); #1;
        expect_bit(ex_mem_w_en_o, 1'b1, "resume latch store write enable");
        expect_word(ex_rd_data_o, 32'h1122_3344, "resume latch store data");
        expect_word(ex_mem_addr_o, 32'h3000_0008, "resume latch store address");
        expect_bus5(ex_reg_addr_o, 5'd3, "resume latch register address");
        expect_bit(inst_valid_o, 1'b1, "resume latch valid");

        if (errors == 0) begin
            $display("[RESULT] tb_ex_mem PASS");
        end else begin
            $display("[RESULT] tb_ex_mem FAIL errors=%0d", errors);
            $fatal(1);
        end
        $finish;
    end
endmodule

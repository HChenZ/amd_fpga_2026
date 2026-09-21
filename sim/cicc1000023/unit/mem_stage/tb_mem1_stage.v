`timescale 1ns / 1ps
`include "defines.v"

module tb_mem1_stage;
    localparam XLEN = 32;

    reg                 clk;
    reg                 rst_n;
    reg                 ex_reg_w_en;
    reg                 ex_mem_w_en;
    reg  [XLEN-1:0]     ex_rd_data;
    reg  [XLEN-1:0]     ex_mem_addr;
    reg  [4:0]          ex_reg_addr;
    reg  [2:0]          ex_op_sel;
    reg  [5:0]          ex_func_sel;
    reg                 ex_mem_r_en;
    reg                 inst_valid_i;
    wire                inst_valid_o;
    wire [4:0]          mem1_reg_addr;
    wire                mem1_reg_w_en;
    wire [XLEN-1:0]     mem1_rd_data;
    wire [2:0]          mem1_op_sel;
    wire [5:0]          mem1_func_sel;
    wire [2:0]          mem1_byte_offset;
    wire                mem_r_en;
    wire                mem1_r_en;
    wire [XLEN-1:0]     mem1_addr;
    wire [XLEN-1:0]     mem1_w_data;
    wire                mem1_w_en;
    wire [(XLEN/8)-1:0] mem1_w_mask;

    integer errors;

    mem1_stage #(.XLEN(XLEN)) dut (
        .clk(clk),
        .rst_n(rst_n),
        .ex_reg_w_en(ex_reg_w_en),
        .ex_mem_w_en(ex_mem_w_en),
        .ex_rd_data(ex_rd_data),
        .ex_mem_addr(ex_mem_addr),
        .ex_reg_addr(ex_reg_addr),
        .ex_op_sel(ex_op_sel),
        .ex_func_sel(ex_func_sel),
        .ex_mem_r_en(ex_mem_r_en),
        .inst_valid_i(inst_valid_i),
        .inst_valid_o(inst_valid_o),
        .mem1_reg_addr(mem1_reg_addr),
        .mem1_reg_w_en(mem1_reg_w_en),
        .mem1_rd_data(mem1_rd_data),
        .mem1_op_sel(mem1_op_sel),
        .mem1_func_sel(mem1_func_sel),
        .mem1_byte_offset(mem1_byte_offset),
        .mem_r_en(mem_r_en),
        .mem1_r_en(mem1_r_en),
        .mem1_addr(mem1_addr),
        .mem1_w_data(mem1_w_data),
        .mem1_w_en(mem1_w_en),
        .mem1_w_mask(mem1_w_mask)
    );

`ifdef DUMP_FSDB
    initial begin
        $fsdbDumpfile("tb_mem1_stage.fsdb");
        $fsdbDumpvars(0, tb_mem1_stage, "+all");
    end
`else
    initial begin
        $dumpfile("tb_mem1_stage.vcd");
        $dumpvars(0, tb_mem1_stage);
    end
`endif

    initial clk = 0;
    always #5 clk = ~clk;

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

    task expect_mask;
        input [(XLEN/8)-1:0] actual;
        input [(XLEN/8)-1:0] expected;
        input [255:0] name;
        begin
            if (actual !== expected) begin
                $display("[FAIL] %0s actual=0x%0h expected=0x%0h", name, actual, expected);
                errors = errors + 1;
            end else begin
                $display("[PASS] %0s = 0x%0h", name, actual);
            end
        end
    endtask

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

    initial begin
        errors = 0;
        rst_n = 0;
        ex_reg_w_en = 0;
        ex_mem_w_en = 0;
        ex_rd_data = 0;
        ex_mem_addr = 0;
        ex_reg_addr = 0;
        ex_op_sel = 0;
        ex_func_sel = 0;
        ex_mem_r_en = 0;
        inst_valid_i = 0;

        repeat (2) @(posedge clk);
        rst_n = 1;

        ex_reg_w_en = 1;
        ex_mem_r_en = 1;
        ex_reg_addr = 5'd7;
        ex_rd_data = 32'h1234_5678;
        ex_mem_addr = 32'h0000_1002;
        ex_op_sel = `EXE_RES_LOAD_STORE;
        ex_func_sel = `EXE_LW_OP;
        inst_valid_i = 1;
        @(posedge clk); #1;
        expect_word(mem1_rd_data, 32'h1234_5678, "load path data pipeline");
        expect_word({29'h0, mem1_byte_offset}, 32'd2, "byte offset capture");
        expect_bit(mem_r_en, 1, "load-use helper mem_r_en");
        expect_bit(mem1_r_en, 1, "load request to memory");
        expect_word(mem1_addr, 32'h0000_1002, "load address pass-through");

        ex_mem_r_en = 0;
        ex_mem_w_en = 1;
        ex_func_sel = `EXE_SB_OP;
        ex_rd_data = 32'hAABB_CCDD;
        ex_mem_addr = 32'h0000_1001;
        @(posedge clk); #1;
        expect_word(mem1_w_data, 32'hDDDD_DDDD, "SB replicates byte");
        expect_mask(mem1_w_mask, 4'b0010, "SB byte mask shift");
        expect_bit(mem1_w_en, 1, "store write enable");

        ex_func_sel = `EXE_SH_OP;
        ex_rd_data = 32'h1234_5678;
        ex_mem_addr = 32'h0000_1002;
        @(posedge clk); #1;
        expect_word(mem1_w_data, 32'h5678_5678, "SH replicates halfword");
        expect_mask(mem1_w_mask, 4'b1100, "SH mask shift");

        ex_func_sel = `EXE_SW_OP;
        ex_mem_addr = 32'h0000_1000;
        @(posedge clk); #1;
        expect_word(mem1_w_data, 32'h1234_5678, "SW passes word");
        expect_mask(mem1_w_mask, 4'b1111, "SW full word mask");

        if (errors == 0) begin
            $display("[RESULT] tb_mem1_stage PASS");
        end else begin
            $display("[RESULT] tb_mem1_stage FAIL errors=%0d", errors);
            $fatal(1);
        end
        $finish;
    end
endmodule

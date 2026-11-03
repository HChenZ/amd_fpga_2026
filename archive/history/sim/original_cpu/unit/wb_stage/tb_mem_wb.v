`timescale 1ns / 1ps

module tb_mem_wb;
    localparam XLEN = 32;

    reg                 clk;
    reg                 rst_n;
    reg                 ex_reg_w_en_i;
    reg  [XLEN-1:0]     ex_rd_data_i;
    reg  [4:0]          ex_reg_addr_i;
    reg                 inst_valid_i;
    wire                inst_valid_o;
    wire                mem_reg_w_en_o;
    wire [XLEN-1:0]     mem_rd_data_o;
    wire [4:0]          mem_reg_addr_o;

    integer errors;

    mem_wb #(.XLEN(XLEN)) dut (
        .clk(clk),
        .rst_n(rst_n),
        .ex_reg_w_en_i(ex_reg_w_en_i),
        .ex_rd_data_i(ex_rd_data_i),
        .ex_reg_addr_i(ex_reg_addr_i),
        .inst_valid_i(inst_valid_i),
        .inst_valid_o(inst_valid_o),
        .mem_reg_w_en_o(mem_reg_w_en_o),
        .mem_rd_data_o(mem_rd_data_o),
        .mem_reg_addr_o(mem_reg_addr_o)
    );

`ifdef DUMP_FSDB
    initial begin
        $fsdbDumpfile("tb_mem_wb.fsdb");
        $fsdbDumpvars(0, tb_mem_wb, "+all");
    end
`else
    initial begin
        $dumpfile("tb_mem_wb.vcd");
        $dumpvars(0, tb_mem_wb);
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
        ex_reg_w_en_i = 0;
        ex_rd_data_i = 0;
        ex_reg_addr_i = 0;
        inst_valid_i = 0;

        repeat (2) @(posedge clk);
        #1;
        expect_bit(mem_reg_w_en_o, 0, "reset write disable");
        rst_n = 1;

        ex_reg_w_en_i = 1;
        ex_rd_data_i = 32'h1234_5678;
        ex_reg_addr_i = 5'd9;
        inst_valid_i = 1;
        @(posedge clk); #1;
        expect_bit(mem_reg_w_en_o, 1, "wb write enable capture");
        expect_word(mem_rd_data_o, 32'h1234_5678, "wb data capture");
        expect_word({27'h0, mem_reg_addr_o}, 32'd9, "wb addr capture");
        expect_bit(inst_valid_o, 1, "wb valid capture");

        ex_reg_w_en_i = 0;
        ex_rd_data_i = 32'hDEAD_BEEF;
        ex_reg_addr_i = 5'd0;
        inst_valid_i = 0;
        @(posedge clk); #1;
        expect_bit(mem_reg_w_en_o, 0, "second cycle write disable");
        expect_word(mem_rd_data_o, 32'hDEAD_BEEF, "second cycle data pipeline");
        expect_bit(inst_valid_o, 0, "second cycle valid pipeline");

        if (errors == 0) begin
            $display("[RESULT] tb_mem_wb PASS");
        end else begin
            $display("[RESULT] tb_mem_wb FAIL errors=%0d", errors);
            $fatal(1);
        end
        $finish;
    end
endmodule

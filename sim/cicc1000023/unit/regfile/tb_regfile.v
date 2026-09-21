`timescale 1ns / 1ps

module tb_regfile;
    localparam XLEN = 32;

    reg              clk;
    reg              rst_n;
    reg  [4:0]       w_reg_addr;
    reg  [4:0]       r_reg_addr1;
    reg  [4:0]       r_reg_addr2;
    reg  [XLEN-1:0]  w_reg_data;
    reg              w_reg_en;
    wire [XLEN-1:0]  reg_rs1;
    wire [XLEN-1:0]  reg_rs2;

    integer errors;
    integer i;

    regfile #(.XLEN(XLEN)) dut (
        .clk(clk),
        .rst_n(rst_n),
        .w_reg_addr(w_reg_addr),
        .r_reg_addr1(r_reg_addr1),
        .r_reg_addr2(r_reg_addr2),
        .w_reg_data(w_reg_data),
        .w_reg_en(w_reg_en),
        .reg_rs1(reg_rs1),
        .reg_rs2(reg_rs2)
    );

`ifdef DUMP_FSDB
    initial begin
        $fsdbDumpfile("tb_regfile.fsdb");
        $fsdbDumpvars(0, tb_regfile, "+all");
    end
`else
    initial begin
        $dumpfile("tb_regfile.vcd");
        $dumpvars(0, tb_regfile);
    end
`endif

    initial clk = 1'b0;
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

    initial begin
        errors = 0;
        rst_n = 1'b0;
        w_reg_addr = 5'd0;
        r_reg_addr1 = 5'd0;
        r_reg_addr2 = 5'd0;
        w_reg_data = 32'h0;
        w_reg_en = 1'b0;
        for (i = 0; i < 32; i = i + 1)
            dut.registers[i] = 32'h0;

        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        @(negedge clk);

        r_reg_addr1 = 5'd0;
        r_reg_addr2 = 5'd0;
        #1;
        expect_word(reg_rs1, 32'h0, "x0 read port 1");
        expect_word(reg_rs2, 32'h0, "x0 read port 2");
        r_reg_addr1 = 5'd5;
        #1;
        expect_word(reg_rs1, 32'h0, "unwritten register defaults to zero in test init");

        w_reg_en = 1'b1;
        w_reg_addr = 5'd1;
        w_reg_data = 32'h1234_5678;
        r_reg_addr1 = 5'd1;
        #1;
        expect_word(reg_rs1, 32'h1234_5678, "same-cycle write bypass rs1");
        @(negedge clk);
        w_reg_en = 1'b0;
        #1;
        expect_word(dut.registers[1], 32'h1234_5678, "x1 stored after clock");
        expect_word(reg_rs1, 32'h1234_5678, "x1 read back");

        w_reg_en = 1'b1;
        w_reg_addr = 5'd0;
        w_reg_data = 32'hFFFF_FFFF;
        r_reg_addr1 = 5'd0;
        #1;
        expect_word(reg_rs1, 32'h0, "x0 write ignored on read");
        @(negedge clk);
        w_reg_en = 1'b0;

        w_reg_en = 1'b1;
        w_reg_addr = 5'd31;
        w_reg_data = 32'hCAFE_BABE;
        r_reg_addr1 = 5'd31;
        r_reg_addr2 = 5'd1;
        #1;
        expect_word(reg_rs1, 32'hCAFE_BABE, "upper boundary register bypass");
        expect_word(reg_rs2, 32'h1234_5678, "independent second read");
        @(negedge clk);
        w_reg_en = 1'b0;
        #1;
        expect_word(dut.registers[31], 32'hCAFE_BABE, "x31 stored after clock");

        w_reg_en = 1'b0;
        w_reg_addr = 5'd1;
        w_reg_data = 32'h8765_4321;
        r_reg_addr1 = 5'd1;
        #1;
        expect_word(reg_rs1, 32'h1234_5678, "write disabled keeps old value");

        w_reg_en = 1'b1;
        w_reg_addr = 5'd2;
        w_reg_data = 32'hA5A5_5A5A;
        r_reg_addr1 = 5'd2;
        r_reg_addr2 = 5'd2;
        #1;
        expect_word(reg_rs1, 32'hA5A5_5A5A, "dual-port bypass rs1");
        expect_word(reg_rs2, 32'hA5A5_5A5A, "dual-port bypass rs2");
        @(negedge clk);
        w_reg_en = 1'b0;

        r_reg_addr1 = 5'd31;
        r_reg_addr2 = 5'd2;
        #1;
        expect_word(reg_rs1, 32'hCAFE_BABE, "dual-port independent stored rs1");
        expect_word(reg_rs2, 32'hA5A5_5A5A, "dual-port independent stored rs2");

        if (errors == 0) begin
            $display("[RESULT] tb_regfile PASS");
        end else begin
            $display("[RESULT] tb_regfile FAIL errors=%0d", errors);
            $fatal(1);
        end
        $finish;
    end
endmodule

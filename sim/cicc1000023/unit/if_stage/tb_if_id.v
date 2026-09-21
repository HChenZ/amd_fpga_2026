`timescale 1ns / 1ps

module tb_if_id;
    localparam XLEN = 32;

    reg                 clk;
    reg                 rst_n;
    reg  [31:0]         imem_inst_i;
    reg                 pred_taken_i;
    reg  [XLEN-1:0]     pred_target_i;
    reg                 flush;
    reg                 stall;
    reg  [XLEN-1:0]     pc;
    wire [4:0]          rs1_addr;
    wire [4:0]          rs2_addr;
    wire                rs1_en;
    wire                rs2_en;
    wire [31:0]         if_inst_o;
    wire                pred_taken_o;
    wire [XLEN-1:0]     pred_target_o;
    wire [XLEN-1:0]     if_pc_o;
    wire [6:0]          opcode;
    wire                inst_valid;

    integer errors;

    if_id #(.XLEN(XLEN)) dut (
        .clk(clk),
        .rst_n(rst_n),
        .imem_inst_i(imem_inst_i),
        .pred_taken_i(pred_taken_i),
        .pred_target_i(pred_target_i),
        .flush(flush),
        .stall(stall),
        .pc(pc),
        .rs1_addr(rs1_addr),
        .rs2_addr(rs2_addr),
        .rs1_en(rs1_en),
        .rs2_en(rs2_en),
        .if_inst_o(if_inst_o),
        .pred_taken_o(pred_taken_o),
        .pred_target_o(pred_target_o),
        .if_pc_o(if_pc_o),
        .opcode(opcode),
        .inst_valid(inst_valid)
    );

`ifdef DUMP_FSDB
    initial begin
        $fsdbDumpfile("tb_if_id.fsdb");
        $fsdbDumpvars(0, tb_if_id, "+all");
    end
`else
    initial begin
        $dumpfile("tb_if_id.vcd");
        $dumpvars(0, tb_if_id);
    end
`endif

    initial clk = 0;
    always #5 clk = ~clk;

    task expect_word;
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
        flush = 0;
        stall = 0;
        pc = 32'h0000_1000;
        pred_taken_i = 1;
        pred_target_i = 32'h0000_2000;
        imem_inst_i = 32'h002082b3; // add x5,x1,x2

        repeat (2) @(posedge clk);
        rst_n <= 1;
        @(posedge clk); #1;
        expect_word(if_inst_o, 32'h002082b3, "normal instruction forward");
        expect_word(if_pc_o, 32'h0000_1000, "pc capture");
        expect_bit(pred_taken_o, 1, "prediction bit capture");
        expect_word(pred_target_o, 32'h0000_2000, "prediction target capture");
        expect_word({27'h0, rs1_addr}, 32'd1, "rs1 decode");
        expect_word({27'h0, rs2_addr}, 32'd2, "rs2 decode");
        expect_bit(inst_valid, 1, "valid on normal transfer");

        @(posedge clk);
        flush <= 1;
        @(posedge clk); #1;
        flush <= 0;
        expect_word(if_inst_o, 32'h0000_0013, "flush injects nop");
        expect_word({27'h0, rs1_addr}, 32'd0, "flush clears rs1");
        expect_bit(inst_valid, 0, "flush clears valid");

        @(posedge clk);
        imem_inst_i <= 32'h0080a303; // lw x6,8(x1)
        pc <= 32'h0000_1004;
        @(posedge clk); #1;
        expect_word(if_inst_o, 32'h0080a303, "post-flush normal instruction");

        @(posedge clk);
        stall <= 1;
        imem_inst_i <= 32'h0020a223; // sw x2,4(x1)
        @(posedge clk); #1;
        expect_word(dut.stall_inst_reg, 32'h0020a223, "stall captures current imem beat");
        expect_word(if_inst_o, 32'h0020a223, "stall outputs captured instruction");
        expect_bit(inst_valid, 0, "stall deasserts valid");

        @(posedge clk);
        stall <= 0;

        if (errors == 0) begin
            $display("[RESULT] tb_if_id PASS");
        end else begin
            $display("[RESULT] tb_if_id FAIL errors=%0d", errors);
            $fatal(1);
        end
        $finish;
    end
endmodule

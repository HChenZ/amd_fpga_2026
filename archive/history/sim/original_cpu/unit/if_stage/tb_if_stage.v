`timescale 1ns / 1ps

module tb_if_stage;
    localparam XLEN = 32;

    reg                  clk;
    reg                  rst_n;
    reg                  stall;
    reg  [1:0]           jump_sel;
    reg                  pred_taken;
    reg  [XLEN-1:0]      pred_target;
    reg  [XLEN-1:0]      ex_pc_shift;
    reg  [XLEN-1:0]      mtvec_pc;
    reg  [XLEN-1:0]      mepc_pc;
    wire [XLEN-1:0]      pc;

    integer errors;

    if_stage #(.XLEN(XLEN)) dut (
        .clk(clk),
        .rst_n(rst_n),
        .stall(stall),
        .jump_sel(jump_sel),
        .pred_taken(pred_taken),
        .pred_target(pred_target),
        .ex_pc_shift(ex_pc_shift),
        .mtvec_pc(mtvec_pc),
        .mepc_pc(mepc_pc),
        .pc(pc)
    );

`ifdef DUMP_FSDB
    initial begin
        $fsdbDumpfile("tb_if_stage.fsdb");
        $fsdbDumpvars(0, tb_if_stage, "+all");
    end
`else
    initial begin
        $dumpfile("tb_if_stage.vcd");
        $dumpvars(0, tb_if_stage);
    end
`endif

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task expect_pc;
        input [XLEN-1:0] expected;
        input [255:0] name;
        begin
            if (pc !== expected) begin
                $display("[FAIL] %0s actual=0x%08h expected=0x%08h", name, pc, expected);
                errors = errors + 1;
            end else begin
                $display("[PASS] %0s = 0x%08h", name, pc);
            end
        end
    endtask

    initial begin
        errors = 0;
        rst_n = 0;
        stall = 0;
        jump_sel = 2'b00;
        pred_taken = 0;
        pred_target = 32'h0000_0040;
        ex_pc_shift = 32'h0000_0080;
        mtvec_pc = 32'h0000_0100;
        mepc_pc = 32'h0000_0200;

        repeat (2) @(posedge clk);
        #1 expect_pc(32'h1000_0000, "reset pc boot address");
        rst_n = 1;

        @(posedge clk); #1;
        expect_pc(32'h1000_0004, "sequential pc+4");

        pred_taken = 1;
        @(posedge clk); #1;
        expect_pc(32'h0000_0040, "predict taken target");

        pred_taken = 0;
        stall = 1;
        @(posedge clk); #1;
        expect_pc(32'h0000_0040, "stall holds pc");

        stall = 0;
        jump_sel = 2'b01;
        @(posedge clk); #1;
        expect_pc(32'h0000_0080, "branch redirect has priority");

        jump_sel = 2'b10;
        pred_taken = 1;
        @(posedge clk); #1;
        expect_pc(32'h0000_0100, "trap redirect overrides prediction");

        jump_sel = 2'b11;
        @(posedge clk); #1;
        expect_pc(32'h0000_0200, "mret redirect");

        if (errors == 0) begin
            $display("[RESULT] tb_if_stage PASS");
        end else begin
            $display("[RESULT] tb_if_stage FAIL errors=%0d", errors);
            $fatal(1);
        end
        $finish;
    end
endmodule

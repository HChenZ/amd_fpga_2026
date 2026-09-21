`timescale 1ns / 1ps

module tb_if_frontend_integrated;
    localparam XLEN = 32;

    reg                 clk;
    reg                 rst_n;
    reg                 stall;
    reg  [1:0]          jump_sel;
    reg                 pred_taken;
    reg  [XLEN-1:0]     pred_target;
    reg  [XLEN-1:0]     ex_pc_shift;
    reg  [XLEN-1:0]     mtvec_pc;
    reg  [XLEN-1:0]     mepc_pc;

    reg                 flush;

    wire [XLEN-1:0]     pc;
    wire [31:0]         imem_inst_i;
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

    integer             errors;
    integer             cycle_count;

    if_stage #(.XLEN(XLEN)) u_if_stage (
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

    sync_imem #(.XLEN(XLEN)) u_sync_imem (
        .clk(clk),
        .addr(pc),
        .re(1'b1),
        .inst(imem_inst_i)
    );

    if_id #(.XLEN(XLEN)) u_if_id (
        .clk(clk),
        .rst_n(rst_n),
        .imem_inst_i(imem_inst_i),
        .pred_taken_i(pred_taken),
        .pred_target_i(pred_target),
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
        $fsdbDumpfile("tb_if_frontend_integrated.fsdb");
        $fsdbDumpvars(0, tb_if_frontend_integrated, "+all");
    end
`else
    initial begin
        $dumpfile("tb_if_frontend_integrated.vcd");
        $dumpvars(0, tb_if_frontend_integrated);
    end
`endif

    initial clk = 1'b0;
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

    always @(posedge clk) begin
        cycle_count <= cycle_count + 1;
        #1;
        $display("[TRACE] cycle=%0d time=%0t pc=0x%08h imem=0x%08h if_inst_o=0x%08h if_pc_o=0x%08h stall=%0b flush=%0b valid=%0b stall_reg=%0b stall_inst=0x%08h",
                 cycle_count, $time, pc, imem_inst_i, if_inst_o, if_pc_o, stall, flush, inst_valid,
                 u_if_id.stall_reg, u_if_id.stall_inst_reg);
    end

    initial begin
        errors = 0;
        cycle_count = 0;
        rst_n = 0;
        stall = 0;
        flush = 0;
        jump_sel = 2'b00;
        pred_taken = 0;
        pred_target = 32'h0;
        ex_pc_shift = 32'h0;
        mtvec_pc = 32'h100;
        mepc_pc = 32'h200;

        repeat (2) @(posedge clk);
        rst_n <= 1;

        // Let the synchronous fetch path settle through add/lw alignment.
        repeat (3) @(posedge clk);

        // Assert stall one beat before the desired hold point so that the synchronous
        // BRAM frontend freezes on the fetch beat carrying the SW instruction.
        stall <= 1;
        @(posedge clk); #1;
        expect_word(if_inst_o, 32'h0020A223, "system-aware stall holds current fetched instruction");
        expect_word(u_if_id.stall_inst_reg, 32'h0020A223, "stall register captures fetched instruction");
        expect_word(if_pc_o, 32'h10000008, "if_pc_o remains aligned with fetched instruction");
        expect_bit(inst_valid, 0, "stall deasserts inst_valid");

        stall <= 0;
        @(posedge clk); #1;

        if (errors == 0) begin
            $display("[RESULT] tb_if_frontend_integrated PASS");
        end else begin
            $display("[RESULT] tb_if_frontend_integrated FAIL errors=%0d", errors);
            $fatal(1);
        end
        $finish;
    end
endmodule

module sync_imem #(
    parameter XLEN = 32
)(
    input                  clk,
    input      [XLEN-1:0]  addr,
    input                  re,
    output reg [31:0]      inst
);
    always @(posedge clk) begin
        if (re) begin
            case (addr)
                32'h1000_0000: inst <= 32'h0020_82B3; // add x5,x1,x2
                32'h1000_0004: inst <= 32'h0080_A303; // lw x6,8(x1)
                32'h1000_0008: inst <= 32'h0020_A223; // sw x2,4(x1)
                32'h1000_000C: inst <= 32'h0000_0013; // nop
                default:       inst <= 32'h0000_0013;
            endcase
        end
    end
endmodule

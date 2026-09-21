`timescale 1ns / 1ps
`include "defines.v"

module tb_id_stage;
    localparam XLEN = 32;

    reg  [XLEN-1:0] if_pc;
    reg  [31:0]     if_inst;
    reg  [6:0]      opcode;
    reg  [XLEN-1:0] reg_rs1;
    reg  [XLEN-1:0] reg_rs2;
    wire [4:0]      reg_addr1;
    wire [4:0]      reg_addr2;
    wire [XLEN-1:0] id_rs1;
    wire [XLEN-1:0] id_rs2;
    wire [XLEN-1:0] id_pc;
    wire [4:0]      id_w_reg_waddr;
    wire [2:0]      id_op_sel;
    wire [5:0]      id_func_sel;
    wire            id_reg_w_en;
    wire            id_mem_w_en;
    wire            id_mem_r_en;
    wire [XLEN-1:0] id_imm;
    wire            is_branch;
    wire [31:0]     id_inst;
    wire            is_word_op;
    wire [4:0]      rs1_addr;
    wire [4:0]      rs2_addr;
    wire            csr_w_en;
    wire [11:0]     csr_addr;
    wire            illegal_inst_en;

    integer errors;

    id_stage #(.XLEN(XLEN)) dut (
        .if_pc(if_pc),
        .if_inst(if_inst),
        .opcode(opcode),
        .reg_rs1(reg_rs1),
        .reg_rs2(reg_rs2),
        .reg_addr1(reg_addr1),
        .reg_addr2(reg_addr2),
        .id_rs1(id_rs1),
        .id_rs2(id_rs2),
        .id_pc(id_pc),
        .id_w_reg_waddr(id_w_reg_waddr),
        .id_op_sel(id_op_sel),
        .id_func_sel(id_func_sel),
        .id_reg_w_en(id_reg_w_en),
        .id_mem_w_en(id_mem_w_en),
        .id_mem_r_en(id_mem_r_en),
        .id_imm(id_imm),
        .is_branch(is_branch),
        .id_inst(id_inst),
        .is_word_op(is_word_op),
        .rs1_addr(rs1_addr),
        .rs2_addr(rs2_addr),
        .csr_w_en(csr_w_en),
        .csr_addr(csr_addr),
        .illegal_inst_en(illegal_inst_en)
    );

`ifdef DUMP_FSDB
    initial begin
        $fsdbDumpfile("tb_id_stage.fsdb");
        $fsdbDumpvars(0, tb_id_stage, "+all");
    end
`else
    initial begin
        $dumpfile("tb_id_stage.vcd");
        $dumpvars(0, tb_id_stage);
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

    task expect_small;
        input [31:0] actual;
        input [31:0] expected;
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
        if_pc = 32'h0000_1000;
        reg_rs1 = 32'h1111_1111;
        reg_rs2 = 32'h2222_2222;

        if_inst = 32'h002082b3; // add x5,x1,x2
        opcode  = if_inst[6:0];
        #1;
        expect_small(reg_addr1, 1, "ADD rs1 addr");
        expect_small(reg_addr2, 2, "ADD rs2 addr");
        expect_small(id_w_reg_waddr, 5, "ADD rd");
        expect_small(id_op_sel, `EXE_RES_ARITH, "ADD op sel");
        expect_small(id_func_sel, `EXE_ADD_OP, "ADD func sel");
        expect_bit(id_reg_w_en, 1, "ADD reg write");
        expect_word(id_rs1, 32'h1111_1111, "ADD rs1 data pass-through");
        expect_word(id_rs2, 32'h2222_2222, "ADD rs2 data pass-through");

        if_inst = 32'hfff08293; // addi x5,x1,-1
        opcode  = if_inst[6:0];
        #1;
        expect_small(id_func_sel, `EXE_ADD_OP, "ADDI func sel");
        expect_word(id_imm, 32'hFFFF_FFFF, "ADDI sign-extended immediate");
        expect_word(id_rs2, 32'hFFFF_FFFF, "ADDI immediate routed to rs2");

        if_inst = 32'h0080a303; // lw x6,8(x1)
        opcode  = if_inst[6:0];
        #1;
        expect_small(id_op_sel, `EXE_RES_LOAD_STORE, "LW op sel");
        expect_small(id_func_sel, `EXE_LW_OP, "LW func sel");
        expect_bit(id_mem_r_en, 1, "LW mem read enable");
        expect_word(id_imm, 32'd8, "LW immediate");

        if_inst = 32'h0020a223; // sw x2,4(x1)
        opcode  = if_inst[6:0];
        #1;
        expect_bit(id_mem_w_en, 1, "SW mem write enable");
        expect_small(id_func_sel, `EXE_SW_OP, "SW func sel");
        expect_word(id_imm, 32'd4, "SW immediate");

        if_inst = 32'h00208863; // beq x1,x2,16
        opcode  = if_inst[6:0];
        #1;
        expect_bit(is_branch, 1, "BEQ branch flag");
        expect_small(id_func_sel, `EXE_BEQ_OP, "BEQ func sel");
        expect_word(id_imm, 32'd16, "BEQ immediate");

        if_inst = 32'h010000ef; // jal x1,16
        opcode  = if_inst[6:0];
        #1;
        expect_small(id_func_sel, `EXE_JAL_OP, "JAL func sel");
        expect_bit(is_branch, 1, "JAL branch flag");
        expect_small(id_w_reg_waddr, 1, "JAL rd");

        if_inst = 32'h305120f3; // csrrs x1,0x305,x2
        opcode  = if_inst[6:0];
        #1;
        expect_bit(csr_w_en, 1, "CSRRS writes csr when rs1!=0");
        expect_small(csr_addr, 12'h305, "CSRRS address");
        expect_small(id_func_sel, `EXE_CSRRS_OP, "CSRRS func sel");

        if_inst = 32'h00000000;
        opcode  = if_inst[6:0];
        #1;
        expect_bit(illegal_inst_en, 1, "all-zero instruction flagged illegal");

        if (errors == 0) begin
            $display("[RESULT] tb_id_stage PASS");
        end else begin
            $display("[RESULT] tb_id_stage FAIL errors=%0d", errors);
            $fatal(1);
        end
        $finish;
    end
endmodule

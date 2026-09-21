`timescale 1ns / 1ps
`include "defines.v"

module tb_ex_stage_alu;
    localparam XLEN = 32;

    reg                     clk;
    reg                     rst_n;
    reg   [XLEN-1:0]        id_pc;
    reg   [XLEN-1:0]        id_rs1;
    reg   [XLEN-1:0]        id_rs2;
    reg   [2:0]             id_op_sel;
    reg   [5:0]             id_func_sel;
    reg                     id_reg_w_en;
    reg                     id_mem_w_en;
    reg   [XLEN-1:0]        id_imm;
    reg   [4:0]             id_w_reg_waddr;
    reg                     id_mem_r_en;
    reg                     csr_w_en;
    reg   [11:0]            id_csr_addr;
    reg   [XLEN-1:0]        csr_rdata;
    reg                     is_word_op;
    reg                     is_branch;
    reg                     pred_taken;
    reg   [XLEN-1:0]        pred_target;
    reg                     inter_req;
    reg                     id_illegal_inst_en;
    reg   [31:0]            id_inst;

    wire                    ex_reg_w_en;
    wire                    ex_mem_w_en;
    wire  [XLEN-1:0]        ex_rd_data;
    wire  [4:0]             ex_reg_addr;
    wire  [2:0]             ex_op_sel;
    wire  [XLEN-1:0]        ex_mem_addr;
    wire  [5:0]             ex_func_sel;
    wire                    ex_mem_r_en;
    wire  [XLEN-1:0]        ex_pc_shift;
    wire                    jump_en;
    wire                    ex_stall_req;
    wire                    pred_real_taken;
    wire  [XLEN-1:0]        pred_real_addr;
    wire                    is_branch_o;
    wire  [XLEN-1:0]        ex_pc;
    wire                    jump_trap_en;
    wire                    jump_trap_out;
    wire  [XLEN-1:0]        csr_wdata;
    wire                    csr_we;
    wire                    csr_re;
    wire                    trap_en;
    wire  [XLEN-1:0]        trap_pc;
    wire  [3:0]             trap_cause;
    wire                    trap_out;
    wire  [XLEN-1:0]        trap_val;

    integer errors;

    ex_stage #(.XLEN(XLEN)) dut (
        .clk(clk),
        .rst_n(rst_n),
        .id_pc(id_pc),
        .id_rs1(id_rs1),
        .id_rs2(id_rs2),
        .id_op_sel(id_op_sel),
        .id_func_sel(id_func_sel),
        .id_reg_w_en(id_reg_w_en),
        .id_mem_w_en(id_mem_w_en),
        .id_imm(id_imm),
        .id_w_reg_waddr(id_w_reg_waddr),
        .id_mem_r_en(id_mem_r_en),
        .csr_w_en(csr_w_en),
        .id_csr_addr(id_csr_addr),
        .csr_rdata(csr_rdata),
        .is_word_op(is_word_op),
        .is_branch(is_branch),
        .pred_taken(pred_taken),
        .pred_target(pred_target),
        .inter_req(inter_req),
        .id_illegal_inst_en(id_illegal_inst_en),
        .id_inst(id_inst),
        .ex_reg_w_en(ex_reg_w_en),
        .ex_mem_w_en(ex_mem_w_en),
        .ex_rd_data(ex_rd_data),
        .ex_reg_addr(ex_reg_addr),
        .ex_op_sel(ex_op_sel),
        .ex_mem_addr(ex_mem_addr),
        .ex_func_sel(ex_func_sel),
        .ex_mem_r_en(ex_mem_r_en),
        .ex_pc_shift(ex_pc_shift),
        .jump_en(jump_en),
        .ex_stall_req(ex_stall_req),
        .pred_real_taken(pred_real_taken),
        .pred_real_addr(pred_real_addr),
        .is_branch_o(is_branch_o),
        .ex_pc(ex_pc),
        .jump_trap_en(jump_trap_en),
        .jump_trap_out(jump_trap_out),
        .csr_wdata(csr_wdata),
        .csr_we(csr_we),
        .csr_re(csr_re),
        .trap_en(trap_en),
        .trap_pc(trap_pc),
        .trap_cause(trap_cause),
        .trap_out(trap_out),
        .trap_val(trap_val)
    );

`ifdef DUMP_FSDB
    initial begin
        $fsdbDumpfile("tb_ex_stage_alu.fsdb");
        $fsdbDumpvars(0, tb_ex_stage_alu, "+all");
    end
`else
    initial begin
        $dumpfile("tb_ex_stage_alu.vcd");
        $dumpvars(0, tb_ex_stage_alu);
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

    task clear_inputs;
        begin
            id_pc = 32'h1000;
            id_rs1 = 32'h0;
            id_rs2 = 32'h0;
            id_op_sel = `EXE_RES_NOP;
            id_func_sel = `EXE_NOP_OP;
            id_reg_w_en = 1'b0;
            id_mem_w_en = 1'b0;
            id_imm = 32'h0;
            id_w_reg_waddr = 5'd0;
            id_mem_r_en = 1'b0;
            csr_w_en = 1'b0;
            id_csr_addr = 12'h0;
            csr_rdata = 32'h0;
            is_word_op = 1'b0;
            is_branch = 1'b0;
            pred_taken = 1'b0;
            pred_target = 32'h0;
            inter_req = 1'b0;
            id_illegal_inst_en = 1'b0;
            id_inst = 32'h0;
            #1;
        end
    endtask

    initial begin
        errors = 0;
        rst_n = 1'b0;
        clear_inputs();
        repeat (2) @(posedge clk);
        rst_n = 1'b1;

        clear_inputs();
        id_op_sel = `EXE_RES_ARITH;
        id_func_sel = `EXE_ADD_OP;
        id_rs1 = 32'd20;
        id_rs2 = 32'd22;
        #1;
        expect_word(ex_rd_data, 32'd42, "ADD result");

        clear_inputs();
        id_op_sel = `EXE_RES_ARITH;
        id_func_sel = `EXE_SUB_OP;
        id_rs1 = 32'd20;
        id_rs2 = 32'd22;
        #1;
        expect_word(ex_rd_data, 32'hFFFF_FFFE, "SUB negative result");

        clear_inputs();
        id_op_sel = `EXE_RES_LOGIC;
        id_func_sel = `EXE_AND_OP;
        id_rs1 = 32'hF0F0_F0F0;
        id_rs2 = 32'h0FF0_0FF0;
        #1;
        expect_word(ex_rd_data, 32'h00F0_00F0, "AND result");

        clear_inputs();
        id_op_sel = `EXE_RES_SHIFT;
        id_func_sel = `EXE_SRA_OP;
        id_rs1 = 32'h8000_0010;
        id_rs2 = 32'd2;
        #1;
        expect_word(ex_rd_data, 32'hE000_0004, "SRA sign-preserving shift");

        clear_inputs();
        id_op_sel = `EXE_RES_ARITH;
        id_func_sel = `EXE_SLTU_OP;
        id_rs1 = 32'h0000_0001;
        id_rs2 = 32'hFFFF_FFFF;
        #1;
        expect_word(ex_rd_data, 32'h0000_0001, "SLTU unsigned compare result");

        clear_inputs();
        id_op_sel = `EXE_RES_JUMP_BRANCH;
        id_func_sel = `EXE_BEQ_OP;
        is_branch = 1'b1;
        id_rs1 = 32'h55AA_1234;
        id_rs2 = 32'h55AA_1234;
        id_imm = 32'h20;
        pred_taken = 1'b0;
        pred_target = 32'h0000_0000;
        #1;
        expect_bit(pred_real_taken, 1'b1, "BEQ actual taken");
        expect_bit(jump_en, 1'b1, "BEQ wrong-direction triggers flush");
        expect_word(ex_pc_shift, 32'h1020, "BEQ real branch target");

        clear_inputs();
        id_op_sel = `EXE_RES_JUMP_BRANCH;
        id_func_sel = `EXE_BLTU_OP;
        is_branch = 1'b1;
        id_rs1 = 32'h0000_0001;
        id_rs2 = 32'hFFFF_FFFF;
        id_imm = 32'h10;
        pred_taken = 1'b1;
        pred_target = 32'h1010;
        #1;
        expect_bit(pred_real_taken, 1'b1, "BLTU unsigned compare taken");
        expect_bit(jump_en, 1'b0, "correct BLTU prediction keeps pipeline");

        clear_inputs();
        id_op_sel = `EXE_RES_JUMP_BRANCH;
        id_func_sel = `EXE_JAL_OP;
        is_branch = 1'b1;
        id_pc = 32'h4000;
        id_imm = 32'h40;
        pred_taken = 1'b1;
        pred_target = 32'h4010;
        #1;
        expect_bit(pred_real_taken, 1'b1, "JAL always taken");
        expect_bit(jump_en, 1'b1, "JAL wrong target triggers flush");
        expect_word(ex_pc_shift, 32'h4040, "JAL target uses pc plus imm");

        clear_inputs();
        id_op_sel = `EXE_RES_JUMP_BRANCH;
        id_func_sel = `EXE_JALR_OP;
        is_branch = 1'b1;
        id_pc = 32'h2000;
        id_rs1 = 32'h3003;
        id_imm = 32'h10;
        pred_taken = 1'b1;
        pred_target = 32'h3012;
        #1;
        expect_word(ex_rd_data, 32'h2004, "JALR link address");
        expect_word(pred_real_addr, 32'h3012, "JALR target clears bit0");
        expect_bit(jump_en, 1'b0, "correct JALR prediction avoids flush");

        clear_inputs();
        id_op_sel = `EXE_RES_LOAD_STORE;
        id_func_sel = `EXE_LH_OP;
        id_rs1 = 32'h1000;
        id_imm = 32'h1;
        #1;
        expect_bit(trap_en, 1'b1, "misaligned LH raises trap");
        expect_word({28'h0, trap_cause}, 32'h0000_0004, "load half misalign cause");

        clear_inputs();
        id_op_sel = `EXE_RES_LOAD_STORE;
        id_func_sel = `EXE_LW_OP;
        id_rs1 = 32'h1000;
        id_imm = 32'h2;
        #1;
        expect_bit(trap_en, 1'b1, "misaligned LW raises trap");
        expect_word(trap_val, 32'h1002, "misaligned address captured");

        clear_inputs();
        id_op_sel = `EXE_RES_LOAD_STORE;
        id_func_sel = `EXE_SW_OP;
        id_rs1 = 32'h1000;
        id_imm = 32'h1;
        #1;
        expect_bit(trap_en, 1'b1, "misaligned SW raises trap");
        expect_word({28'h0, trap_cause}, 32'h0000_0006, "store misalign cause");

        clear_inputs();
        id_func_sel = `EXE_CSRRS_OP;
        csr_rdata = 32'h0000_00F0;
        id_rs1 = 32'h0000_000F;
        id_w_reg_waddr = 5'd1;
        id_csr_addr = 12'h305;
        #1;
        expect_bit(csr_re, 1'b1, "CSRRS enables csr read");
        expect_word(csr_wdata, 32'h0000_00FF, "CSRRS merges set bits");

        clear_inputs();
        id_illegal_inst_en = 1'b1;
        id_inst = 32'hFFFF_FFFF;
        #1;
        expect_bit(trap_en, 1'b1, "illegal instruction trap");
        expect_word(trap_val, 32'hFFFF_FFFF, "illegal instruction value captured");

        clear_inputs();
        id_func_sel = `EXE_MRET_OP;
        #1;
        expect_bit(trap_out, 1'b1, "mret raises trap out");

        clear_inputs();
        id_func_sel = `EXE_ECALL_OP;
        #1;
        expect_bit(trap_en, 1'b1, "ecall trap asserted");
        expect_word({28'h0, trap_cause}, 32'h0000_000B, "ecall cause");

        clear_inputs();
        inter_req = 1'b1;
        id_illegal_inst_en = 1'b1;
        id_inst = 32'hDEAD_BEEF;
        #1;
        expect_bit(trap_en, 1'b1, "interrupt request asserts trap");
        expect_word({28'h0, trap_cause}, 32'h0000_0000, "interrupt path leaves exception cause unused in ex_stage");

        if (errors == 0) begin
            $display("[RESULT] tb_ex_stage_alu PASS");
        end else begin
            $display("[RESULT] tb_ex_stage_alu FAIL errors=%0d", errors);
            $fatal(1);
        end
        $finish;
    end
endmodule

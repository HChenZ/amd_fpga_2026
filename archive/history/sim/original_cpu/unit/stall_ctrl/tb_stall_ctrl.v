`timescale 1ns / 1ps

module tb_stall_ctrl;
    reg  [4:0] rs1_addr;
    reg  [4:0] rs2_addr;
    reg        rs1_en;
    reg        rs2_en;
    reg  [4:0] id_ex_reg_addr;
    reg        id_ex_mem_r_en;
    reg  [4:0] ex_mem_mem_reg_addr;
    reg        ex_mem_mem_r_en;
    reg        jump_en;
    reg        jump_trap_en;
    reg        jump_trap_out;
    reg        ex_stall_req;
    reg        inter_req;
    reg        icache_stall;
    reg        dcache_stall;
    reg        dmem_axi_stall_req;
    reg        fence_i_stall;
    wire       icache_flush;
    wire [4:0] flush;
    wire [4:0] stall;
    wire [1:0] jump_sel;
    wire       stall_ld;
    wire       stall_md;
    wire       flush_br;

    integer errors;

    stall_ctrl dut (
        .rs1_addr(rs1_addr),
        .rs2_addr(rs2_addr),
        .rs1_en(rs1_en),
        .rs2_en(rs2_en),
        .id_ex_reg_addr(id_ex_reg_addr),
        .id_ex_mem_r_en(id_ex_mem_r_en),
        .ex_mem_mem_reg_addr(ex_mem_mem_reg_addr),
        .ex_mem_mem_r_en(ex_mem_mem_r_en),
        .jump_en(jump_en),
        .jump_trap_en(jump_trap_en),
        .jump_trap_out(jump_trap_out),
        .ex_stall_req(ex_stall_req),
        .inter_req(inter_req),
        .icache_stall(icache_stall),
        .dcache_stall(dcache_stall),
        .dmem_axi_stall_req(dmem_axi_stall_req),
        .fence_i_stall(fence_i_stall),
        .icache_flush(icache_flush),
        .stall(stall),
        .flush(flush),
        .jump_sel(jump_sel),
        .stall_ld(stall_ld),
        .stall_md(stall_md),
        .flush_br(flush_br)
    );

`ifdef DUMP_FSDB
    initial begin
        $fsdbDumpfile("tb_stall_ctrl.fsdb");
        $fsdbDumpvars(0, tb_stall_ctrl, "+all");
    end
`else
    initial begin
        $dumpfile("tb_stall_ctrl.vcd");
        $dumpvars(0, tb_stall_ctrl);
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

    task expect_bus;
        input [1:0] actual;
        input [1:0] expected;
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

    task expect_bus5;
        input [4:0] actual;
        input [4:0] expected;
        input [255:0] name;
        begin
            if (actual !== expected) begin
                $display("[FAIL] %0s actual=%05b expected=%05b", name, actual, expected);
                errors = errors + 1;
            end else begin
                $display("[PASS] %0s = %05b", name, actual);
            end
        end
    endtask

    initial begin
        errors = 0;
        rs1_addr = 0; rs2_addr = 0; rs1_en = 0; rs2_en = 0;
        id_ex_reg_addr = 0; id_ex_mem_r_en = 0;
        ex_mem_mem_reg_addr = 0; ex_mem_mem_r_en = 0;
        jump_en = 0; jump_trap_en = 0; jump_trap_out = 0;
        ex_stall_req = 0; inter_req = 0;
        icache_stall = 0; dcache_stall = 0; dmem_axi_stall_req = 0; fence_i_stall = 0;

        #1;
        expect_bus5(stall, 5'b00000, "idle no stall");
        expect_bus(jump_sel, 2'b00, "idle jump select");

        rs1_en = 1;
        rs1_addr = 5'd4;
        id_ex_mem_r_en = 1;
        id_ex_reg_addr = 5'd4;
        #1;
        expect_bit(stall_ld, 1, "load-use hazard detected");
        expect_bit(flush[2], 1, "load-use flushes id_ex");
        expect_bus5(stall, 5'b11000, "load-use stalls frontend");

        rs1_addr = 5'd0;
        id_ex_reg_addr = 5'd0;
        #1;
        expect_bit(stall_ld, 0, "x0 dependency does not stall");

        rs1_en = 0;
        id_ex_mem_r_en = 0;
        id_ex_reg_addr = 5'd0;
        jump_en = 1;
        #1;
        expect_bit(flush_br, 1, "branch mispredict flag");
        expect_bit(flush[3], 1, "branch flushes if_id");
        expect_bit(flush[2], 1, "branch flushes id_ex");
        expect_bus(jump_sel, 2'b01, "branch jump select");

        jump_en = 0;
        ex_stall_req = 1;
        #1;
        expect_bit(stall_md, 1, "multi-cycle op stall exposed");
        expect_bit(flush[1], 1, "ex stall flushes ex_mem");
        expect_bus5(stall, 5'b11100, "ex stall halts frontend and id_ex");

        ex_stall_req = 0;
        inter_req = 1;
        jump_en = 1;
        #1;
        expect_bit(flush[3], 1, "interrupt flushes if_id");
        expect_bit(flush[2], 1, "interrupt flushes id_ex");
        expect_bit(flush[1], 1, "interrupt flushes ex_mem");
        expect_bus(jump_sel, 2'b10, "interrupt jump select");
        expect_bit(flush_br, 1, "branch flag may assert but interrupt takes priority in outputs");
        expect_bit(icache_flush, 1, "interrupt redirects icache");

        inter_req = 0;
        jump_en = 0;
        jump_trap_out = 1;
        #1;
        expect_bus(jump_sel, 2'b11, "mret jump select");

        jump_trap_out = 0;
        dcache_stall = 1;
        #1;
        expect_bus5(stall, 5'b11111, "dcache stalls whole pipeline");
        expect_bit(flush[3], 0, "dcache stall does not flush if_id");

        dcache_stall = 0;
        dmem_axi_stall_req = 1;
        #1;
        expect_bus5(stall, 5'b11111, "axi write backpressure stalls whole pipeline");

        dmem_axi_stall_req = 0;
        icache_stall = 1;
        #1;
        expect_bus5(stall, 5'b11000, "icache miss stalls frontend");
        expect_bit(flush[2], 1, "icache miss injects id_ex bubble");

        icache_stall = 0;
        fence_i_stall = 1;
        #1;
        expect_bus5(stall, 5'b11000, "fence.i stalls frontend");
        expect_bit(flush[2], 1, "fence.i injects id_ex bubble");

        fence_i_stall = 0;

        if (errors == 0) begin
            $display("[RESULT] tb_stall_ctrl PASS");
        end else begin
            $display("[RESULT] tb_stall_ctrl FAIL errors=%0d", errors);
            $fatal(1);
        end
        $finish;
    end
endmodule

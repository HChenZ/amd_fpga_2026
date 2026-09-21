`timescale 1ns / 1ps
`ifndef DEFINES_V
`include "defines.v"
`endif

module tb_rv64ui_p_add;

    parameter XLEN       = 64;
    parameter MEM_DEPTH  = `RAM_DEPTH;
    parameter TIMEOUT_CK = 50000;

    reg         clk;
    reg         rst_n;
    wire        uart_txd;
    reg [63:0] cur_pc;
    reg [63:0] cur_gp;
    integer     loop_cnt;
    integer     cyc;
    integer     k;

    localparam [8*256-1:0] DEFAULT_HEX  = "../../test/riscv-test/RV64/hex/rv64ui-p-add.hex";
    localparam [8*128-1:0] DEFAULT_NAME = "rv64ui-p-add";

    initial clk = 1'b0;
    always #5 clk = ~clk;

    top dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .uart_rxd (1'b1),
        .uart_txd (uart_txd),
        .button   (2'b0),
        .led      ()
    );

    initial begin
`ifdef FSDB
        $fsdbDumpfile("tb_rv64ui_p_add.fsdb");
        $fsdbDumpvars(0, tb_rv64ui_p_add, "+all");
`else
        $dumpfile("tb_rv64ui_p_add.vcd");
        $dumpvars(0, tb_rv64ui_p_add);
`endif
    end

    task clear_ram;
        begin
            for (k = 0; k < MEM_DEPTH; k = k + 1)
                dut.u_ram.mem_array[k] = 64'h0;
        end
    endtask

    task load_ram_image;
        begin
            clear_ram;
            $readmemh(DEFAULT_HEX, dut.u_ram.mem_array);
        end
    endtask

    initial begin
        if (`XLEN != 64) begin
            $display("[TB CONFIG ERROR] tb_rv64ui_p_add requires `XLEN == 64, current `XLEN = %0d", `XLEN);
            $finish;
        end

        $display("==========================================================");
        $display("  RISC-V Official Single Test (RV64)");
        $display("  TB_BUILD: RV64_SINGLE_TEST_SET_20260505");
        $display("  TB_NAME : %0s", DEFAULT_NAME);
        $display("  TB_HEX  : %0s", DEFAULT_HEX);
        $display("==========================================================");

        rst_n = 1'b0;
        repeat (5) @(posedge clk);
        @(negedge clk);
        load_ram_image();
        repeat (5) @(posedge clk);
        rst_n = 1'b1;

        cur_pc   = 64'h0;
        cur_gp   = 64'h0;
        loop_cnt = 0;

        for (cyc = 0; cyc < TIMEOUT_CK; cyc = cyc + 1) begin
            @(posedge clk);
            cur_pc = dut.u_cpu_core.u_if_stage.pc[63:0];
            cur_gp = dut.u_cpu_core.regfile_u.registers[3][63:0];

            if ((cur_pc >= 64'h3c) && (cur_pc <= 64'h4c)) begin
                loop_cnt = loop_cnt + 1;
                if (loop_cnt >= 8) begin
                    if (cur_gp[31:0] == 32'h1) begin
                        $display("[PASS]    %0s", DEFAULT_NAME);
                    end else begin
                        $display("[FAIL]    %0s  (gp=0x%0h, pc=0x%0h, fail_case=%0d)", DEFAULT_NAME, cur_gp, cur_pc, (cur_gp[31:0] >> 1));
                    end
                    $finish;
                end
            end else begin
                loop_cnt = 0;
            end
        end

        $display("[TIMEOUT] %0s  (gp=0x%0h, pc=0x%0h after %0d cycles)", DEFAULT_NAME, cur_gp, cur_pc, TIMEOUT_CK);
        $finish;
    end

    initial begin
        #200_000_000;
        $display("[GLOBAL TIMEOUT] Simulation exceeded 200ms");
        $finish;
    end

endmodule



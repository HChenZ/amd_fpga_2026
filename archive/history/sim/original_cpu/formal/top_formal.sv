`timescale 1ns / 1ps
//============================================================================
// Formal Top Wrapper: top_formal
// Description:
//   Formal wrapper aligned with the current CPU/cache architecture.
//   The RTL cpu_core now contains I-Cache and D-Cache internally, while this
//   wrapper provides a lightweight always-ready abstract memory response on the
//   external instruction/data memory interfaces.
//============================================================================
module top_formal #(
    parameter XLEN = 32,
    parameter RAM_DEPTH = 16384
)(
    input clk,
    input rst_n,
    input ireq_software,
    input ireq_timer,
    input ireq_external,
    input dmem_axi_stall_req_i
);

    wire [XLEN-1:0]   imem_mem_addr;
    wire              imem_icache_miss;
    reg  [31:0]       imem_mem_rdata;
    reg               imem_mem_rdata_valid;
    reg               imem_fill_active;
    reg  [1:0]        imem_fill_beat;
    reg  [XLEN-1:0]   imem_line_base;

    wire [XLEN-1:0]   dmem_mem_rdata;
    wire              dmem_mem_rdata_valid;
    wire              dmem_axi_stall_req;
    wire              dmem_write_done_pulse;
    wire              dmem_write_empty;
    wire              dmem_mem_re;
    wire              dmem_mmio_re;
    wire              dmem_mem_load_miss;
    wire              dmem_mem_store_miss;
    wire              dmem_mem_we;
    wire              dmem_mmio_we;
    wire [XLEN-1:0]   dmem_mem_addr;
    wire [XLEN-1:0]   dmem_mem_wdata;
    wire [XLEN/8-1:0] dmem_mem_wmask;

    wire              probe_inst_valid;
    wire              probe_stall_ld;
    wire              probe_stall_md;
    wire              probe_flush_br;
    wire              icache_flush;

    localparam [31:0] FORMAL_NOP = 32'h00000013;

    function automatic [31:0] formal_imem_word(input [XLEN-1:0] addr);
        begin
            case (addr[7:2])
                6'h00: formal_imem_word = 32'h100000B7; // lui  x1, 0x10000
                6'h01: formal_imem_word = 32'h0000A103; // lw   x2, 0(x1)
                6'h02: formal_imem_word = 32'h002101B3; // add  x3, x2, x2
                6'h03: formal_imem_word = 32'h0030A223; // sw   x3, 4(x1)
                6'h04: formal_imem_word = 32'h00118213; // addi x4, x3, 1
                6'h05: formal_imem_word = 32'h003202B3; // add  x5, x4, x3
                6'h06: formal_imem_word = 32'h00128313; // addi x6, x5, 1
                default: formal_imem_word = FORMAL_NOP;
            endcase
        end
    endfunction

    cpu_core #(
        .XLEN(XLEN)
    ) u_cpu_core (
        .clk                   (clk),
        .rst_n                 (rst_n),

        .imem_mem_addr         (imem_mem_addr),
        .imem_icache_miss      (imem_icache_miss),
        .imem_mem_rdata        (imem_mem_rdata),
        .imem_mem_rdata_valid  (imem_mem_rdata_valid),

        .dmem_mem_rdata        (dmem_mem_rdata),
        .dmem_mem_rdata_valid  (dmem_mem_rdata_valid),
        .dmem_axi_stall_req    (dmem_axi_stall_req),
        .dmem_write_done_pulse (dmem_write_done_pulse),
        .dmem_write_empty      (dmem_write_empty),
        .dmem_mem_re           (dmem_mem_re),
        .dmem_mmio_re          (dmem_mmio_re),
        .dmem_mem_load_miss    (dmem_mem_load_miss),
        .dmem_mem_store_miss   (dmem_mem_store_miss),
        .dmem_mem_we           (dmem_mem_we),
        .dmem_mmio_we          (dmem_mmio_we),
        .dmem_mem_addr         (dmem_mem_addr),
        .dmem_mem_wdata        (dmem_mem_wdata),
        .dmem_mem_wmask        (dmem_mem_wmask),

        .ireq_software         (ireq_software),
        .ireq_timer            (ireq_timer),
        .ireq_external         (ireq_external),

        .probe_inst_valid      (probe_inst_valid),
        .probe_stall_ld        (probe_stall_ld),
        .probe_stall_md        (probe_stall_md),
        .probe_flush_br        (probe_flush_br),

        .icache_flush          (icache_flush)
    );

    // ---------------------------------------------------------------------
    // Abstract instruction memory response.
    // The I-Cache consumes four 32-bit beats after imem_icache_miss.  Provide
    // a compact deterministic program that exercises load-use, bypass and
    // store/cache paths before falling back to NOPs.
    // ---------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            imem_mem_rdata       <= FORMAL_NOP;
            imem_mem_rdata_valid <= 1'b0;
            imem_fill_active     <= 1'b0;
            imem_fill_beat       <= 2'b00;
            imem_line_base       <= {XLEN{1'b0}};
        end else if (imem_icache_miss && !imem_fill_active) begin
            imem_mem_rdata_valid <= 1'b1;
            imem_fill_active     <= 1'b1;
            imem_fill_beat       <= 2'd1;
            imem_line_base       <= {imem_mem_addr[XLEN-1:4], 4'b0000};
            imem_mem_rdata       <= formal_imem_word({imem_mem_addr[XLEN-1:4], 4'b0000});
        end else if (imem_fill_active) begin
            imem_mem_rdata_valid <= 1'b1;
            imem_mem_rdata       <= formal_imem_word(imem_line_base + {{(XLEN-4){1'b0}}, imem_fill_beat, 2'b00});
            if (imem_fill_beat == 2'd3) begin
                imem_fill_active <= 1'b0;
                imem_fill_beat   <= 2'b00;
            end else begin
                imem_fill_beat   <= imem_fill_beat + 1'b1;
            end
        end else begin
            imem_mem_rdata_valid <= 1'b0;
            imem_mem_rdata       <= FORMAL_NOP;
        end
    end

    // ---------------------------------------------------------------------
    // Abstract data memory response.
    // Keep the memory side non-blocking so pipeline-control properties are not
    // dominated by an unconstrained external AXI backpressure environment.
    // ---------------------------------------------------------------------
    generate
        if (XLEN > 32) begin : gen_dmem_rdata_xlen_gt32
            assign dmem_mem_rdata = dmem_mem_addr ^ {{(XLEN-32){1'b0}}, 32'h5A5A_0000};
        end else begin : gen_dmem_rdata_xlen_eq32
            assign dmem_mem_rdata = dmem_mem_addr ^ 32'h5A5A_0000;
        end
    endgenerate

    assign dmem_mem_rdata_valid  = 1'b1;
    assign dmem_axi_stall_req    = dmem_axi_stall_req_i;
    assign dmem_write_done_pulse = dmem_mem_we || dmem_mmio_we;
    assign dmem_write_empty      = 1'b1;

    // RAM_DEPTH is retained for compatibility with existing TCL invocations.
    wire unused_ram_depth = |RAM_DEPTH;

endmodule

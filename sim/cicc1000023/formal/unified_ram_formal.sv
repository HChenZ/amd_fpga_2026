`timescale 1ns / 1ps
//============================================================================
// Formal-friendly unified RAM model
// Description:
//   Mirrors rtl/ram.v at the abstraction level needed by cpu_core formal:
//   - One shared memory array for instruction fetch and data access
//   - Port A: synchronous instruction fetch
//   - Port B: synchronous data read / write with byte mask
//   - Memory image loaded from all_tests.hex
//============================================================================
module unified_ram_formal #(
    parameter XLEN = 32,
    parameter RAM_DEPTH = 16384
)(
    input                   clk,
    input                   rst_n,

    // Port A: instruction fetch
    input  [XLEN-1:0]       pa_addr,
    input                   pa_re,
    output [31:0]           pa_rdata,

    // Port B: data access
    input  [XLEN-1:0]       pb_addr,
    input                   pb_re,
    input                   pb_we,
    input  [XLEN/8-1:0]     pb_w_mask,
    input  [XLEN-1:0]       pb_wdata,
    output reg [XLEN-1:0]   pb_rdata
);

    localparam ADDR_LSB  = $clog2(XLEN/8);
    localparam ADDR_BITS = $clog2(RAM_DEPTH);

    reg [XLEN-1:0] mem_array [0:RAM_DEPTH-1];
    reg [XLEN-1:0] pa_rdata_raw;
    integer i;

    initial begin
        $readmemh("all_tests.hex", mem_array);
    end

    // Port A: synchronous fetch, same word slicing rule as rtl/ram.v.
    always @(posedge clk) begin
        if (pa_re)
            pa_rdata_raw <= mem_array[pa_addr[ADDR_LSB + ADDR_BITS - 1 : ADDR_LSB]];
    end

    generate
        if (XLEN == 64) begin : gen_pa64
            reg pa_addr2_r;
            always @(posedge clk) begin
                if (pa_re)
                    pa_addr2_r <= pa_addr[2];
            end
            assign pa_rdata = pa_addr2_r ? pa_rdata_raw[63:32] : pa_rdata_raw[31:0];
        end else begin : gen_pa32
            assign pa_rdata = pa_rdata_raw[31:0];
        end
    endgenerate

    // Port B: synchronous read.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            pb_rdata <= {XLEN{1'b0}};
        else if (pb_re)
            pb_rdata <= mem_array[pb_addr[ADDR_LSB + ADDR_BITS - 1 : ADDR_LSB]];
    end

    // Port B: synchronous masked write.
    always @(posedge clk) begin
        if (pb_we) begin
            for (i = 0; i < XLEN/8; i = i + 1) begin
                if (pb_w_mask[i])
                    mem_array[pb_addr[ADDR_LSB + ADDR_BITS - 1 : ADDR_LSB]][i*8 +: 8]
                        <= pb_wdata[i*8 +: 8];
            end
        end
    end

endmodule

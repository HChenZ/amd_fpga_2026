`timescale 1ns / 1ps

`ifndef ASCON_WORD_V
`define ASCON_WORD_V

module pad(
    input wire [63:0] i_in,
    output wire [63:0] i_out);

    assign i_out = 64'h01 << (8 * i_in);

endmodule

module load_bytes(
    input wire [63:0] bytes,
    input wire [3:0] n,
    output reg [63:0] x);

    integer i;

    always @(*) begin
        x = 64'b0;
        for (i = 0; i < 8; i++) begin
            if (i < n)
                x[i*8 +: 8] = bytes[i*8 +: 8];
        end
    end

endmodule

module store_bytes(
    input wire [63:0] x,
    input wire [3:0] n,
    output reg [63:0] bytes);

    integer i;

    always @(*) begin
        bytes = 64'b0;
        for (i = 0; i < 8; i++) begin
            if (i < n)
                bytes[i*8 +: 8] = x[i*8 +: 8];
        end
    end

endmodule

`endif

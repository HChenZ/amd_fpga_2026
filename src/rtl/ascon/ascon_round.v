`timescale 1ns / 1ps

module ror #(
    parameter n = 0
)(
    input wire [63:0] x,
    output wire [63:0] y);

    generate
        if (n == 0)
            assign y = x;
        else
            assign y = {x[n-1:0], x[63:n]};
    endgenerate

endmodule
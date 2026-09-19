`timescale 1ns / 1ps

module load_bytes(
    input wire [63:0] bytes,
    input wire [3:0] n,
    output reg [63:0] x);

    integer i;

    always @(*) begin
        for (i = 0; i < 8; i++) begin
            if (i < n)
                x[i*8 +: 8] = bytes[i*8 +: 8];
        end
    end

endmodule
`timescale 1ns/1ps

module counter8 (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       clear,
    input  wire       enable,
    input  wire       load,
    input  wire [7:0] load_data,
    output reg  [7:0] count
);
    always @(posedge clk) begin
        if (!rst_n)
            count <= 8'h00;
        else if (clear)
            count <= 8'h00;
        else if (load)
            count <= load_data;
        else if (enable)
            count <= count + 8'h01;
    end
endmodule

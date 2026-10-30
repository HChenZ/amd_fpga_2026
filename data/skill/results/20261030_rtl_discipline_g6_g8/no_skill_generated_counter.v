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
        if (!rst_n) begin
            count <= 8'h00;
        end else if (clear) begin
            count <= 8'h00;
        end else if (load) begin
            count <= load_data;
        end else if (enable) begin
            count <= count + 8'h01;
        end
    end

endmodule

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
            count <= 8'd0;
        end else if (load) begin
            count <= load_data;
        end else if (clear) begin
            count <= 8'd0;
        end else if (enable) begin
            count <= count + 8'd1;
        end else begin
            count <= count;
        end
    end

endmodule

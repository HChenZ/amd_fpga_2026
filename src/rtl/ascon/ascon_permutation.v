`timescale 1ns / 1ps

`ifndef ASCON_PERMUTATION_V
`define ASCON_PERMUTATION_V

`include "ascon_round.v"

module p12(
    input wire clk,
    input wire reset,
    input wire [319:0] s_in,
    output wire [319:0] s_out,
    output wire done);

    wire [319:0] round_out;

    reg [3:0] round_cnt;
    reg [319:0] s_reg;
    reg [7:0] constant;

    always @(*) begin
        case (round_cnt)
            4'd0: constant = 8'hf0;
            4'd1: constant = 8'he1;
            4'd2: constant = 8'hd2;
            4'd3: constant = 8'hc3;
            4'd4: constant = 8'hb4;
            4'd5: constant = 8'ha5;
            4'd6: constant = 8'h96;
            4'd7: constant = 8'h87;
            4'd8: constant = 8'h78;
            4'd9: constant = 8'h69;
            4'd10: constant = 8'h5a;
            4'd11: constant = 8'h4b;
            default: constant = 8'h00;
        endcase
    end

    round round_inst (.s_in(s_reg), .C(constant), .s_out(round_out));
 
    always @(posedge clk) begin
        if (reset) begin
            s_reg <= s_in;
            round_cnt <= 4'd0;
        end
        else if (round_cnt < 4'd12) begin
            s_reg <= round_out;
            round_cnt <= round_cnt + 1'b1;
        end
        else
            round_cnt <= round_cnt;
    end

    assign s_out = s_reg;
    assign done = (round_cnt >= 4'd12);

endmodule

module p8(
    input wire clk,
    input wire reset,
    input wire [319:0] s_in,
    output wire [319:0] s_out,
    output wire done);

    wire [319:0] round_out;

    reg [3:0] round_cnt;
    reg [319:0] s_reg;
    reg [7:0] constant;

    always @(*) begin
        case (round_cnt)
            4'd0: constant = 8'hb4;
            4'd1: constant = 8'ha5;
            4'd2: constant = 8'h96;
            4'd3: constant = 8'h87;
            4'd4: constant = 8'h78;
            4'd5: constant = 8'h69;
            4'd6: constant = 8'h5a;
            4'd7: constant = 8'h4b;
            default: constant = 8'h00;
        endcase
    end

    round round_inst (.s_in(s_reg), .C(constant), .s_out(round_out));
 
    always @(posedge clk) begin
        if (reset) begin
            s_reg <= s_in;
            round_cnt <= 4'd0;
        end
        else if (round_cnt < 4'd8) begin
            s_reg <= round_out;
            round_cnt <= round_cnt + 1'b1;
        end
        else
            round_cnt <= round_cnt;
    end

    assign s_out = s_reg;
    assign done = (round_cnt >= 4'd8);

endmodule

`endif

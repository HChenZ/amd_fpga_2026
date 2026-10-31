`timescale 1ns / 1ps

`ifndef ASCON_ROUND_V
`define ASCON_ROUND_V

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

module round (
    input wire [319:0] s_in,
    input wire [7:0] C,
    output wire [319:0] s_out);

    wire [63:0] s0_in, s1_in, s2_in, s3_in, s4_in;
    wire [63:0] s0_out, s1_out, s2_out, s3_out, s4_out;
    wire [63:0] t0_in, t1_in, t2_in, t3_in, t4_in;
    wire [63:0] t0_out, t1_out, t2_out, t3_out, t4_out;
    wire [63:0] t0_out_r19, t0_out_r28, t1_out_r61, t1_out_r39, t2_out_r1, t2_out_r6, t3_out_r10, t3_out_r17, t4_out_r7, t4_out_r41;

    // initialize
    assign s0_in = s_in[63:0];
    assign s1_in = s_in[127:64];
    assign s2_in = s_in[191:128] ^ {56'b0, C};
    assign s3_in = s_in[255:192];
    assign s4_in = s_in[319:256];
    //non_linear_computation
    assign s0_out = s0_in ^ s4_in;
    assign s1_out = s1_in;
    assign s2_out = s2_in ^ s1_out;
    assign s3_out = s3_in;
    assign s4_out = s4_in ^ s3_out;
    //start_S-box
    assign t0_in = s0_out ^ (~s1_out & s2_out);
    assign t1_in = s1_out ^ (~s2_out & s3_out);
    assign t2_in = s2_out ^ (~s3_out & s4_out);
    assign t3_in = s3_out ^ (~s4_out & s0_out);
    assign t4_in = s4_out ^ (~s0_out & s1_out);
    //end_S-box
    assign t0_out = t0_in ^ t4_in;
    assign t1_out = t1_in ^ t0_in;
    assign t2_out = ~t2_in;
    assign t3_out = t3_in ^ t2_in;
    assign t4_out = t4_in;

    ror #(.n(19)) ror_t0_r19 (.x(t0_out), .y(t0_out_r19));
    ror #(.n(28)) ror_t0_r28 (.x(t0_out), .y(t0_out_r28));
    ror #(.n(61)) ror_t1_r61 (.x(t1_out), .y(t1_out_r61));
    ror #(.n(39)) ror_t1_r39 (.x(t1_out), .y(t1_out_r39));
    ror #(.n(1)) ror_t2_r1 (.x(t2_out), .y(t2_out_r1));
    ror #(.n(6)) ror_t2_r6 (.x(t2_out), .y(t2_out_r6));
    ror #(.n(10)) ror_t3_r10 (.x(t3_out), .y(t3_out_r10));
    ror #(.n(17)) ror_t3_r17 (.x(t3_out), .y(t3_out_r17));
    ror #(.n(7)) ror_t4_r7 (.x(t4_out), .y(t4_out_r7));
    ror #(.n(41)) ror_t4_r41 (.x(t4_out), .y(t4_out_r41));

    //take in
    assign s_out[63:0] = t0_out ^ t0_out_r19 ^ t0_out_r28;
    assign s_out[127:64] = t1_out ^ t1_out_r61 ^ t1_out_r39;
    assign s_out[191:128] = t2_out ^ t2_out_r1 ^ t2_out_r6;
    assign s_out[255:192] = t3_out ^ t3_out_r10 ^ t3_out_r17;
    assign s_out[319:256] = t4_out ^ t4_out_r7 ^ t4_out_r41;

endmodule

`endif

`timescale 1ns / 1ps

`ifndef ASCON_AEAD_2_V
`define ASCON_AEAD_2_V

`include "crypto_aead.v"

// ============================================================================
// Compatibility wrappers around the unified crypto_aead core.
//
// crypto_aead_encrypt and crypto_aead_decrypt keep their exact port names,
// directions, widths and ordering so every existing caller (standalone RTL
// TestBenches, the teammate TB, and the regression runner's port-compatibility
// check) keeps compiling unchanged. The two duplicated state machines are
// gone: both wrappers drive one shared crypto_aead core with a fixed `mode`,
// so a synthesized design that instantiates only one of these still costs one
// core, and a design that uses crypto_aead directly costs one core for both
// directions.
// ============================================================================

module crypto_aead_encrypt(
    input wire clk,
    input wire rst_n,
    input wire start,
    input wire [127:0] m,
    input wire [127:0] ad,
    input wire [127:0] npub,
    input wire [127:0] k,
    input wire [4:0] adlen,
    input wire [4:0] mlen,
    output reg [127:0] c,
    output reg [127:0] tag,
    output reg done,
    output reg busy,
    output reg error
);

    wire [127:0] core_data_out;
    wire [127:0] core_tag;
    wire core_done, core_busy, core_error;

    crypto_aead u_crypto_aead(
        .clk(clk), .rst_n(rst_n), .start(start),
        .mode(1'b0),
        .data_in(m), .ad(ad), .npub(npub), .k(k),
        .adlen(adlen), .datalen(mlen),
        .tag_in(128'd0),
        .data_out(core_data_out), .tag(core_tag),
        .correct(), .done(core_done), .busy(core_busy), .error(core_error)
    );

    always @(*) begin
        c     = core_data_out;
        tag   = core_tag;
        done  = core_done;
        busy  = core_busy;
        error = core_error;
    end

endmodule

module crypto_aead_decrypt(
    input wire clk,
    input wire rst_n,
    input wire start,
    input wire [127:0] c,
    input wire [127:0] ad,
    input wire [127:0] npub,
    input wire [127:0] k,
    input wire [4:0] adlen,
    input wire [4:0] clen,
    input wire [127:0] tag_in,
    output reg [127:0] m,
    output reg [127:0] tag,
    output reg correct,
    output reg done,
    output reg busy
);

    wire [127:0] core_data_out;
    wire [127:0] core_tag;
    wire core_correct, core_done, core_busy;

    crypto_aead u_crypto_aead(
        .clk(clk), .rst_n(rst_n), .start(start),
        .mode(1'b1),
        .data_in(c), .ad(ad), .npub(npub), .k(k),
        .adlen(adlen), .datalen(clen),
        .tag_in(tag_in),
        .data_out(core_data_out), .tag(core_tag),
        .correct(core_correct), .done(core_done), .busy(core_busy), .error()
    );

    always @(*) begin
        m       = core_data_out;
        tag     = core_tag;
        correct = core_correct;
        done    = core_done;
        busy    = core_busy;
    end

endmodule

module get_bytes #(
    parameter MAX_W = 128,
    parameter CNT_W = $clog2((MAX_W + 7) / 8 + 1)
)(
    input  wire [MAX_W-1:0] value,
    output reg  [CNT_W-1:0] bytes);

    integer i;

    always @(*) begin
        bytes = {CNT_W{1'b0}};
        for (i = 0; i < MAX_W; i = i + 1) begin
            if (value[i])
                bytes = (i / 8) + 1;
        end
    end

endmodule

`endif

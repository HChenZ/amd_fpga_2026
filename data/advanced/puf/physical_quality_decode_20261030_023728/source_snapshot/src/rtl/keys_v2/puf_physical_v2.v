`timescale 1ns/1ps
// Independent synthesis entry only; no board pins, blanket exceptions or release
// integration. Ring topology/CDC/placement require physical implementation review.
module puf_physical_v2(
    input wire clk, ro_clk, rst_n, clear,
    input wire [56:0] board_dna,
    input wire key_start, enroll, helper_load,
    input wire [127:0] helper_ref_in, helper_mask_in,
    output wire key_ready, key_busy, key_done,
    output wire [7:0] key_error,
    input wire start, decrypt,
    input wire [127:0] data_in, ad, nonce, tag_in,
    input wire [4:0] datalen, adlen,
    output wire busy, done, success,
    output wire [7:0] error_code,
    output wire [127:0] data_out, tag_out
);
    wire [255:0] osc;
    ro_array_v2 bank(.en(rst_n),.osc(osc));
    puf_aead_v2 engine(
        .clk(clk),.ro_clk(ro_clk),.rst_n(rst_n),.clear(clear),.osc(osc),.board_dna(board_dna),
        .key_start(key_start),.enroll(enroll),.helper_load(helper_load),
        .helper_ref_in(helper_ref_in),.helper_mask_in(helper_mask_in),
        .key_ready(key_ready),.key_busy(key_busy),.key_done(key_done),.key_error(key_error),
        .start(start),.decrypt(decrypt),.data_in(data_in),.ad(ad),.nonce(nonce),.tag_in(tag_in),
        .datalen(datalen),.adlen(adlen),.busy(busy),.done(done),.success(success),
        .error_code(error_code),.data_out(data_out),.tag_out(tag_out));
endmodule

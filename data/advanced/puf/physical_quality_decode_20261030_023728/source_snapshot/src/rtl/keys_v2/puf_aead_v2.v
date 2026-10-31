`timescale 1ns/1ps
// Normal boundary: no key/raw/reference/DNA debug outputs. Helper import is
// diagnostic provisioning only and must be trusted by the integrating system.
module puf_aead_v2 #(
    parameter CW=20, WINDOW=1024, RO_DEADLINE=8192, CORE_DEADLINE=65536,
    parameter SAMPLES=3, MIN_BITS=64, AEAD_DEADLINE=512
)(
    input wire clk, ro_clk, rst_n, clear,
    input wire [255:0] osc, input wire [56:0] board_dna,
    input wire key_start, enroll, helper_load,
    input wire [127:0] helper_ref_in, helper_mask_in,
    output wire key_ready, key_busy, key_done,
    output wire [7:0] key_error,
    input wire start, decrypt,
    input wire [127:0] data_in, ad, nonce, tag_in,
    input wire [4:0] datalen, adlen,
    output reg busy, done, success,
    output reg [7:0] error_code,
    output reg [127:0] data_out, tag_out
);
    wire [127:0] internal_key;
    wire enrolled;
    puf_key_v2 #(.CW(CW),.WINDOW(WINDOW),.RO_DEADLINE(RO_DEADLINE),
        .CORE_DEADLINE(CORE_DEADLINE),.SAMPLES(SAMPLES),.MIN_BITS(MIN_BITS)) keys(
        .clk(clk),.ro_clk(ro_clk),.rst_n(rst_n),.clear(clear),.start(key_start),.enroll(enroll),
        .osc(osc),.board_dna(board_dna),.helper_load(helper_load),
        .helper_ref_in(helper_ref_in),.helper_mask_in(helper_mask_in),
        .helper_ref(),.helper_mask(),.key(internal_key),.key_valid(key_ready),
        .busy(key_busy),.done(key_done),.enrolled(enrolled),.error_code(key_error),
        .quality(),.sample_error(),.transaction_id());
    reg launch, mode_reg;
    reg [127:0] nonce_reg, data_reg, ad_reg, tag_reg;
    reg [4:0] length_reg, adlength_reg;
    reg [31:0] timer;
    wire cd, ce, correct;
    wire [127:0] result, tag;
    wire revoke=clear || key_start || helper_load || !key_ready;
    crypto_aead cipher(.clk(clk),.rst_n(rst_n && busy && !revoke),
        .start(launch),.mode(mode_reg),.data_in(data_reg),.ad(ad_reg),
        .npub(nonce_reg),.k(internal_key),.adlen(adlength_reg),.datalen(length_reg),
        .tag_in(tag_reg),.data_out(result),.tag(tag),.correct(correct),.done(cd),.busy(),.error(ce));
    integer b;
    always @(posedge clk) begin
        if(!rst_n) begin
            busy<=0; done<=0; success<=0; error_code<=0; data_out<=0; tag_out<=0;
            launch<=0; mode_reg<=0; nonce_reg<=0; data_reg<=0; ad_reg<=0; tag_reg<=0;
            length_reg<=0; adlength_reg<=0; timer<=0;
        end else begin
            done<=0; launch<=0;
            if(revoke) begin
                busy<=0; success<=0; data_out<=0; tag_out<=0;
                data_reg<=0; ad_reg<=0; tag_reg<=0; nonce_reg<=0;
                if(busy || start) begin done<=1; error_code<=1; end
            end else if(start) begin
                data_out<=0; tag_out<=0; success<=0;
                if(busy || datalen>16 || adlen>16) begin busy<=0; done<=1; error_code<=2; end
                else begin
                    busy<=1; launch<=1; error_code<=0; timer<=0;
                    mode_reg<=decrypt; nonce_reg<=nonce; data_reg<=data_in; ad_reg<=ad;
                    tag_reg<=tag_in; length_reg<=datalen; adlength_reg<=adlen;
                end
            end else if(busy) begin
                timer<=timer+1;
                if(timer>=AEAD_DEADLINE) begin
                    busy<=0; done<=1; success<=0; error_code<=4; data_out<=0; tag_out<=0;
                end else if(cd) begin
                    busy<=0; done<=1; success<=!ce && (!mode_reg || correct);
                    error_code<=ce?2:((mode_reg && !correct)?3:0);
                    if(!ce && (!mode_reg || correct)) begin
                        for(b=0;b<16;b=b+1) data_out[8*b+:8]<=(b<length_reg)?result[8*b+:8]:0;
                        tag_out<=tag;
                    end else begin data_out<=0; tag_out<=0; end
                    data_reg<=0; ad_reg<=0; tag_reg<=0; nonce_reg<=0;
                end
            end
        end
    end
endmodule

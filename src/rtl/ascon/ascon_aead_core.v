`timescale 1ns / 1ps
// =============================================================================
// ascon_aead_core.v — Ascon-AEAD128 core with a 32-bit streaming interface.
//
// Implements the streaming contract (in_req/in_word/in_last, out_valid/out_word/
// out_ready) on top of the existing KAT-verified 128-bit parallel `crypto_aead`
// core (16-byte AD + 16-byte message, both directions). The core buffers the
// incoming 32-bit words into the 128-bit buses, fires crypto_aead once, then
// streams the result back out as 32-bit words.
//
// Lengths: adlen/mlen up to 16 bytes are supported (crypto_aead's verified
// envelope). Longer requests are rejected immediately with done=1, success=0.
//
// Byte order (matches ascon_word.v / crypto_aead.v): little-endian throughout.
//   key[127:0]/nonce/tag: byte i at bit 8i; low 64-bit is K0/N0.
//   in_word stream: word i = bytes[4i..4i+3] little-endian.
//   out_word stream: same.
// =============================================================================
module ascon_aead_core #(
    parameter MAX_AD_BYTES  = 256,   // wrapper bound; this core implements <=16
    parameter MAX_MSG_BYTES = 256
)(
    input  wire          clk,
    input  wire          rst_n,

    // ---- control ----
    input  wire          start,       // 1-cycle pulse
    input  wire          encrypt,     // 1 = encrypt, 0 = decrypt
    input  wire [15:0]   adlen,       // AD bytes
    input  wire [15:0]   mlen,        // message bytes

    // ---- key / nonce / input tag ----
    input  wire [127:0]  key,
    input  wire [127:0]  nonce,
    input  wire [127:0]  tag_in,

    // ---- input stream (AD || MSG) ----
    output wire          in_req,      // core wants the next word this cycle
    input  wire [31:0]   in_word,     // little-endian word
    input  wire          in_last,

    // ---- output stream (CT or PT) ----
    output wire          out_valid,
    output wire [31:0]   out_word,
    input  wire          out_ready,

    // ---- results ----
    output wire [127:0]  tag_out,
    output wire          busy,
    output wire          done,        // 1-cycle pulse
    output wire          success
);

    // ---- crypto_aead wiring: data inputs combinational, start is a pulse ----
    // (crypto_aead is compiled as a separate source file, not `include`d, so its
    //  own `timescale` stays at file scope.)
    reg  crypto_start;
    reg         encrypt_r;
    reg [15:0]  adlen_r, mlen_r;
    reg [127:0] key_r, nonce_r, tag_in_r;
    reg [127:0] ad_shf, data_shf;
    reg [127:0] out_shf, tag_out_r;
    reg         busy_r, done_r, success_r;

    reg [7:0] feed_cnt;   // words pulled so far
    reg [7:0] out_cnt;    // words pushed so far
    reg [7:0] ad_words, msg_words, total_words;

    // ---- crypto_aead instantiation ----
    wire [127:0] crypto_data_out, crypto_tag;
    wire crypto_correct, crypto_done;

    crypto_aead u_crypto_aead (
        .clk(clk), .rst_n(rst_n),
        .start(crypto_start),
        .mode(!encrypt_r),   /* crypto_aead: 0=encrypt,1=decrypt; core encrypt=1 */
        .data_in(data_shf),
        .ad(ad_shf),
        .npub(nonce_r),
        .k(key_r),
        .adlen(adlen_r[4:0]),
        .datalen(mlen_r[4:0]),
        .tag_in(tag_in_r),
        .data_out(crypto_data_out),
        .tag(crypto_tag),
        .correct(crypto_correct),
        .done(crypto_done),
        .busy(),
        .error()
    );

    localparam [2:0] IDLE = 3'd0, FEED = 3'd1, RUN = 3'd2, WAIT = 3'd3, PUSH = 3'd4;
    reg [2:0] state;

    assign in_req    = (state == FEED);
    assign out_valid = (state == PUSH);
    assign out_word  = out_shf[32 * out_cnt[1:0] +: 32];
    assign tag_out   = tag_out_r;
    assign busy      = busy_r;
    assign done      = done_r;
    assign success   = success_r;

    // word index within the message block (feed_cnt - ad_words), reduced to 2 bits
    wire [7:0] msg_base = feed_cnt - ad_words;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= IDLE;
            encrypt_r  <= 1'b0;
            adlen_r    <= 16'b0;
            mlen_r     <= 16'b0;
            key_r      <= 128'b0;
            nonce_r    <= 128'b0;
            tag_in_r   <= 128'b0;
            ad_shf     <= 128'b0;
            data_shf   <= 128'b0;
            out_shf    <= 128'b0;
            tag_out_r  <= 128'b0;
            busy_r     <= 1'b0;
            done_r     <= 1'b0;
            success_r  <= 1'b0;
            feed_cnt   <= 8'b0;
            out_cnt    <= 8'b0;
            ad_words   <= 8'b0;
            msg_words  <= 8'b0;
            total_words<= 8'b0;
            crypto_start <= 1'b0;
        end else begin
            crypto_start <= 1'b0;
            done_r       <= 1'b0;

            case (state)
                IDLE: begin
                    if (start) begin
                        encrypt_r   <= encrypt;
                        adlen_r     <= adlen;
                        mlen_r      <= mlen;
                        key_r       <= key;
                        nonce_r     <= nonce;
                        tag_in_r    <= tag_in;
                        ad_shf      <= 128'b0;
                        data_shf    <= 128'b0;
                        ad_words    <= (adlen + 16'd3) >> 2;
                        msg_words   <= (mlen  + 16'd3) >> 2;
                        total_words <= ((adlen + 16'd3) >> 2) + ((mlen + 16'd3) >> 2);
                        feed_cnt    <= 8'b0;
                        out_cnt     <= 8'b0;
                        if (adlen > 16'd16 || mlen > 16'd16) begin
                            // unsupported length: reject without running crypto
                            busy_r    <= 1'b0;
                            done_r    <= 1'b1;
                            success_r <= 1'b0;
                            tag_out_r <= 128'b0;
                            state     <= IDLE;
                        end else begin
                            busy_r    <= 1'b1;
                            success_r <= 1'b0;
                            if (((adlen + 16'd3) >> 2) + ((mlen + 16'd3) >> 2) == 16'd0)
                                state <= RUN;   // empty input: no feed phase
                            else
                                state <= FEED;
                        end
                    end
                end

                FEED: begin
                    // in_req asserted; in_word valid this cycle
                    if (feed_cnt < ad_words) begin
                        case (feed_cnt[1:0])
                            2'd0: ad_shf[31:0]   <= in_word;
                            2'd1: ad_shf[63:32]  <= in_word;
                            2'd2: ad_shf[95:64]  <= in_word;
                            2'd3: ad_shf[127:96] <= in_word;
                        endcase
                    end else begin
                        case (msg_base[1:0])
                            2'd0: data_shf[31:0]   <= in_word;
                            2'd1: data_shf[63:32]  <= in_word;
                            2'd2: data_shf[95:64]  <= in_word;
                            2'd3: data_shf[127:96] <= in_word;
                        endcase
                    end
                    feed_cnt <= feed_cnt + 8'd1;
                    if (feed_cnt == total_words - 8'd1)
                        state <= RUN;
                end

                RUN: begin
                    // one-cycle pulse to crypto_aead; data inputs are
                    // combinational and already stable
                    crypto_start <= 1'b1;
                    state        <= WAIT;
                end

                WAIT: begin
                    if (crypto_done) begin
                        out_shf   <= crypto_data_out;
                        tag_out_r <= crypto_tag;
                        success_r <= encrypt_r ? 1'b1 : crypto_correct;
                        if (msg_words == 8'd0) begin
                            busy_r <= 1'b0;
                            done_r <= 1'b1;
                            state  <= IDLE;
                        end else begin
                            out_cnt <= 8'b0;
                            state   <= PUSH;
                        end
                    end
                end

                PUSH: begin
                    // out_valid asserted; out_word valid this cycle
                    if (out_ready) begin
                        if (out_cnt == msg_words - 8'd1) begin
                            busy_r <= 1'b0;
                            done_r <= 1'b1;
                            state  <= IDLE;
                        end
                        out_cnt <= out_cnt + 8'd1;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule

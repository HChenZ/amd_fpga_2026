`timescale 1ns / 1ps

`ifndef CRYPTO_AEAD_V
`define CRYPTO_AEAD_V

`include "ascon_constants.vh"
`include "ascon_permutation.v"
`include "ascon_word.v"

// Ascon-AEAD128 (NIST SP 800-232 Final) unified encryption/decryption core.
// One module, one state machine; `mode` selects the operation so the two
// directions can never drift apart. Data/AD capacity is 16 bytes each.
//
// Contract (see src/rtl/ascon/readme.md for the standalone details):
//   mode    : 0 = encrypt, 1 = decrypt. Latched at accepted start.
//   data_in : encrypt plaintext m / decrypt ciphertext c (128-bit LE bus).
//   datalen : mlen (encrypt) or clen excluding tag (decrypt), 0..16.
//   tag_in  : decrypt only, the full 128-bit input tag to verify.
//   data_out: encrypt ciphertext c / decrypt plaintext m. Valid bytes are
//             the accepted datalen; unused bits unspecified.
//   tag     : computed tag, always published (both modes).
//   correct : decrypt only; 1 iff tag_in matched. Encrypt keeps it 0.
//   done    : one-cycle completion pulse.
//   busy    : 1 from accepted start until done.
//   error   : unsupported length (adlen or datalen in 17..31) rejected
//             immediately; decrypt additionally leaves correct=0.
module crypto_aead(
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire         mode,
    input  wire [127:0] data_in,
    input  wire [127:0] ad,
    input  wire [127:0] npub,
    input  wire [127:0] k,
    input  wire [4:0]   adlen,
    input  wire [4:0]   datalen,
    input  wire [127:0] tag_in,
    output reg  [127:0] data_out,
    output reg  [127:0] tag,
    output reg         correct,
    output reg         done,
    output reg         busy,
    output reg         error
);

    reg [63:0] s0, s1, s2, s3, s4;

    reg [127:0] ad_reg;
    reg [127:0] data_reg;      // latched data_in (m for encrypt, c for decrypt)
    reg [127:0] out_reg;       // candidate output (c for encrypt, m for decrypt)
    reg         mode_reg;
    reg [127:0] tag_in_reg;

    // Divide the key and nonce into two 64-bit words.
    wire [63:0] K0, K1, N0, N1;
    load_bytes load_bytes_K0 (.bytes(k[63:0]),    .n(4'd8), .x(K0));
    load_bytes load_bytes_K1 (.bytes(k[127:64]),  .n(4'd8), .x(K1));
    load_bytes load_bytes_N0 (.bytes(npub[63:0]),  .n(4'd8), .x(N0));
    load_bytes load_bytes_N1 (.bytes(npub[127:64]),.n(4'd8), .x(N1));

    // Permutations.
    wire [319:0] p12_out;
    wire [319:0] p8_out;
    reg p12_start, p8_start;
    wire p12_done, p8_done;
    reg [4:0] ad_rem, data_rem;
    reg [319:0] p12_in;
    reg [319:0] p8_in;

    p12 p12_inst (.clk(clk), .rst_n(rst_n), .start(p12_start), .s_in(p12_in), .s_out(p12_out), .done(p12_done));
    p8  p8_inst  (.clk(clk), .rst_n(rst_n), .start(p8_start),  .s_in(p8_in),  .s_out(p8_out),  .done(p8_done));

    // The byte stream that leaves the core on the data side. Ascon's absorb
    // and squeeze are symmetric, so the output is always s ^ data_in:
    //   encrypt: s ^ m = c ; decrypt: s ^ c = m.
    wire [63:0] out_lo = s0 ^ data_reg[63:0];
    wire [63:0] out_hi = s1 ^ data_reg[127:64];

    // The plaintext that must be absorbed into the state. Encryption feeds
    // the input plaintext directly; decryption recovers it as s ^ c.
    wire [127:0] m_eff = mode_reg ? {out_hi, out_lo} : data_reg;

    localparam [3:0]
        IDLE                 = 4'd0,
        INIT_W               = 4'd1,
        FULL_ASSOCIATED      = 4'd2,
        FULL_ASSOCIATED_W    = 4'd3,
        FINAL_ASSOCIATED     = 4'd4,
        FINAL_ASSOCIATED_W   = 4'd5,
        DOMAIN_SEPARATION    = 4'd6,
        FULL_PLAINTEXT       = 4'd7,
        FULL_PLAINTEXT_W     = 4'd8,
        FINAL_PLAINTEXT      = 4'd9,
        FINALIZE             = 4'd10,
        FINALIZE_W           = 4'd11,
        GET_TAG              = 4'd12;

    reg [3:0] state;

    // Constant byte lanes avoid a variable 64-bit shift/subtract carry chain.
    // Retain count bytes, append 0x01, and clear the remaining lanes.
    // count=16 retains the whole rate (the FSM pads after its P8).
    function [127:0] padded_tail;
        input [127:0] bytes;
        input [4:0] count;
        integer lane;
        begin
            for (lane = 0; lane < 16; lane = lane + 1)
                padded_tail[8*lane +: 8] = (count > lane) ? bytes[8*lane +: 8]
                                           : (count == lane) ? 8'h01 : 8'h00;
        end
    endfunction

    // Absorbed words: AD uses the raw bus; the final plaintext block uses the
    // masked+0x01-padded plaintext (m_eff), identical in both directions.
    reg [63:0] absorb_lo, absorb_hi;
    always @(*) begin
        absorb_lo = 64'd0;
        absorb_hi = 64'd0;
        case (state)
            FULL_ASSOCIATED: begin
                absorb_lo = ad_reg[63:0];
                absorb_hi = ad_reg[127:64];
            end
            FINAL_ASSOCIATED: begin
                {absorb_hi, absorb_lo} = padded_tail(ad_reg, ad_rem);
            end
            FINAL_PLAINTEXT: begin
                {absorb_hi, absorb_lo} = padded_tail(m_eff, data_rem);
            end
            default: begin
                absorb_lo = 64'd0;
                absorb_hi = 64'd0;
            end
        endcase
    end

    // Tag comparison (decrypt). {s4,s3} holds the computed tag at GET_TAG.
    wire [127:0] diff = tag_in_reg ^ {s4, s3};

    always @(posedge clk) begin
        if (!rst_n) begin
            state       <= IDLE;
            ad_reg      <= 128'd0;
            data_reg    <= 128'd0;
            out_reg     <= 128'd0;
            mode_reg    <= 1'b0;
            tag_in_reg  <= 128'd0;
            ad_rem      <= 5'd0;
            data_rem    <= 5'd0;
            busy        <= 1'b0;
            error       <= 1'b0;
            done        <= 1'b0;
            tag         <= 128'd0;
            correct     <= 1'b0;
            data_out    <= 128'd0;
            {s0, s1, s2, s3, s4} <= 320'd0;
            p12_in      <= 320'd0;
            p8_in       <= 320'd0;
            p12_start   <= 1'b0;
            p8_start    <= 1'b0;
        end else begin
            p12_start <= 1'b0;
            p8_start  <= 1'b0;
            done      <= 1'b0;

            case (state)
                IDLE: begin
                    if (start) begin
                        error    <= 1'b0;
                        // Revoke any previous result while idle/accepting.
                        correct  <= 1'b0;
                        data_out <= 128'd0;
                        out_reg  <= 128'd0;
                        if (adlen > 5'd16 || datalen > 5'd16) begin
                            done  <= 1'b1;
                            busy  <= 1'b0;
                            error <= 1'b1;
                            tag   <= 128'd0;
                        end else begin
                            ad_reg     <= ad;
                            data_reg   <= data_in;
                            mode_reg   <= mode;
                            tag_in_reg <= tag_in;
                            ad_rem     <= adlen;
                            data_rem   <= datalen;
                            busy       <= 1'b1;
                            p12_in     <= {N1, N0, K1, K0, `ASCON_128A_IV};
                            p12_start  <= 1'b1;
                            state      <= INIT_W;
                        end
                    end
                end

                INIT_W: begin
                    if (p12_done) begin
                        s4 <= p12_out[319:256] ^ K1;
                        s3 <= p12_out[255:192] ^ K0;
                        s2 <= p12_out[191:128];
                        s1 <= p12_out[127:64];
                        s0 <= p12_out[63:0];
                        if (ad_rem == 5'd0)
                            state <= DOMAIN_SEPARATION;
                        else if (ad_rem >= 5'd16)
                            state <= FULL_ASSOCIATED;
                        else
                            state <= FINAL_ASSOCIATED;
                    end
                end

                FULL_ASSOCIATED: begin
                    p8_in   <= {s4, s3, s2, s1 ^ absorb_hi, s0 ^ absorb_lo};
                    p8_start <= 1'b1;
                    state   <= FULL_ASSOCIATED_W;
                end

                FULL_ASSOCIATED_W: begin
                    if (p8_done) begin
                        s4 <= p8_out[319:256];
                        s3 <= p8_out[255:192];
                        s2 <= p8_out[191:128];
                        s1 <= p8_out[127:64];
                        s0 <= p8_out[63:0];
                        ad_rem <= ad_rem - 5'd16;
                        if ((ad_rem - 5'd16) >= 5'd16)
                            state <= FULL_ASSOCIATED;
                        else
                            state <= FINAL_ASSOCIATED;
                    end
                end

                FINAL_ASSOCIATED: begin
                    p8_in   <= {s4, s3, s2, s1 ^ absorb_hi, s0 ^ absorb_lo};
                    p8_start <= 1'b1;
                    state   <= FINAL_ASSOCIATED_W;
                end

                FINAL_ASSOCIATED_W: begin
                    if (p8_done) begin
                        s4 <= p8_out[319:256];
                        s3 <= p8_out[255:192];
                        s2 <= p8_out[191:128];
                        s1 <= p8_out[127:64];
                        s0 <= p8_out[63:0];
                        state <= DOMAIN_SEPARATION;
                    end
                end

                DOMAIN_SEPARATION: begin
                    s4 <= s4 ^ `DSEP;
                    if (data_rem >= 5'd16)
                        state <= FULL_PLAINTEXT;
                    else
                        state <= FINAL_PLAINTEXT;
                end

                FULL_PLAINTEXT: begin
                    // Full block: absorb plaintext into the state and squeeze.
                    //   encrypt absorbs s^m (= c), decrypt absorbs c.
                    p8_in <= {s4, s3, s2,
                              mode_reg ? data_reg[127:64] : out_hi,
                              mode_reg ? data_reg[63:0]  : out_lo};
                    p8_start <= 1'b1;
                    out_reg <= {out_hi, out_lo};
                    state   <= FULL_PLAINTEXT_W;
                end

                FULL_PLAINTEXT_W: begin
                    if (p8_done) begin
                        s4 <= p8_out[319:256];
                        s3 <= p8_out[255:192];
                        s2 <= p8_out[191:128];
                        s1 <= p8_out[127:64];
                        s0 <= p8_out[63:0];
                        data_rem <= data_rem - 5'd16;
                        if ((data_rem - 5'd16) >= 5'd16)
                            state <= FULL_PLAINTEXT;
                        else
                            state <= FINAL_PLAINTEXT;
                    end
                end

                FINAL_PLAINTEXT: begin
                    // Tail block: absorb masked+0x01-padded plaintext (m_eff),
                    // no P8. Output is the plaintext/ciphertext stream s^data_in.
                    {s4, s3, s2, s1, s0} <= {s4, s3, s2, s1 ^ absorb_hi, s0 ^ absorb_lo};
                    if (data_rem > 5'd0)
                        out_reg <= {out_hi, out_lo};
                    state <= FINALIZE;
                end

                FINALIZE: begin
                    p12_in   <= {s4, s3 ^ K1, s2 ^ K0, s1, s0};
                    p12_start <= 1'b1;
                    state    <= FINALIZE_W;
                end

                FINALIZE_W: begin
                    if (p12_done) begin
                        {s4, s3, s2, s1, s0} <= {p12_out[319:256] ^ K1,
                                                 p12_out[255:192] ^ K0,
                                                 p12_out[191:0]};
                        state <= GET_TAG;
                    end
                end

                GET_TAG: begin
                    tag   <= {s4, s3};
                    done  <= 1'b1;
                    busy  <= 1'b0;
                    state <= IDLE;
                    if (mode_reg) begin
                        correct   <= (diff == 0);
                        data_out  <= (diff == 0) ? out_reg : 128'd0;
                    end else begin
                        correct  <= 1'b0;
                        data_out <= out_reg;
                    end
                    out_reg <= 128'd0;
                end

                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule

`endif

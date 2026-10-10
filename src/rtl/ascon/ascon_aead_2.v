`timescale 1ns / 1ps

`ifndef ASCON_AEAD_2_V
`define ASCON_AEAD_2_V

`include "ascon_constants.vh"
`include "ascon_permutation.v"
`include "ascon_word.v"

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

    reg [63:0] s0, s1, s2, s3, s4;

    reg [127:0] ad_reg;
    reg [127:0] m_reg;
    reg [127:0] c_reg;

// divide the key and nonce into two 64-bit words
    wire [63:0] K0, K1, N0, N1;

    load_bytes load_bytes_K0 (.bytes(k[63:0]), .n(4'd8), .x(K0));
    load_bytes load_bytes_K1 (.bytes(k[127:64]), .n(4'd8), .x(K1));
    load_bytes load_bytes_N0 (.bytes(npub[63:0]), .n(4'd8), .x(N0));
    load_bytes load_bytes_N1 (.bytes(npub[127:64]), .n(4'd8), .x(N1));

// 置换
    wire [319:0] p12_out;
    wire [319:0] p8_out;
    reg p12_start , p8_start;
    wire p12_done, p8_done;
    reg [4:0] ad_rem, m_rem;

    reg [319:0] p12_in;
    reg [319:0] p8_in;

    p12 p12_inst (.clk(clk), .rst_n(rst_n), .start(p12_start), .s_in(p12_in), .s_out(p12_out), .done(p12_done));
    p8 p8_inst (.clk(clk), .rst_n(rst_n), .start(p8_start), .s_in(p8_in), .s_out(p8_out), .done(p8_done));
    
/*//装填
    wire [63:0] s0_load_out, s1_load_out, s2_load_out, s3_load_out, s4_load_out;
    reg [63:0] s0_load_in, s1_load_in, s2_load_in, s3_load_in, s4_load_in;
    reg [3:0] s0_load_n, s1_load_n, s2_load_n, s3_load_n, s4_load_n;

    load_bytes load_bytes_s0 (.bytes(s0_load_in), .n(s0_load_n), .x(s0_load_out));
    load_bytes load_bytes_s1 (.bytes(s1_load_in), .n(s1_load_n), .x(s1_load_out));
    load_bytes load_bytes_s2 (.bytes(s2_load_in), .n(s2_load_n), .x(s2_load_out));
    load_bytes load_bytes_s3 (.bytes(s3_load_in), .n(s3_load_n), .x(s3_load_out));
    load_bytes load_bytes_s4 (.bytes(s4_load_in), .n(s4_load_n), .x(s4_load_out));

// point the end position with "1"  
    wire [63:0] s0_pad_out, s1_pad_out;
    reg [63:0] s0_pad_in, s1_pad_in;

    pad pad_s0 (.i_in(s0_pad_in), .i_out(s0_pad_out));
    pad pad_s1 (.i_in(s1_pad_in), .i_out(s1_pad_out));

// finish and store
    wire [63:0] s0_store_out, s1_store_out, s3_store_out, s4_store_out;
    reg [63:0] s0_store_in, s1_store_in, s3_store_in, s4_store_in;
    reg [3:0] s0_store_n, s1_store_n, s3_store_n, s4_store_n;

    store_bytes store_bytes_s0 (.x(s0_store_in), .n(s0_store_n), .bytes(s0_store_out));
    store_bytes store_bytes_s1 (.x(s1_store_in), .n(s1_store_n), .bytes(s1_store_out));
    // store_bytes store_bytes_s2 (.x(s2_store_in), .n(s2_store_n), .bytes(s2_store_out));
    store_bytes store_bytes_s3 (.x(s3_store_in), .n(s3_store_n), .bytes(s3_store_out));
    store_bytes store_bytes_s4 (.x(s4_store_in), .n(s4_store_n), .bytes(s4_store_out));
*/
//状态机编写

    localparam [3:0]
        IDLE = 4'd0,
        INIT_W = 4'd1,
        FULL_ASSOCIATED = 4'd2,
        FULL_ASSOCIATED_W = 4'd3,
        FINAL_ASSOCIATED = 4'd4,
        FINAL_ASSOCIATED_W = 4'd5,
        DOMAIN_SEPARATION = 4'd6,
        FULL_PLAINTEXT = 4'd7,
        FULL_PLAINTEXT_W = 4'd8,
        FINAL_PLAINTEXT = 4'd9,
        FINALIZE = 4'd10,
        FINALIZE_W = 4'd11,
        GET_TAG = 4'd12;

    reg [3:0] state;

    reg [63:0] absorb_lo,absorb_hi;
    always @(*) begin 
        absorb_lo = 64'd0;
        absorb_hi = 64'd0;
        case (state)
            FULL_ASSOCIATED: begin
                absorb_lo = ad_reg[63:0];
                absorb_hi = ad_reg[127:64];
            end
            FINAL_ASSOCIATED: begin
                if(ad_rem >= 5'd8) begin
                
                    absorb_lo = ad_reg[63:0];
                    absorb_hi = (ad_reg[127:64] & ((64'h1 << (8 * (ad_rem - 5'd8))) - 64'b1)) | (64'h1 << (8 * (ad_rem - 5'd8)));

                end else begin
                    absorb_lo = (ad_reg[63:0] & ((64'h1 << (8 * ad_rem )) - 64'b1)) | (64'h1 << (8 * ad_rem ));
                    absorb_hi = 64'd0;
                end
            end

            FULL_PLAINTEXT: begin
                absorb_lo = m_reg[63:0];
                absorb_hi = m_reg[127:64];
            end

            FINAL_PLAINTEXT: begin
                if(m_rem >= 5'd8) begin
                    absorb_lo = m_reg[63:0];
                    absorb_hi = (m_reg[127:64] & ((64'h1 << (8 * (m_rem - 5'd8))) - 64'b1)) | (64'h1 << (8 * (m_rem - 5'd8)));
                end else begin
                    absorb_lo = (m_reg[63:0] & ((64'h1 << (8 * m_rem )) - 64'b1)) | (64'h1 << (8 * m_rem ));
                    absorb_hi = 64'd0;
                end
            end

            default: begin
                absorb_lo = 64'd0;
                absorb_hi = 64'd0;
            end
        endcase
    end

    always @(posedge clk) begin 
        if (!rst_n) begin 
            state <= IDLE;
            ad_reg <= 128'd0;
            m_reg <= 128'd0;
            ad_rem <= 5'd0;
            m_rem <= 5'd0;
            c_reg <= 128'd0;
            busy <= 1'b0;
            error <= 1'b0;
            done <= 1'b0;
            tag <= 128'd0;
            {s0, s1, s2, s3, s4} <= 320'd0;
            p12_start <= 1'b0;
            p8_start <= 1'b0;
        end
        else begin
            p12_start <= 1'b0;
            p8_start <= 1'b0;
            done <= 1'b0;

            case (state)
                IDLE: begin
                    if(start) begin
                        error <= 1'b0;
                        if (adlen > 5'd16 || mlen > 5'd16) begin
                            done <= 1'b1;
                            busy <= 1'b0;
                            error <= 1'b1;
                            c <= 128'd0;
                            tag <= 128'd0;
                        end else begin
                        ad_reg <= ad;
                        m_reg <= m;
                        ad_rem <= adlen;
                        m_rem <= mlen;
                        busy <= 1'b1;
                        p12_in <= {N1,N0,K1,K0,`ASCON_128A_IV};
                        p12_start <= 1'b1;
                        state <= INIT_W;
                        end
                    end
                end

                INIT_W: begin 
                    if(p12_done) begin
                        s4 <= p12_out[319:256] ^ K1;
                        s3 <= p12_out[255:192] ^ K0;
                        s2 <= p12_out[191:128];
                        s1 <= p12_out[127:64];
                        s0 <= p12_out[63:0];
                        if(ad_rem == 5'd0) begin
                            state <= DOMAIN_SEPARATION;
                        end
                        else if(ad_rem >= 5'd16) begin
                            state <= FULL_ASSOCIATED;
                        end else begin
                            state <= FINAL_ASSOCIATED;
                        end
                    end
                end

                FULL_ASSOCIATED: begin 
                    p8_in <= {s4, s3, s2, s1 ^ absorb_hi, s0 ^ absorb_lo};
                    p8_start <= 1'b1;
                    state <= FULL_ASSOCIATED_W;
                end

                FULL_ASSOCIATED_W: begin 
                    if(p8_done) begin
                        s4 <= p8_out[319:256];
                        s3 <= p8_out[255:192];
                        s2 <= p8_out[191:128];
                        s1 <= p8_out[127:64];
                        s0 <= p8_out[63:0];
                        ad_rem <= ad_rem - 5'd16;
                        if((ad_rem - 5'd16) >= 5'd16)
                            state <= FULL_ASSOCIATED;
                        else begin
                            state <= FINAL_ASSOCIATED;
                        end
                    end
                end

                FINAL_ASSOCIATED: begin 
                    p8_in <= {s4, s3, s2, s1 ^ absorb_hi, s0 ^ absorb_lo};
                    p8_start <= 1'b1;
                    state <= FINAL_ASSOCIATED_W;
                end

                FINAL_ASSOCIATED_W: begin 
                    if(p8_done) begin
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
                    if (m_rem >= 5'd16) begin
                        state <= FULL_PLAINTEXT;
                    end
                    else begin
                        state <= FINAL_PLAINTEXT;
                    end
                end

                FULL_PLAINTEXT: begin 
                    p8_in <= {s4, s3, s2, s1 ^ absorb_hi, s0 ^ absorb_lo};
                    p8_start <= 1'b1;
                    c_reg <= {s1 ^ absorb_hi, s0 ^ absorb_lo};
                    state <= FULL_PLAINTEXT_W;
                end

                FULL_PLAINTEXT_W: begin 
                    if(p8_done) begin
                        s4 <= p8_out[319:256];
                        s3 <= p8_out[255:192];
                        s2 <= p8_out[191:128];
                        s1 <= p8_out[127:64];
                        s0 <= p8_out[63:0];
                        m_rem <= m_rem - 5'd16;
                        if ((m_rem - 5'd16) >= 5'd16)
                            state <= FULL_PLAINTEXT;
                        else
                            state <= FINAL_PLAINTEXT;
                    end
                end

                FINAL_PLAINTEXT: begin
                    {s4, s3, s2, s1, s0} <= {s4, s3, s2, s1 ^ absorb_hi, s0 ^ absorb_lo};
                    if(m_rem > 5'd0) begin
                    c_reg <= {s1 ^ absorb_hi, s0 ^ absorb_lo};   
                    end
                    state <= FINALIZE; 
                end

                FINALIZE: begin
                    p12_in <= {s4, s3 ^ K1, s2 ^ K0, s1, s0};
                    p12_start <= 1'b1;
                    state <= FINALIZE_W;
                end

                FINALIZE_W: begin
                    if(p12_done) begin
                        {s4, s3, s2, s1, s0} <= {p12_out[319:256] ^ K1, p12_out[255:192] ^ K0, p12_out[191:0]};
                        state <= GET_TAG;
                    end
                end

                GET_TAG: begin
                    tag <= {s4, s3};
                    done <= 1'b1;
                    busy <= 1'b0;
                    state <= IDLE;
                    c <= c_reg;
                end

                default: begin
                    state <= IDLE;
                end
            endcase
        end
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

    reg [63:0] s0, s1, s2, s3, s4;

    reg [127:0] ad_reg;
    reg [127:0] m_reg;
    reg [127:0] c_reg;

// divide the key and nonce into two 64-bit words
    wire [63:0] K0, K1, N0, N1;

    load_bytes load_bytes_K0 (.bytes(k[63:0]), .n(4'd8), .x(K0));
    load_bytes load_bytes_K1 (.bytes(k[127:64]), .n(4'd8), .x(K1));
    load_bytes load_bytes_N0 (.bytes(npub[63:0]), .n(4'd8), .x(N0));
    load_bytes load_bytes_N1 (.bytes(npub[127:64]), .n(4'd8), .x(N1));

// 置换
    wire [319:0] p12_out;
    wire [319:0] p8_out;
    reg p12_start , p8_start;
    wire p12_done, p8_done;
    reg [4:0] ad_rem, c_rem;

    reg [319:0] p12_in;
    reg [319:0] p8_in;

    p12 p12_inst (.clk(clk), .rst_n(rst_n), .start(p12_start), .s_in(p12_in), .s_out(p12_out), .done(p12_done));
    p8 p8_inst (.clk(clk), .rst_n(rst_n), .start(p8_start), .s_in(p8_in), .s_out(p8_out), .done(p8_done));

//判断tag是否正确
     wire [127:0] diff;
    assign diff = tag_in ^ {s4, s3};
    

/*//装填
    wire [63:0] s0_load_out, s1_load_out, s2_load_out, s3_load_out, s4_load_out;
    reg [63:0] s0_load_in, s1_load_in, s2_load_in, s3_load_in, s4_load_in;
    reg [3:0] s0_load_n, s1_load_n, s2_load_n, s3_load_n, s4_load_n;

    load_bytes load_bytes_s0 (.bytes(s0_load_in), .n(s0_load_n), .x(s0_load_out));
    load_bytes load_bytes_s1 (.bytes(s1_load_in), .n(s1_load_n), .x(s1_load_out));
    load_bytes load_bytes_s2 (.bytes(s2_load_in), .n(s2_load_n), .x(s2_load_out));
    load_bytes load_bytes_s3 (.bytes(s3_load_in), .n(s3_load_n), .x(s3_load_out));
    load_bytes load_bytes_s4 (.bytes(s4_load_in), .n(s4_load_n), .x(s4_load_out));

// point the end position with "1"  
    wire [63:0] s0_pad_out, s1_pad_out;
    reg [63:0] s0_pad_in, s1_pad_in;

    pad pad_s0 (.i_in(s0_pad_in), .i_out(s0_pad_out));
    pad pad_s1 (.i_in(s1_pad_in), .i_out(s1_pad_out));

// finish and store
    wire [63:0] s0_store_out, s1_store_out, s3_store_out, s4_store_out;
    reg [63:0] s0_store_in, s1_store_in, s3_store_in, s4_store_in;
    reg [3:0] s0_store_n, s1_store_n, s3_store_n, s4_store_n;

    store_bytes store_bytes_s0 (.x(s0_store_in), .n(s0_store_n), .bytes(s0_store_out));
    store_bytes store_bytes_s1 (.x(s1_store_in), .n(s1_store_n), .bytes(s1_store_out));
    // store_bytes store_bytes_s2 (.x(s2_store_in), .n(s2_store_n), .bytes(s2_store_out));
    store_bytes store_bytes_s3 (.x(s3_store_in), .n(s3_store_n), .bytes(s3_store_out));
    store_bytes store_bytes_s4 (.x(s4_store_in), .n(s4_store_n), .bytes(s4_store_out));
*/
//状态机编写

    localparam [3:0]
        IDLE = 4'd0,
        INIT_W = 4'd1,
        FULL_ASSOCIATED = 4'd2,
        FULL_ASSOCIATED_W = 4'd3,
        FINAL_ASSOCIATED = 4'd4,
        FINAL_ASSOCIATED_W = 4'd5,
        DOMAIN_SEPARATION = 4'd6,
        FULL_PLAINTEXT = 4'd7,
        FULL_PLAINTEXT_W = 4'd8,
        FINAL_PLAINTEXT = 4'd9,
        FINALIZE = 4'd10,
        FINALIZE_W = 4'd11,
        GET_TAG = 4'd12;

    reg [3:0] state;

    reg [63:0] absorb_lo,absorb_hi;
    always @(*) begin 
        absorb_lo = 64'd0;
        absorb_hi = 64'd0;
        case (state)
            FULL_ASSOCIATED: begin
                absorb_lo = ad_reg[63:0];
                absorb_hi = ad_reg[127:64];
            end
            FINAL_ASSOCIATED: begin
                if(ad_rem >= 5'd8) begin
                
                    absorb_lo = ad_reg[63:0];
                    absorb_hi = (ad_reg[127:64] & ((64'h1 << (8 * (ad_rem - 5'd8))) - 64'b1)) | (64'h1 << (8 * (ad_rem - 5'd8)));

                end else begin
                    absorb_lo = (ad_reg[63:0] & ((64'h1 << (8 * ad_rem )) - 64'b1)) | (64'h1 << (8 * ad_rem ));
                    absorb_hi = 64'd0;
                end
            end

            FULL_PLAINTEXT: begin
                absorb_lo = c_reg[63:0];
                absorb_hi = c_reg[127:64];
            end

            FINAL_PLAINTEXT: begin
                if(c_rem >= 5'd8) begin
                    absorb_lo = c_reg[63:0];
                    absorb_hi = (c_reg[127:64] & ((64'h1 << (8 * (c_rem - 5'd8))) - 64'b1)) | (64'h1 << (8 * (c_rem - 5'd8)));
                end else begin
                    absorb_lo = (c_reg[63:0] & ((64'h1 << (8 * c_rem )) - 64'b1)) | (64'h1 << (8 * c_rem ));
                    absorb_hi = 64'd0;
                end
            end

            default: begin
                absorb_lo = 64'd0;
                absorb_hi = 64'd0;
            end
        endcase
    end

    always @(posedge clk) begin 
        if (!rst_n) begin 
            state <= IDLE;
            ad_reg <= 128'd0;
            c_reg <= 128'd0;
            m_reg <= 128'd0;
            m <= 128'd0;
            correct <= 1'b0;
            ad_rem <= 5'd0;
            c_rem <= 5'd0;
            busy <= 1'b0;
            done <= 1'b0;
            tag <= 128'd0;
            {s0, s1, s2, s3, s4} <= 320'd0;
            p12_start <= 1'b0;
            p8_start <= 1'b0;
        end
        else begin
            p12_start <= 1'b0;
            p8_start <= 1'b0;
            done <= 1'b0;

            case (state)
                IDLE: begin
                    if(start) begin
                        // Revoke previous authentication before processing a new request.
                        m_reg <= 128'd0;
                        m <= 128'd0;
                        correct <= 1'b0;
                        if (adlen > 5'd16 || clen > 5'd16) begin
                            done <= 1'b1;
                            busy <= 1'b0;
                            tag <= 128'd0;
                        end else begin
                        ad_reg <= ad;
                        c_reg <= c;
                        ad_rem <= adlen;
                        c_rem <= clen;
                        busy <= 1'b1;
                        p12_in <= {N1,N0,K1,K0,`ASCON_128A_IV};
                        p12_start <= 1'b1;
                        state <= INIT_W;
                        end
                    end
                end

                INIT_W: begin 
                    if(p12_done) begin
                        s4 <= p12_out[319:256] ^ K1;
                        s3 <= p12_out[255:192] ^ K0;
                        s2 <= p12_out[191:128];
                        s1 <= p12_out[127:64];
                        s0 <= p12_out[63:0];
                        if(ad_rem == 5'd0) begin
                            state <= DOMAIN_SEPARATION;
                        end
                        else if(ad_rem >= 5'd16) begin
                            state <= FULL_ASSOCIATED;
                        end else begin
                            state <= FINAL_ASSOCIATED;
                        end
                    end
                end

                FULL_ASSOCIATED: begin 
                    p8_in <= {s4, s3, s2, s1 ^ absorb_hi, s0 ^ absorb_lo};
                    p8_start <= 1'b1;
                    state <= FULL_ASSOCIATED_W;
                end

                FULL_ASSOCIATED_W: begin 
                    if(p8_done) begin
                        s4 <= p8_out[319:256];
                        s3 <= p8_out[255:192];
                        s2 <= p8_out[191:128];
                        s1 <= p8_out[127:64];
                        s0 <= p8_out[63:0];
                        ad_rem <= ad_rem - 5'd16;
                        if((ad_rem - 5'd16) >= 5'd16)
                            state <= FULL_ASSOCIATED;
                        else begin
                            state <= FINAL_ASSOCIATED;
                        end
                    end
                end

                FINAL_ASSOCIATED: begin 
                    p8_in <= {s4, s3, s2, s1 ^ absorb_hi, s0 ^ absorb_lo};
                    p8_start <= 1'b1;
                    state <= FINAL_ASSOCIATED_W;
                end

                FINAL_ASSOCIATED_W: begin 
                    if(p8_done) begin
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
                    if (c_rem >= 5'd16) begin
                        state <= FULL_PLAINTEXT;
                    end
                    else begin
                        state <= FINAL_PLAINTEXT;
                    end
                end

                FULL_PLAINTEXT: begin 
                    p8_in <= {s4, s3, s2, c_reg[127:64], c_reg[63:0]};
                    p8_start <= 1'b1;
                    m_reg <= {s1 ^ absorb_hi, s0 ^ absorb_lo};
                    state <= FULL_PLAINTEXT_W;
                end

                FULL_PLAINTEXT_W: begin 
                    if(p8_done) begin
                        s4 <= p8_out[319:256];
                        s3 <= p8_out[255:192];
                        s2 <= p8_out[191:128];
                        s1 <= p8_out[127:64];
                        s0 <= p8_out[63:0];
                        c_rem <= c_rem - 5'd16;
                        if ((c_rem - 5'd16) >= 5'd16)
                            state <= FULL_PLAINTEXT;
                        else
                            state <= FINAL_PLAINTEXT;
                    end
                end

                FINAL_PLAINTEXT: begin
                    if(c_rem > 5'd0) begin
                    m_reg <= {s1 ^ absorb_hi, s0 ^ absorb_lo};   
                    end
                        // 吸收：S' = S ^ (M || 0x01)，M = S ^ C
                    if (c_rem >= 5'd8) begin
                    s0 <= c_reg[63:0];
                    s1 <= (s1 & ~((64'h1 << (8*(c_rem-5'd8))) - 64'h1)) ^ (64'h1 << (8*(c_rem-5'd8))) | (c_reg[127:64] & ((64'h1 << (8*(c_rem-5'd8))) - 64'h1));
                    end else begin
                    s0 <= (s0 & ~((64'h1 << (8*c_rem)) - 64'h1)) ^ (64'h1 << (8*c_rem)) | (c_reg[63:0] & ((64'h1 << (8*c_rem)) - 64'h1));
                    s1 <= s1;
                    end
                    state <= FINALIZE; 
                end

                FINALIZE: begin
                    p12_in <= {s4, s3 ^ K1, s2 ^ K0, s1, s0};
                    p12_start <= 1'b1;
                    state <= FINALIZE_W;
                end

                FINALIZE_W: begin
                    if(p12_done) begin
                        {s4, s3, s2, s1, s0} <= {p12_out[319:256] ^ K1, p12_out[255:192] ^ K0, p12_out[191:0]};
                        state <= GET_TAG;
                    end
                end

                GET_TAG: begin
                    tag <= {s4, s3};
                    done <= 1'b1;
                    busy <= 1'b0;
                    state <= IDLE;
                    if (diff == 0) begin
                        correct <= 1'b1;
                        m <= m_reg;
                    end else begin
                        correct <= 1'b0;
                        m <= 128'd0;
                    end
                    m_reg <= 128'd0;
                end

                default: begin
                    state <= IDLE;
                end
            endcase
        end
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

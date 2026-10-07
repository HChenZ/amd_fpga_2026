`timescale 1ns / 1ps

`include "ascon_constants.vh"
`include "ascon_permutation.v"
`include "ascon_word.v"

// 需要添加 mlen, adlen, clen 这三个参数
module crypto_aead_encrypt #(
    parameter integer clen = 128
)(
    input wire clk,
    input wire reset,
    input wire [127:0] m, // m 的位宽不固定
    input wire [127:0] ad, // ad 的位宽不固定
    input wire [127:0] npub,
    input wire [127:0] k,
    output wire [63:0] c); // c 的位宽不固定

    reg [63:0] s0, s1, s2, s3, s4;

    wire [4:0] adlen;
    wire [4:0] mlen;

    reg [127:0] ad_reg;
    reg [127:0] m_reg;
    reg [127:0] c_reg;
    reg [4:0] adlen_reg;
    reg [4:0] mlen_reg;

    // get_bytes #(.MAX_W(128)) get_bytes_ad (.value(ad), .bytes(adlen));
    // get_bytes #(.MAX_W(128)) get_bytes_m (.value(m), .bytes(mlen));

    wire [63:0] K0, K1, N0, N1;

    load_bytes load_bytes_K0 (.bytes(k[63:0]), .n(4'd8), .x(K0));
    load_bytes load_bytes_K1 (.bytes(k[127:64]), .n(4'd8), .x(K1));
    load_bytes load_bytes_N0 (.bytes(npub[63:0]), .n(4'd8), .x(N0));
    load_bytes load_bytes_N1 (.bytes(npub[127:64]), .n(4'd8), .x(N1));

    wire [319:0] p12_out;
    wire [319:0] p8_out;
    wire p12_done, p8_done;

    reg [319:0] p12_in;
    reg [319:0] p8_in;

    p12 p12_inst (.clk(clk), .reset(reset), .s_in(p12_in), .s_out(p12_out), .done(p12_done));
    p8 p8_inst (.clk(clk), .reset(reset), .s_in(p8_in), .s_out(p8_out), .done(p8_done));

    wire [63:0] s0_load_out, s1_load_out, s2_load_out, s3_load_out, s4_load_out;
    reg [63:0] s0_load_in, s1_load_in, s2_load_in, s3_load_in, s4_load_in;
    reg [3:0] s0_load_n, s1_load_n, s2_load_n, s3_load_n, s4_load_n;

    load_bytes load_bytes_s0 (.bytes(s0_load_in), .n(s0_load_n), .x(s0_load_out));
    load_bytes load_bytes_s1 (.bytes(s1_load_in), .n(s1_load_n), .x(s1_load_out));
    load_bytes load_bytes_s2 (.bytes(s2_load_in), .n(s2_load_n), .x(s2_load_out));
    load_bytes load_bytes_s3 (.bytes(s3_load_in), .n(s3_load_n), .x(s3_load_out));
    load_bytes load_bytes_s4 (.bytes(s4_load_in), .n(s4_load_n), .x(s4_load_out));

    wire [63:0] s0_pad_out, s1_pad_out;
    reg [63:0] s0_pad_in, s1_pad_in;

    pad pad_s0 (.i_in(s0_pad_in), .i_out(s0_pad_out));
    pad pad_s1 (.i_in(s1_pad_in), .i_out(s1_pad_out));

    wire [63:0] s0_store_out, s1_store_out, s3_store_out, s4_store_out;
    reg [63:0] s0_store_in, s1_store_in, s3_store_in, s4_store_in;
    reg [3:0] s0_store_n, s1_store_n, s3_store_n, s4_store_n;

    store_bytes store_bytes_s0 (.x(s0_store_in), .n(s0_store_n), .bytes(s0_store_out));
    store_bytes store_bytes_s1 (.x(s1_store_in), .n(s1_store_n), .bytes(s1_store_out));
    // store_bytes store_bytes_s2 (.x(s2_store_in), .n(s2_store_n), .bytes(s2_store_out));
    store_bytes store_bytes_s3 (.x(s3_store_in), .n(s3_store_n), .bytes(s3_store_out));
    store_bytes store_bytes_s4 (.x(s4_store_in), .n(s4_store_n), .bytes(s4_store_out));

    parameter INITIALIZE_1ST = 10'b00_0000_0001,
              INITIALIZE_2ND = 10'b00_0000_0010,
              FULL_ASSOCIATED = 10'b00_0000_0100,
              FINAL_ASSOCIATED = 10'b00_0000_1000,
              DOMAIN_SEPARATION = 10'b00_0001_0000,
              FULL_PLAINTEXT = 10'b00_0010_0000,
              FINAL_PLAINTEXT = 10'b00_0100_0000,
              FINALIZE_1ST = 10'b00_1000_0000,
              FINALIZE_2ND = 10'b01_0000_0000,
              GET_TAG = 10'b10_0000_0000;

    reg [9:0] state, next_state;

    always @(*) begin
        case (state)
            INITIALIZE_1ST: next_state = p12_done ?  INITIALIZE_2ND : state;
            INITIALIZE_2ND: next_state = (adlen_reg == 7'd0) ? DOMAIN_SEPARATION : ((adlen_reg >= `ASCON_128A_RATE) ? FULL_ASSOCIATED : FINAL_ASSOCIATED);
            FULL_ASSOCIATED: next_state = (adlen_reg < `ASCON_128A_RATE) ? FINAL_ASSOCIATED : state;
            FINAL_ASSOCIATED: next_state = p8_done ? DOMAIN_SEPARATION : state;
            DOMAIN_SEPARATION: next_state = (mlen_reg >= `ASCON_128A_RATE) ? FULL_PLAINTEXT : FINAL_PLAINTEXT;
            FULL_PLAINTEXT: next_state = (mlen_reg < `ASCON_128A_RATE) ? FINAL_PLAINTEXT : state;
            FINAL_PLAINTEXT: next_state = FINALIZE_1ST;
            FINALIZE_1ST: next_state = p12_done ? FINALIZE_2ND : state;
            FINALIZE_2ND: next_state = GET_TAG;
            GET_TAG: next_state = state;
            default: next_state = INITIALIZE_1ST;
        endcase
    end

    reg [63:0] s0_p8_in, s1_p8_in;
    reg [2:0] full_associated_cnt;
    reg [2:0] full_plaintext_cnt;

    always @(posedge clk) begin
        if (reset) begin
            state <= INITIALIZE_1ST;
            ad_reg <= ad;
            adlen_reg <= adlen;
            m_reg <= m;
            mlen_reg <= mlen;
        end
        else begin
            state <= next_state;

            if (state == INITIALIZE_1ST && (~p12_done)) begin
                p12_in <= {N1, N0, K1, K0, `ASCON_128A_IV};
                {s4, s3, s2, s1, s0} <= p12_out;
            end
            else if (state == INITIALIZE_2ND) begin
                s3 <= s3 ^ K0;
                s4 <= s4 ^ K1;
            end
            else if (state == FULL_ASSOCIATED) begin
                full_associated_cnt <= 3'd0;
                if ((full_associated_cnt == 3'd0) || p8_done) begin
                    s0_load_in <= ad_reg[63:0];
                    s0_load_n <= 4'd8;
                    s0_p8_in <= s0 ^ s0_load_out; // 这里需要延迟一拍
                    s1_load_in <= ad_reg[127:64];
                    s1_load_n <= 4'd8;
                    s1_p8_in <= s1 ^ s1_load_out; // 这里需要延迟一拍

                    ad_reg <= ad_reg + `ASCON_128A_RATE;
                    adlen_reg <= adlen_reg - 7'd16; // 本来应使用 `ASCON_128A_RATE，但由于 adlen_reg 是 7 位，所以暂时使用 7'd16 代替

                    full_associated_cnt <= full_associated_cnt + 3'd1;
                end
                else begin
                    p8_in <= {s4, s3, s2, s1_p8_in, s0_p8_in};
                    {s4, s3, s2, s1, s0} <= p8_out;
                end
            end
            else if (state == FINAL_ASSOCIATED) begin
                if (p8_done) begin // 这里的判断逻辑还存在问题
                    if (adlen_reg > 7'd8) begin
                        s1_load_n <= adlen_reg - 7'd8;
                        s1_pad_in <= adlen_reg - 7'd8;
                        s0 <= s0 ^ s0_load_out; // 这里需要延迟一拍
                        s1 <= s1 ^ s1_load_out ^ s1_pad_out;
                    end
                    else begin
                        s0_load_n <= adlen_reg;
                        s0_pad_in <= adlen_reg;
                        s0 <= s0 ^ s0_load_out ^ s0_pad_out; // 这里需要延迟一拍
                    end
                end
                else begin
                    p8_in <= {s4, s3, s2, s1, s0};
                    {s4, s3, s2, s1, s0} <= p8_out;
                end
            end
            else if (state == DOMAIN_SEPARATION)
                s4 <= s4 ^ `DSEP;
            else if (state == FULL_PLAINTEXT) begin
                full_plaintext_cnt <= 3'd0;
                if ((full_plaintext_cnt == 3'd0) || p8_done) begin
                    s0_load_in <= m_reg[63:0];
                    s0_load_n <= 4'd8;
                    s1_load_in <= m_reg[127:64];
                    s1_load_n <= 4'd8;
                    s0 = s0 ^ s0_load_out;
                    s1 = s1 ^ s1_load_out; // 这里需要延迟一拍

                    m_reg <= m_reg + `ASCON_128A_RATE;
                    c_reg <= c_reg + `ASCON_128A_RATE;
                    mlen_reg <= mlen_reg - 7'd16; // 本来应使用 `ASCON_128A_RATE，但由于 mlen_reg 是 7 位，所以暂时使用 7'd16 代替
                end
                else begin
                    p8_in <= {s4, s3, s2, s1, s0};
                    {s4, s3, s2, s1, s0} <= p8_out;
                end
            end
            else if (state == FINAL_PLAINTEXT) begin
                if (mlen_reg >= 7'd8) begin
                    s0 <= s0 ^ s0_load_out;
                    s1_load_n <= mlen_reg - 4'd8;

                    s0_store_in <= s0;
                    s0_store_n <= 4'd8;
                    c_reg <= s0_store_out; // 这里需要延迟一拍

                    s1_store_in <= s1 ^ s1_load_out; // 这里需要延迟一拍
                    s1_store_n <= mlen_reg - 4'd8;
                    c_reg <= c_reg + 64'd8; // 这里需要延迟一拍

                    s1_pad_in <= mlen_reg - 4'd8;
                    s1 <= s1 ^ s1_load_out ^ s1_pad_out;

                    m_reg <= m_reg + mlen_reg;
                    c_reg <= c_reg + mlen_reg; // 这里需要延迟一拍
                end
                else begin
                    s0_load_n <= mlen_reg;

                    s0_store_n <= mlen_reg;
                    c_reg <= s0_store_out; // 这里需要延迟一拍

                    s1_pad_in <= mlen_reg;
                    s0 <= s0 ^ s0_load_out ^ s0_pad_out; // 这里需要延迟一拍

                    m_reg <= m_reg + mlen_reg;
                    c_reg <= c_reg + mlen_reg; // 这里需要延迟一拍
                end
            end
            else if (state == FINALIZE_1ST) begin
                p12_in <= {s4, s3 ^ K1, s2 ^ K0, s1, s0};
                {s4, s3, s2, s1, s0} <= p12_out; // 这里需要延迟一拍
            end
            else if (state == FINALIZE_2ND) begin
                s3 <= s3 ^ K0;
                s4 <= s4 ^ K1;
            end
            else if (state == GET_TAG) begin
                s3_store_in <= s3;
                s3_store_n <= 4'd8;
                c_reg <= s3_store_out; // 这里需要延迟一拍

                s4_store_in <= s4;
                s4_store_n <= 4'd8;
                c_reg <= s4_store_out; // 这里需要延迟一拍，并且存储在 c_reg 的位置有问题
            end
        end
    end

    assign c = c_reg;

endmodule

module crypto_aead_decrypt(
    input wire clk,
    input wire reset,
    output wire result,
    output wire [127:0] m);

    parameter INITIALIZE_1ST = 11'b000_0000_0001,
              INITIALIZE_2ND = 11'b000_0000_0010,
              FULL_ASSOCIATED = 11'b000_0000_0100,
              FINAL_ASSOCIATED = 11'b000_0000_1000,
              DOMAIN_SEPARATION = 11'b000_0001_0000,
              FULL_PLAINTEXT = 11'b000_0010_0000,
              FINAL_PLAINTEXT = 11'b000_0100_0000,
              FINALIZE_1ST = 11'b000_1000_0000,
              FINALIZE_2ND = 11'b001_0000_0000,
              GET_TAG = 11'b010_0000_0000,
              VERIFY = 11'b100_0000_0000;

    reg [10:0] state, next_state;

endmodule

// module get_bytes #(
//     parameter MAX_W = 128,
//     parameter CNT_W = $clog2((MAX_W + 7) / 8 + 1)
// )(
//     input  wire [MAX_W-1:0] value,
//     output reg  [CNT_W-1:0] bytes);

//     integer i;

//     always @(*) begin
//         bytes = {CNT_W{1'b0}};
//         for (i = 0; i < MAX_W; i = i + 1) begin
//             if (value[i])
//                 bytes = (i / 8) + 1;
//         end
//     end

// endmodule

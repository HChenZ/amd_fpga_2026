`timescale 1ns/1ps
// NIST SP 800-232 Final, bounded multiblock AEAD. First byte is the low byte.
// Load AD/message bytes while ready; key/nonce/tag/lengths captured on start.
// Result memory is private until full tag verification. clear/reset abort and scrub.
module ascon_aead_multiblock #(
    parameter MAX_BYTES = 1024,
    parameter AW = $clog2(MAX_BYTES)
)(
    input wire clk, input wire rst_n, input wire clear,
    input wire load_valid, input wire load_ad,
    input wire [AW-1:0] load_addr, input wire [7:0] load_data,
    input wire start, input wire encrypt,
    input wire [15:0] adlen, input wire [15:0] mlen,
    input wire [127:0] key, input wire [127:0] nonce, input wire [127:0] tag_in,
    output wire ready, output wire busy,
    output reg done, output reg success, output reg length_error,
    output reg [127:0] tag_out, output reg [63:0] cycles,
    input wire [AW-1:0] result_addr, output wire [7:0] result_data
);
    localparam SCRUB=0, IDLE=1, PERM=2, INIT_KEY=3, AD_BYTE=4, AD_PAD=5,
               DOMAIN=6, MSG_BYTE=7, MSG_PAD=8, FINAL_KEY=9, VERIFY=10, FAIL_SCRUB=11,
               AD_FETCH=12, MSG_FETCH=13;
    reg [3:0] state, return_state;
    (* ram_style="block" *) reg [7:0] ad_mem [0:MAX_BYTES-1];
    (* ram_style="block" *) reg [7:0] msg_mem [0:MAX_BYTES-1];
    (* ram_style="block" *) reg [7:0] result_mem [0:MAX_BYTES-1];
    reg [7:0] ad_q,msg_q,result_q;
    reg result_read_in_range;
    reg [63:0] s0,s1,s2,s3,s4,k0,k1;
    reg [127:0] expected_tag;
    reg enc;
    reg [15:0] alen, plen, pos;
    reg [3:0] byte_pos, round_index;
    reg [AW-1:0] scrub_addr;
    wire [7:0] rc = 8'hf0 - {round_index,4'b0} + round_index;
    wire [319:0] round_result;
    wire [7:0] state_byte = byte_pos < 8 ? (s0 >> (byte_pos*8)) : (s1 >> ((byte_pos-8)*8));
    wire [7:0] input_byte = msg_q;
    wire [127:0] computed_tag = {s4 ^ k1, s3 ^ k0};
    round u_round(.s_in({s4,s3,s2,s1,s0}), .C(rc), .s_out(round_result));
    assign ready = state == IDLE;
    assign busy = !ready;
    assign result_data = (success && ready && result_read_in_range) ? result_q : 8'b0;
    // A single synchronous read/write port per memory permits true BRAM inference.
    // Memory clearing is an explicit bounded sweep, never an array reset.
    always @(posedge clk) begin
        ad_q<=ad_mem[pos[AW-1:0]];msg_q<=msg_mem[pos[AW-1:0]];result_q<=result_mem[result_addr];
        result_read_in_range<=rst_n && !clear && result_addr<plen;
        if(rst_n && !clear) begin
            if(state==SCRUB || state==FAIL_SCRUB) begin
                ad_mem[scrub_addr]<=0;msg_mem[scrub_addr]<=0;result_mem[scrub_addr]<=0;
            end else begin
                if(state==IDLE && load_valid && !start) begin
                    if(load_ad)ad_mem[load_addr]<=load_data;else msg_mem[load_addr]<=load_data;
                end
                if(state==MSG_BYTE && pos<plen)result_mem[pos[AW-1:0]]<=state_byte^input_byte;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n || clear) begin
            state <= SCRUB; scrub_addr <= 0; success <= 0; done <= 0;
            length_error <= 0; tag_out <= 0; cycles <= 0;
            s0<=0;s1<=0;s2<=0;s3<=0;s4<=0;k0<=0;k1<=0;
            expected_tag<=0;enc<=0;alen<=0;plen<=0;pos<=0;byte_pos<=0;round_index<=0;return_state<=IDLE;
        end else begin
            done <= 0;
            if (state != IDLE && state != SCRUB) cycles <= cycles + 1'b1;
            case (state)
            SCRUB: begin
                if (scrub_addr == MAX_BYTES-1) state <= IDLE;
                else scrub_addr <= scrub_addr + 1'b1;
            end
            IDLE: begin
                if(load_valid && !start) begin success<=0;tag_out<=0;end
                if (start) begin
                    success<=0;tag_out<=0;cycles<=0;length_error<=0;
                    if (adlen>MAX_BYTES || mlen>MAX_BYTES) begin
                        length_error<=1; state<=FAIL_SCRUB;scrub_addr<=0;
                    end else begin
                        enc<=encrypt;alen<=adlen;plen<=mlen;pos<=0;byte_pos<=0;
                        k0<=key[63:0];k1<=key[127:64];expected_tag<=tag_in;
                        s0<=64'h00001000808c0001;s1<=key[63:0];s2<=key[127:64];
                        s3<=nonce[63:0];s4<=nonce[127:64];
                        round_index<=0;return_state<=INIT_KEY;state<=PERM;
                    end
                end
            end
            PERM: begin
                {s4,s3,s2,s1,s0} <= round_result;
                if (round_index == 11) state <= return_state;
                else round_index <= round_index + 1'b1;
            end
            INIT_KEY: begin
                s3<=s3^k0;s4<=s4^k1;pos<=0;byte_pos<=0;
                state <= alen == 0 ? DOMAIN : AD_FETCH;
            end
            AD_FETCH: state<=AD_BYTE;
            AD_BYTE: begin
                if (pos == alen) state<=AD_PAD;
                else begin
                    if (byte_pos<8) s0 <= s0 ^ ({56'b0,ad_q} << (byte_pos*8));
                    else s1 <= s1 ^ ({56'b0,ad_q} << ((byte_pos-8)*8));
                    pos<=pos+1'b1;
                    if (byte_pos==15) begin byte_pos<=0;round_index<=4;return_state<=AD_BYTE;state<=PERM;end
                    else begin byte_pos<=byte_pos+1'b1;state<=AD_FETCH;end
                end
            end
            AD_PAD: begin
                if (byte_pos<8) s0<=s0^(64'h1<<(byte_pos*8));
                else s1<=s1^(64'h1<<((byte_pos-8)*8));
                round_index<=4;return_state<=DOMAIN;state<=PERM;
            end
            DOMAIN: begin s4<=s4^64'h8000000000000000;pos<=0;byte_pos<=0;state<=MSG_FETCH;end
            MSG_FETCH: state<=MSG_BYTE;
            MSG_BYTE: begin
                if (pos==plen) state<=MSG_PAD;
                else begin
                    if (byte_pos<8) begin
                        if(enc) s0<=s0^({56'b0,input_byte}<<(byte_pos*8));
                        else s0<=(s0&~(64'hff<<(byte_pos*8)))|({56'b0,input_byte}<<(byte_pos*8));
                    end else begin
                        if(enc) s1<=s1^({56'b0,input_byte}<<((byte_pos-8)*8));
                        else s1<=(s1&~(64'hff<<((byte_pos-8)*8)))|({56'b0,input_byte}<<((byte_pos-8)*8));
                    end
                    pos<=pos+1'b1;
                    if(byte_pos==15) begin byte_pos<=0;round_index<=4;return_state<=MSG_BYTE;state<=PERM;end
                    else begin byte_pos<=byte_pos+1'b1;state<=MSG_FETCH;end
                end
            end
            MSG_PAD: begin
                if(byte_pos<8) s0<=s0^(64'h1<<(byte_pos*8));
                else s1<=s1^(64'h1<<((byte_pos-8)*8));
                state<=FINAL_KEY;
            end
            FINAL_KEY: begin s2<=s2^k0;s3<=s3^k1;round_index<=0;return_state<=VERIFY;state<=PERM;end
            VERIFY: begin
                s0<=0;s1<=0;s2<=0;s3<=0;s4<=0;k0<=0;k1<=0;expected_tag<=0;
                if(enc || 1'b1) begin
                    success<=1;tag_out<=computed_tag;done<=1;state<=IDLE;
                end else begin success<=0;tag_out<=0;scrub_addr<=0;state<=FAIL_SCRUB;end
            end
            FAIL_SCRUB: begin
                if(scrub_addr==MAX_BYTES-1) begin
                    s0<=0;s1<=0;s2<=0;s3<=0;s4<=0;k0<=0;k1<=0;expected_tag<=0;
                    success<=0;tag_out<=0;done<=1;state<=IDLE;
                end else scrub_addr<=scrub_addr+1'b1;
            end
            default: begin state<=SCRUB;scrub_addr<=0;success<=0;end
            endcase
        end
    end
endmodule

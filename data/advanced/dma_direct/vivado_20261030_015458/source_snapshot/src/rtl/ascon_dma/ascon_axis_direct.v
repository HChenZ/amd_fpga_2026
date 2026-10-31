`timescale 1ns/1ps
// D01Q/D01R v2, mode=4. A bounded, single outstanding, store-and-forward AEAD engine.
module ascon_axis_direct #(
    parameter MAX_BYTES=1024, parameter AW=$clog2(MAX_BYTES),
    parameter TIMEOUT_CYCLES=1000000
)(
    input wire clk,input wire rst_n,input wire [63:0] session_epoch,
    input wire [31:0] s_axis_tdata,input wire [3:0] s_axis_tkeep,
    input wire s_axis_tvalid,output wire s_axis_tready,input wire s_axis_tlast,
    output reg [31:0] m_axis_tdata,output reg [3:0] m_axis_tkeep,
    output reg m_axis_tvalid,input wire m_axis_tready,output reg m_axis_tlast,
    output reg fault, output wire idle
);
    localparam MAX_REQUEST=96+2*MAX_BYTES, WORDS=(MAX_REQUEST+3)/4;
    localparam SCRUB=0,READY_WAIT=1,RX=2,CHECK=3,LOAD=4,TAG=5,KICK=6,COMPUTE=7,
               HEADER=8,BUILD=9,SEND=10,LOAD_FETCH=11,TAG_FETCH=12,BUILD_FETCH=13;
    reg [3:0] state;
    (* ram_style="block" *) reg [31:0] packet [0:WORDS-1];
    reg [31:0] header_words[0:19];
    reg [31:0] packet_q;
    reg [15:0] rx_count, copy_pos, tag_pos, tx_pos, tx_length, scrub_word;
    reg bad_packet;
    reg [31:0] watchdog;
    reg [63:0] epoch_seen,last_id,req_epoch,req_id;
    reg [31:0] operation,mode,status;
    reg [15:0] ad_length,msg_length;
    reg [127:0] key,nonce,expected_tag;
    reg [383:0] response_header;
    reg [31:0] build_word;
    reg [1:0] lane;
    reg core_clear;
    wire core_ready,core_busy,core_done,core_success,core_length_error;
    wire [127:0] core_tag;
    wire [63:0] core_cycles;
    wire [7:0] core_byte;
    wire [15:0] load_offset=16'd80+copy_pos;
    wire [15:0] core_load_addr=copy_pos<ad_length ? copy_pos : copy_pos-ad_length;
    wire [7:0] core_load_data=packet_q>>(load_offset[1:0]*8);
    wire [15:0] tag_offset=16'd80+ad_length+msg_length+tag_pos;
    wire [15:0] result_offset=tx_pos-16'd48;
    wire [15:0] output_tag_offset=result_offset-msg_length;
    wire [7:0] tx_byte = tx_pos<48 ? (response_header>>(tx_pos*8)) :
        (result_offset<msg_length ? core_byte : (core_tag>>(output_tag_offset*8)));
    wire [31:0] assembled_word=build_word | ({24'b0,tx_byte}<<(lane*8));
    wire [2:0] valid_bytes = s_axis_tkeep==4'hf ? 4 : s_axis_tkeep==4'h7 ? 3 :
                            s_axis_tkeep==4'h3 ? 2 : s_axis_tkeep==4'h1 ? 1 : 0;
    assign s_axis_tready = state==RX && session_epoch!=0;
    assign idle = s_axis_tready && rx_count==0 && !bad_packet;
    wire packet_accept=state==RX && s_axis_tvalid && s_axis_tready &&
                       rx_count+valid_bytes<=MAX_REQUEST && !bad_packet && valid_bytes!=0;
    wire packet_we=rst_n && session_epoch==epoch_seen && (state==SCRUB || packet_accept);
    wire [$clog2(WORDS)-1:0] packet_wa=(state==SCRUB)?scrub_word:(rx_count>>2);
    wire [31:0] packet_wd=(state==SCRUB)?32'b0:s_axis_tdata;
    wire [$clog2(WORDS)-1:0] packet_ra=(state==TAG_FETCH||state==TAG)?(tag_offset>>2):(load_offset>>2);
    always @(posedge clk) begin
        packet_q<=packet[packet_ra];
        if(packet_we)packet[packet_wa]<=packet_wd;
        if(rst_n && session_epoch==epoch_seen) begin
            if(state==SCRUB)begin if(scrub_word<20)header_words[scrub_word]<=0;end
            else if(packet_accept && rx_count<80)header_words[rx_count>>2]<=s_axis_tdata;
        end
    end
    ascon_aead_multiblock #(.MAX_BYTES(MAX_BYTES)) core(
        .clk(clk),.rst_n(rst_n),.clear(core_clear),
        .load_valid(state==LOAD && copy_pos<ad_length+msg_length),
        .load_ad(copy_pos<ad_length),
        .load_addr(core_load_addr[AW-1:0]),.load_data(core_load_data),
        .start(state==KICK),.encrypt(operation==1),.adlen(ad_length),.mlen(msg_length),
        .key(key),.nonce(nonce),.tag_in(expected_tag),.ready(core_ready),.busy(core_busy),
        .done(core_done),.success(core_success),.length_error(core_length_error),
        .tag_out(core_tag),.cycles(core_cycles),.result_addr(result_offset[AW-1:0]),.result_data(core_byte)
    );
    always @(posedge clk) begin
        if(!rst_n) begin
            state<=SCRUB;scrub_word<=0;core_clear<=1;epoch_seen<=0;last_id<=0;
            rx_count<=0;bad_packet<=0;watchdog<=0;copy_pos<=0;tag_pos<=0;
            tx_pos<=0;tx_length<=0;lane<=0;build_word<=0;response_header<=0;
            req_epoch<=0;req_id<=0;operation<=0;mode<=0;status<=0;
            ad_length<=0;msg_length<=0;key<=0;nonce<=0;expected_tag<=0;
            m_axis_tvalid<=0;m_axis_tdata<=0;m_axis_tkeep<=0;m_axis_tlast<=0;fault<=0;
        end else if(session_epoch!=epoch_seen) begin
            epoch_seen<=session_epoch;last_id<=0;state<=SCRUB;scrub_word<=0;core_clear<=1;
            rx_count<=0;bad_packet<=0;watchdog<=0;m_axis_tvalid<=0;fault<=0;
            key<=0;nonce<=0;expected_tag<=0;response_header<=0;build_word<=0;
        end else begin
            core_clear<=0;
            case(state)
            SCRUB: begin
                if(scrub_word==WORDS-1) begin state<=READY_WAIT;rx_count<=0;bad_packet<=0;end
                else scrub_word<=scrub_word+1'b1;
            end
            READY_WAIT: if(core_ready) begin
                state<=RX;watchdog<=0;req_epoch<=0;req_id<=0;operation<=0;mode<=0;status<=0;
            end
            RX: begin
                if(rx_count!=0 || bad_packet) watchdog<=watchdog+1'b1;
                if((rx_count!=0 || bad_packet) && watchdog>=TIMEOUT_CYCLES-1) begin
                    status<=5;fault<=1;state<=HEADER;watchdog<=0;core_clear<=1;
                end else if(s_axis_tvalid && s_axis_tready) begin
                    if(valid_bytes==0 || (!s_axis_tlast && s_axis_tkeep!=4'hf) || rx_count+valid_bytes>MAX_REQUEST)
                        bad_packet<=1;
                    if(rx_count+valid_bytes<=MAX_REQUEST) rx_count<=rx_count+valid_bytes;
                    else bad_packet<=1;
                    if(s_axis_tlast) state<=CHECK;
                end
            end
            CHECK: begin
                req_epoch<={header_words[3],header_words[2]};req_id<={header_words[5],header_words[4]};
                operation<=header_words[6];mode<=header_words[7];
                if(bad_packet || rx_count<48) begin req_epoch<=0;req_id<=0;operation<=0;mode<=0;end
                ad_length<=header_words[8][15:0];msg_length<=header_words[9][15:0];
                state<=HEADER;status<=0;
                if(bad_packet || rx_count<48 || header_words[0]!=32'h51313044 || header_words[1]!=32'h00000002) status<=5;
                else if({header_words[3],header_words[2]}!=session_epoch || {header_words[5],header_words[4]}==0 || {header_words[5],header_words[4]}<=last_id) status<=6;
                else if(header_words[6]!=1 && header_words[6]!=2 || header_words[7]!=4) status<=3;
                else if(header_words[8]>MAX_BYTES || header_words[9]>MAX_BYTES || header_words[11]!=(header_words[6]==2?16:0) ||
                        header_words[10]<(header_words[9]+(header_words[6]==1?16:0))) status<=2;
                else if(rx_count!=80+header_words[8]+header_words[9]+header_words[11]) status<=5;
                else begin
                    last_id<={header_words[5],header_words[4]};key<={header_words[15],header_words[14],header_words[13],header_words[12]};
                    nonce<={header_words[19],header_words[18],header_words[17],header_words[16]};expected_tag<=0;
                    copy_pos<=0;tag_pos<=0;state<=LOAD_FETCH;
                end
            end
            LOAD_FETCH: state<=LOAD;
            LOAD: if(copy_pos<ad_length+msg_length) begin copy_pos<=copy_pos+1'b1;state<=LOAD_FETCH;end
                  else if(operation==2) state<=TAG_FETCH; else state<=KICK;
            TAG_FETCH: state<=TAG;
            TAG: begin
                expected_tag[tag_pos*8 +:8] <= packet_q>>(tag_offset[1:0]*8);
                if(tag_pos==15) state<=KICK;else begin tag_pos<=tag_pos+1'b1;state<=TAG_FETCH;end
            end
            KICK: begin state<=COMPUTE;watchdog<=0;end
            COMPUTE: begin
                if(core_done) begin status<=core_success?0:(core_length_error?2:1);state<=HEADER;end
                else if(watchdog==TIMEOUT_CYCLES-1) begin status<=4;fault<=1;core_clear<=1;state<=HEADER;end
                else watchdog<=watchdog+1'b1;
            end
            HEADER: begin
                response_header <= {status==0?core_cycles:64'b0,
                    status==0?({16'b0,msg_length}+(operation==1?32'd16:32'd0)):32'b0,
                    mode,operation,status,req_id,req_epoch, status==0?32'h00010002:32'h00000002,32'h52313044};
                tx_length<=status==0 ? 48+msg_length+(operation==1?16:0):48;
                tx_pos<=0;lane<=0;build_word<=0;state<=BUILD_FETCH;watchdog<=0;
            end
            BUILD_FETCH: state<=BUILD;
            BUILD: begin
                build_word<=assembled_word;tx_pos<=tx_pos+1'b1;
                if(lane==3 || tx_pos==tx_length-1) begin
                    m_axis_tdata<=assembled_word;m_axis_tkeep<=4'hf>>(3-lane);
                    m_axis_tlast<=tx_pos==tx_length-1;m_axis_tvalid<=1;state<=SEND;watchdog<=0;
                end else begin lane<=lane+1'b1;state<=BUILD_FETCH;end
            end
            SEND: begin
                if(m_axis_tvalid && m_axis_tready) begin
                    m_axis_tvalid<=0;lane<=0;build_word<=0;
                    if(m_axis_tlast) begin
                        state<=SCRUB;scrub_word<=0;core_clear<=1;key<=0;nonce<=0;expected_tag<=0;
                    end else state<=BUILD_FETCH;
                end else if(watchdog==TIMEOUT_CYCLES-1) fault<=1;
                else watchdog<=watchdog+1'b1;
            end
            default: begin state<=SCRUB;scrub_word<=0;core_clear<=1;m_axis_tvalid<=0;fault<=1;end
            endcase
        end
    end
endmodule

`timescale 1ns/1ps
// Independent, single-cycle register peripheral. No AXI channel assumptions.
module puf_mmio_v2 #(
    parameter DIAGNOSTIC=0, CW=20, WINDOW=1024, RO_DEADLINE=8192,
    parameter CORE_DEADLINE=65536, SAMPLES=3, MIN_BITS=64,
    parameter [56:0] SIM_DNA=57'h1234, parameter SHIFT_SKIP=1
)(
    input wire clk, ro_clk, rst_n, input wire [255:0] osc,
    input wire valid, write, input wire [7:0] addr,
    input wire [31:0] wdata, input wire [3:0] wstrb,
    output wire ready, output reg [31:0] rdata, output reg bus_error,
    output wire irq, output wire image_ready, output wire [127:0] image_data
);
    reg dna_start, dna_started, dna_ready, dna_failed;
    reg [8:0] dna_timer;
    wire dna_valid;
    wire [56:0] dna_wire;
    reg [56:0] dna;
    device_dna #(.SIM_DNA(SIM_DNA),.SHIFT_SKIP(SHIFT_SKIP)) dna_reader(
        .clk(clk),.rst_n(rst_n),.start(dna_start),.dna(dna_wire),.valid(dna_valid));
    reg key_start, key_enroll, helper_load, clear;
    wire [127:0] internal_key, exported_ref, exported_mask;
    reg [127:0] helper_ref, helper_mask;
    reg [31:0] helper_written;
    wire kv,kbusy,kdone,enrolled;
    wire [7:0] ke,quality,sample_error;
    puf_key_v2 #(.CW(CW),.WINDOW(WINDOW),.RO_DEADLINE(RO_DEADLINE),
        .CORE_DEADLINE(CORE_DEADLINE),.SAMPLES(SAMPLES),.MIN_BITS(MIN_BITS)) keys(
        .clk(clk),.ro_clk(ro_clk),.rst_n(rst_n),.clear(clear),.start(key_start),.enroll(key_enroll),
        .osc(osc),.board_dna(dna),.helper_load(helper_load),.helper_ref_in(helper_ref),
        .helper_mask_in(helper_mask),.helper_ref(exported_ref),.helper_mask(exported_mask),
        .key(internal_key),.key_valid(kv),.busy(kbusy),.done(kdone),.enrolled(enrolled),
        .error_code(ke),.quality(quality),.sample_error(sample_error),.transaction_id());
    reg [127:0] input_data, ad, nonce, input_tag, output_data, output_tag;
    reg [7:0] data_length, ad_length;
    reg [31:0] image_version, image_target, expected_version, expected_target;
    reg [31:0] transaction_id, cipher_timer;
    reg [7:0] result_error, bus_fault;
    reg busy, done, success, image_ok, cipher_start, cipher_mode;
    reg [1:0] operation; // 1 key, 2 cipher, 3 image authentication
    wire cd,ce,correct;
    wire [127:0] cipher_data,cipher_tag;
    wire key_ready=kv && !clear && !key_start && !helper_load;
    wire [127:0] cipher_ad=(operation==3)?{32'h32474d49,image_target,24'b0,data_length,image_version}:ad;
    crypto_aead cipher(.clk(clk),.rst_n(rst_n && busy && operation>=2 && key_ready),
        .start(cipher_start),.mode(cipher_mode),.data_in(input_data),.ad(cipher_ad),
        .npub(nonce),.k(internal_key),.adlen((operation==3)?5'd16:ad_length[4:0]),
        .datalen(data_length[4:0]),.tag_in(input_tag),.data_out(cipher_data),.tag(cipher_tag),
        .correct(correct),.done(cd),.busy(),.error(ce));
    assign ready=1'b1;
    assign irq=done;
    assign image_ready=image_ok && key_ready;
    assign image_data=image_ready?output_data:128'b0;
    wire control=valid && write && addr==8'h04 && wstrb[0];
    wire writable=(addr==8'h04 || addr==8'h20 ||
        (addr>=8'h30 && addr<=8'h8c) || (addr>=8'ha0 && addr<=8'hac));
    always @* begin
        bus_error=0; rdata=0;
        if(valid) begin
            if(addr[1:0]!=0) bus_error=1;
            else if(write) begin
                if(!writable && |wstrb) bus_error=1;
                else if(busy && |wstrb && !(control && wdata[7:0]==7)) bus_error=1;
                else if(control && (wdata[7:0]<1 || wdata[7:0]>7)) bus_error=1;
                else if(control && wdata[7:0]<=2 && !dna_ready) bus_error=1;
            end else case(addr)
                8'h00:rdata=32'h50550202; // magic PU, ABI 2, revision 2
                8'h08:rdata={23'b0,dna_failed,enrolled,image_ready,(DIAGNOSTIC!=0),dna_ready,success,done,key_ready,busy};
                8'h0c:rdata={16'b0,sample_error,result_error};
                8'h10:rdata=transaction_id;
                8'h14:rdata=DIAGNOSTIC?dna[31:0]:0;
                8'h18:rdata=DIAGNOSTIC?{7'b0,dna[56:32]}:0;
                8'h1c:rdata={24'b0,bus_fault};
                8'h20:rdata={16'b0,ad_length,data_length};
                8'ha0:rdata=image_version;
                8'ha4:rdata=image_target;
                8'ha8:rdata=expected_version;
                8'hac:rdata=expected_target;
                default: begin
                    if(addr>=8'h30 && addr<=8'h3c) rdata=input_data[(addr-8'h30)*8+:32];
                    else if(addr>=8'h40 && addr<=8'h4c) rdata=ad[(addr-8'h40)*8+:32];
                    else if(addr>=8'h50 && addr<=8'h5c) rdata=nonce[(addr-8'h50)*8+:32];
                    else if(addr>=8'h60 && addr<=8'h6c) rdata=input_tag[(addr-8'h60)*8+:32];
                    else if(addr>=8'h70 && addr<=8'h7c) rdata=DIAGNOSTIC?helper_ref[(addr-8'h70)*8+:32]:0;
                    else if(addr>=8'h80 && addr<=8'h8c) rdata=DIAGNOSTIC?helper_mask[(addr-8'h80)*8+:32]:0;
                    else if(addr>=8'hb0 && addr<=8'hbc) rdata=output_data[(addr-8'hb0)*8+:32];
                    else if(addr>=8'hc0 && addr<=8'hcc) rdata=output_tag[(addr-8'hc0)*8+:32];
                    else if(addr>=8'hd0 && addr<=8'hdc) rdata=DIAGNOSTIC?exported_ref[(addr-8'hd0)*8+:32]:0;
                    else if(addr>=8'he0 && addr<=8'hec) rdata=DIAGNOSTIC?exported_mask[(addr-8'he0)*8+:32]:0;
                    else if(addr==8'hf0) rdata={24'b0,quality};
                    else bus_error=1;
                end
            endcase
        end
    end
    integer b;
    always @(posedge clk) begin
        if(!rst_n) begin
            dna_start<=0; dna_started<=0; dna_ready<=0; dna_failed<=0; dna_timer<=0; dna<=0;
            key_start<=0; key_enroll<=0; helper_load<=0; clear<=0; helper_ref<=0; helper_mask<=0;
            helper_written<=0;
            input_data<=0; ad<=0; nonce<=0; input_tag<=0; output_data<=0; output_tag<=0;
            data_length<=0; ad_length<=0; image_version<=0; image_target<=0;
            expected_version<=0; expected_target<=0; transaction_id<=0; cipher_timer<=0;
            result_error<=0; bus_fault<=0; busy<=0; done<=0; success<=0; image_ok<=0;
            cipher_start<=0; cipher_mode<=0; operation<=0;
        end else begin
            dna_start<=0; key_start<=0; helper_load<=0; clear<=0; cipher_start<=0;
            if(!dna_started) begin dna_start<=1; dna_started<=1; end
            if(dna_started && !dna_ready && !dna_failed) begin
                dna_timer<=dna_timer+1;
                if(dna_valid) begin dna<=dna_wire; dna_ready<=1; end
                else if(dna_timer==255) dna_failed<=1;
            end
            if(valid && bus_error) bus_fault<=1;
            if(busy) begin
                if(operation==1 && kdone) begin
                    busy<=0; done<=1; result_error<=ke; success<=(ke==0);
                end else if(operation>=2) begin
                    cipher_timer<=cipher_timer+1;
                    if(!key_ready || cipher_timer>=512) begin
                        busy<=0; done<=1; result_error<=8'h91; success<=0; image_ok<=0;
                        output_data<=0; output_tag<=0;
                    end else if(cd) begin
                        busy<=0; done<=1;
                        if(ce || (cipher_mode && !correct)) begin
                            result_error<=8'h92; success<=0; output_data<=0; output_tag<=0; image_ok<=0;
                        end else begin
                            success<=1; result_error<=0; output_tag<=cipher_tag; image_ok<=(operation==3);
                            for(b=0;b<16;b=b+1) output_data[b*8+:8]<=(b<data_length)?cipher_data[b*8+:8]:0;
                        end
                    end
                end
            end
            if(valid && write && !bus_error) begin
                // Any accepted payload/metadata mutation revokes the previously
                // authenticated image/result before a consumer can reuse it.
                if(!control && writable && |wstrb && addr!=8'h04) begin
                    image_ok<=0; success<=0; output_data<=0; output_tag<=0;
                end
                if(control) begin
                    transaction_id<=transaction_id+1; done<=0; success<=0; result_error<=0; bus_fault<=0;
                    output_data<=0; output_tag<=0; image_ok<=0;
                    case(wdata[7:0])
                        1,2: begin key_start<=1; key_enroll<=(wdata[7:0]==1); operation<=1; busy<=1; end
                        3: begin
                            helper_written<=0;
                            if(&helper_written) begin helper_load<=1; operation<=1; busy<=1; end
                            else begin clear<=1; busy<=0; done<=1; result_error<=8'h94; end
                        end
                        4,5,6: begin
                            if(!key_ready || data_length>16 || ad_length>16 ||
                               (wdata[7:0]==6 && (data_length==0 || image_version!=expected_version || image_target!=expected_target))) begin
                                done<=1; busy<=0; result_error<=8'h93;
                            end else begin
                                operation<=(wdata[7:0]==6)?3:2; cipher_start<=1; busy<=1;
                                cipher_mode<=(wdata[7:0]!=4); cipher_timer<=0;
                            end
                        end
                        7: begin clear<=1; busy<=0; done<=1; success<=1; operation<=0;
                            input_data<=0; ad<=0; nonce<=0; input_tag<=0; helper_ref<=0; helper_mask<=0;
                            helper_written<=0;
                        end
                    endcase
                end else for(b=0;b<4;b=b+1) if(wstrb[b]) begin
                    if(addr==8'h20) begin
                        if(b==0) data_length<=wdata[7:0];
                        if(b==1) ad_length<=wdata[15:8];
                    end else if(addr>=8'h30 && addr<=8'h3c) input_data[(addr-8'h30)*8+b*8+:8]<=wdata[b*8+:8];
                    else if(addr>=8'h40 && addr<=8'h4c) ad[(addr-8'h40)*8+b*8+:8]<=wdata[b*8+:8];
                    else if(addr>=8'h50 && addr<=8'h5c) nonce[(addr-8'h50)*8+b*8+:8]<=wdata[b*8+:8];
                    else if(addr>=8'h60 && addr<=8'h6c) input_tag[(addr-8'h60)*8+b*8+:8]<=wdata[b*8+:8];
                    else if(addr>=8'h70 && addr<=8'h7c) begin
                        helper_ref[(addr-8'h70)*8+b*8+:8]<=wdata[b*8+:8]; helper_written[addr-8'h70+b]<=1;
                    end else if(addr>=8'h80 && addr<=8'h8c) begin
                        helper_mask[(addr-8'h80)*8+b*8+:8]<=wdata[b*8+:8]; helper_written[addr-8'h70+b]<=1;
                    end
                    else if(addr==8'ha0) image_version[b*8+:8]<=wdata[b*8+:8];
                    else if(addr==8'ha4) image_target[b*8+:8]<=wdata[b*8+:8];
                    else if(addr==8'ha8) expected_version[b*8+:8]<=wdata[b*8+:8];
                    else if(addr==8'hac) expected_target[b*8+:8]<=wdata[b*8+:8];
                end
            end
        end
    end
endmodule

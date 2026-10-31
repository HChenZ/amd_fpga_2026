`timescale 1ns/1ps
// Functional diagnostic derivation, NOT a standard KDF or secure sketch.
module puf_key_v2 #(
    parameter CW=20, WINDOW=1024, RO_DEADLINE=8192, CORE_DEADLINE=65536,
    parameter SAMPLES=3, MIN_BITS=64
)(
    input wire clk, ro_clk, rst_n, clear, start, enroll,
    input wire [255:0] osc,
    input wire [56:0] board_dna,
    input wire helper_load,
    input wire [127:0] helper_ref_in, helper_mask_in,
    output wire [127:0] helper_ref, helper_mask,
    output reg [127:0] key,
    output reg key_valid, busy, done, enrolled,
    output reg [7:0] error_code, quality,
    output wire [7:0] sample_error,
    output reg [31:0] transaction_id
);
    wire local_rst_n=rst_n && !clear;
    reg sample_start, kdf_start;
    wire sample_done, sample_valid, sample_busy, sample_locked;
    wire [127:0] raw;
    wire [31:0] sample_id;
    ro_puf_core_v2 #(.CW(CW),.WINDOW(WINDOW),.RO_DEADLINE(RO_DEADLINE),
        .CORE_DEADLINE(CORE_DEADLINE)) sampler(
        .clk(clk),.ro_clk(ro_clk),.rst_n(local_rst_n),.start(sample_start),.osc(osc),
        .raw(raw),.valid(sample_valid),.done(sample_done),.busy(sample_busy),
        .error_code(sample_error),.locked(sample_locked),.transaction_id(sample_id),
        .diagnostic_counts());
    reg [127:0] reference, mask, first, stable_mask, material;
    reg [56:0] dna_latched;
    reg mode;
    reg [2:0] state;
    reg [31:0] sample_number, timer;
    wire [319:0] derived;
    wire derived_done;
    // Fixed-length experimental P12 mapping; no security-strength claim.
    p12 derive(.clk(clk),.rst_n(local_rst_n && busy),.start(kdf_start),
        .s_in({64'h5055465f56325f44,64'h4941474e4f535449,material,7'b0,dna_latched}),
        .s_out(derived),.done(derived_done),.busy());
    assign helper_ref=reference;
    assign helper_mask=mask;
    integer pc,j;
    reg [127:0] selected_mask;
    always @* begin
        selected_mask=mode?stable_mask:mask; pc=0;
        for(integer b=0;b<128;b=b+1) pc=pc+selected_mask[b];
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            key<=0; key_valid<=0; busy<=0; done<=0; enrolled<=0;
            reference<=0; mask<=0; first<=0; stable_mask<=0; material<=0;
            dna_latched<=0; mode<=0; state<=0; sample_start<=0; kdf_start<=0;
            error_code<=0; quality<=0; sample_number<=0; timer<=0; transaction_id<=0;
        end else begin
            done<=0; sample_start<=0; kdf_start<=0;
            if(clear) begin
                key<=0; key_valid<=0; busy<=0; state<=0; error_code<=0;
                first<=0; stable_mask<=0; material<=0; dna_latched<=0; quality<=0;
            end else if(start || helper_load) begin
                key<=0; key_valid<=0; quality<=0; material<=0;
                first<=0; stable_mask<=0; dna_latched<=0;
                transaction_id<=transaction_id+1;
                if(busy || (start && helper_load)) begin
                    busy<=0; state<=0; done<=1; error_code<=8'h81;
                end else if(helper_load) begin
                    reference<=helper_ref_in; mask<=helper_mask_in;
                    enrolled<=(helper_mask_in!=0); done<=1;
                    error_code<=(helper_mask_in==0)?8'h84:0;
                end else if(!enroll && !enrolled) begin
                    done<=1; error_code<=8'h82;
                end else if(sample_locked || sample_busy) begin
                    done<=1; error_code<=8'h83;
                end else begin
                    busy<=1; mode<=enroll; dna_latched<=board_dna; timer<=0;
                    error_code<=0; sample_number<=0; stable_mask<={128{1'b1}};
                    first<=0; sample_start<=1; state<=1;
                    if(enroll) begin enrolled<=0; reference<=0; mask<=0; end
                end
            end else if(busy) begin
                timer<=timer+1;
                if(timer >= (CORE_DEADLINE+32)*SAMPLES+128) begin
                    key<=0; key_valid<=0; material<=0; busy<=0; done<=1; state<=0; error_code<=8'h85;
                end else case(state)
                    1: if(sample_done) begin
                        if(!sample_valid || sample_error!=0) begin
                            busy<=0; done<=1; state<=0; error_code<=8'h83; first<=0; stable_mask<=0;
                        end else begin
                            if(sample_number==0) first<=raw;
                            else stable_mask<=stable_mask & ~(first^raw);
                            if(sample_number==SAMPLES-1) state<=2;
                            else begin sample_number<=sample_number+1; sample_start<=1; end
                        end
                    end
                    2: begin
                        quality<=pc;
                        if(pc<MIN_BITS || (!mode && ((mask & ~stable_mask)!=0 || ((first^reference)&mask)!=0))) begin
                            busy<=0; done<=1; state<=0; error_code<=8'h84;
                            first<=0; stable_mask<=0;
                        end else begin
                            if(mode) begin reference<=first; mask<=stable_mask; enrolled<=1; end
                            material<=first & selected_mask; state<=3;
                        end
                    end
                    3: begin kdf_start<=1; state<=4; end
                    4: if(derived_done) begin
                        key<=derived[127:0]; key_valid<=1; busy<=0; done<=1;
                        material<=0; first<=0; stable_mask<=0; state<=0;
                    end
                    default: begin busy<=0; done<=1; key<=0; key_valid<=0; error_code<=8'h85; end
                endcase
            end
        end
    end
endmodule

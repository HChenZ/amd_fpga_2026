`timescale 1ns/1ps
// Diagnostic sampling engine: external oscillator clocks, no simulated entropy.
// Error bits: 0 RO watchdog, 1 core deadline, 2 zero count, 3 tie,
// 4 saturation, 5 all comparisons same direction, 6 overlapping request.
module ro_puf_core_v2 #(
    parameter BITS=128, CW=20, WINDOW=1024,
    parameter RO_DEADLINE=8192, CORE_DEADLINE=65536
)(
    input wire clk, ro_clk, rst_n, start,
    input wire [2*BITS-1:0] osc,
    output reg [BITS-1:0] raw,
    output reg valid, done, busy,
    output reg [7:0] error_code,
    output reg locked,
    output reg [31:0] transaction_id,
    output wire [2*BITS*CW-1:0] diagnostic_counts
);
    reg request, complete;
    (* ASYNC_REG="TRUE" *) reg [1:0] ro_reset_release;
    wire ro_rst_n=ro_reset_release[1];
    always @(posedge ro_clk or negedge rst_n)
        if(!rst_n) ro_reset_release<=0;
        else ro_reset_release<={ro_reset_release[0],1'b1};
    (* ASYNC_REG="TRUE" *) reg [2:0] rq, cp;
    reg rq_seen, cp_seen;
    reg [1:0] phase;
    wire [2*BITS-1:0] stopped, cleared;
    wire [2*BITS*CW-1:0] counts;
    wire [2*BITS-1:0] over;
    genvar g;
    generate for(g=0;g<2*BITS;g=g+1) begin: counters
        wire [1:0] ack;
        (* ASYNC_REG="TRUE" *) reg [1:0] a0,a1;
        ro_counter_v2 #(.CW(CW)) u_counter(osc[g],rst_n,phase,ack,
            counts[g*CW+:CW],over[g]);
        always @(posedge ro_clk or negedge ro_rst_n)
            if(!ro_rst_n) begin a0<=2; a1<=2; end
            else begin a0<=ack; a1<=a0; end
        assign stopped[g]=(a1==3);
        assign cleared[g]=(a1==0);
    end endgenerate
    reg [2:0] state;
    reg [31:0] timer, window_count, core_timer;
    reg [BITS-1:0] result;
    reg [7:0] sample_error;
    // Bundled-data CDC: copy the held management-domain payload on the fully
    // synchronized completion event. Decode ONLY these core-domain registers
    // on the following cycle; never decode sample_error in the CDC input cone.
    reg capture_pending;
    reg [BITS-1:0] captured_result;
    reg [7:0] captured_error;
    reg [2*BITS*CW-1:0] snapshot;
    reg [2*BITS-1:0] overflow_snapshot;
    reg [BITS-1:0] comparison;
    reg [7:0] health;
    integer i;
    assign diagnostic_counts=snapshot;
    always @* begin
        comparison=0; health=0;
        for(integer j=0;j<BITS;j=j+1) begin
            comparison[j]=snapshot[j*CW+:CW]>snapshot[(j+BITS)*CW+:CW];
            if(snapshot[j*CW+:CW]==0 || snapshot[(j+BITS)*CW+:CW]==0) health[2]=1;
            if(snapshot[j*CW+:CW]==snapshot[(j+BITS)*CW+:CW]) health[3]=1;
            if((&snapshot[j*CW+:CW]) || (&snapshot[(j+BITS)*CW+:CW])) health[4]=1;
        end
        health[4]=health[4] | (|overflow_snapshot);
        health[5]=(&comparison)||(~|comparison);
    end
    always @(posedge ro_clk or negedge ro_rst_n) begin
        if(!ro_rst_n) begin
            rq<=0; rq_seen<=0; complete<=0; phase<=2; state<=0;
            timer<=0; window_count<=0; result<=0; sample_error<=0;
            snapshot<=0; overflow_snapshot<=0;
        end else begin
            rq<={rq[1:0],request}; rq_seen<=rq[2];
            if(state!=0) timer<=timer+1;
            if(state!=0 && timer>=RO_DEADLINE) begin
                result<=0; sample_error<=1; complete<=~complete; state<=0; phase<=2;
            end else case(state)
                0: if(rq[2]!=rq_seen) begin
                    timer<=0; result<=0; sample_error<=0; snapshot<=0;
                    phase<=0; state<=1;
                end
                1: if(&cleared) begin phase<=1; window_count<=0; state<=2; end
                2: if(window_count==WINDOW-1) begin phase<=3; state<=3; end
                   else window_count<=window_count+1;
                3: if(&stopped) state<=4;
                4: begin snapshot<=counts; overflow_snapshot<=over; state<=5; end
                5: begin
                    result<=(health==0)?comparison:0; sample_error<=health;
                    complete<=~complete; state<=0; phase<=2;
                end
                default: begin state<=0; phase<=2; end
            endcase
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            request<=0; cp<=0; cp_seen<=0; raw<=0; valid<=0; done<=0;
            busy<=0; error_code<=0; locked<=0; core_timer<=0; transaction_id<=0;
            capture_pending<=0; captured_result<=0; captured_error<=0;
        end else begin
            cp<={cp[1:0],complete}; cp_seen<=cp[2]; done<=0; valid<=0;
            if(start) begin
                raw<=0; transaction_id<=transaction_id+1;
                capture_pending<=0; captured_result<=0; captured_error<=0;
                if(busy || locked) begin
                    busy<=0; done<=1; error_code<=8'h40; locked<=1;
                end else begin
                    busy<=1; error_code<=0; core_timer<=0; request<=~request;
                end
            end else if(busy) begin
                core_timer<=core_timer+1;
                if(core_timer>=CORE_DEADLINE) begin
                    raw<=0; busy<=0; done<=1; error_code<=2; locked<=1;
                    capture_pending<=0; captured_result<=0; captured_error<=0;
                end else if(capture_pending) begin
                    busy<=0; done<=1; error_code<=captured_error;
                    raw<=(captured_error==0)?captured_result:0; valid<=(captured_error==0);
                    if(captured_error!=0) locked<=1;
                    capture_pending<=0; captured_result<=0; captured_error<=0;
                end else if(cp[2]!=cp_seen) begin
                    captured_result<=result; captured_error<=sample_error;
                    capture_pending<=1;
                end
            end
        end
    end
endmodule

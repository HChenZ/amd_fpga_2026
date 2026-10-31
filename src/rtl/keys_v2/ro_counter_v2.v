`timescale 1ns/1ps
// Four-phase bundled-data protocol. Count is stable before stop acknowledgement.
module ro_counter_v2 #(parameter CW=20)(
    input wire osc, rst_n, input wire [1:0] phase,
    output reg [1:0] ack, output reg [CW-1:0] count,
    output reg overflow
);
    (* ASYNC_REG="TRUE" *) reg [1:0] p0, p1;
    (* ASYNC_REG="TRUE" *) reg [1:0] reset_release;
    wire osc_rst_n=reset_release[1];
    always @(posedge osc or negedge rst_n)
        if(!rst_n) reset_release<=0;
        else reset_release<={reset_release[0],1'b1};
    always @(posedge osc or negedge osc_rst_n) begin
        if (!osc_rst_n) begin p0<=0; p1<=0; ack<=0; count<=0; overflow<=0; end
        else begin
            p0<=phase; p1<=p0;
            case (p1)
                0: begin count<=0; overflow<=0; ack<=0; end
                1: begin
                    ack<=1;
                    if (&count) overflow<=1;
                    else count<=count+1'b1;
                end
                3: ack<=3;
                default: ack<=2;
            endcase
        end
    end
endmodule

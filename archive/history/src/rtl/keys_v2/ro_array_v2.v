`timescale 1ns/1ps
// Independent physical ring bank. Requires reviewed loop/CDC/placement constraints.
module ro_array_v2 #(parameter N=256, STAGES=5)(
    input wire en, output wire [N-1:0] osc
);
    genvar i,j;
    generate for(i=0;i<N;i=i+1) begin: rings
        (* KEEP="TRUE" *) wire [STAGES-1:0] n;
        (* DONT_TOUCH="TRUE" *) LUT2 #(.INIT(4'b0111)) gate0
            (.I0(en),.I1(n[STAGES-1]),.O(n[0]));
        for(j=1;j<STAGES;j=j+1) begin: stages
            (* DONT_TOUCH="TRUE" *) LUT1 #(.INIT(2'b01)) inv0(.I0(n[j-1]),.O(n[j]));
        end
        assign osc[i]=n[STAGES-1];
    end endgenerate
endmodule

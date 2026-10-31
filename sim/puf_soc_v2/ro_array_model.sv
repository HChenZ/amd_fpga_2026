`timescale 1ns/1ps
// SIMULATION ONLY. Deterministic differential clocks are NOT physical PUF evidence.
// Replaces only the physical LUT ring bank; all digital/default sampler parameters
// and the actual puf_mmio_physical_v2 instance remain unchanged.
module ro_array_v2 #(parameter N=256, STAGES=5)(input wire en, output wire [N-1:0] osc);
    genvar g;
    generate for(g=0;g<N;g=g+1) begin: models
        reg q=0;
        localparam P=(g<128)?((g%2)?4:2):((g%2)?2:4);
        always #(P) q=~q;
        assign osc[g]=en?q:1'b0;
    end endgenerate
endmodule

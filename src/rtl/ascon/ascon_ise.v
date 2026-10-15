`timescale 1ns / 1ps
// =============================================================================
// ascon_ise.v — Ascon permutation ISE (custom instruction) coprocessor.
//
// Holds a dedicated 320-bit Ascon state register inside the CPU execute unit
// and exposes it to the pipeline via four custom-0 (opcode 0x0B) instructions:
//   ascon.w   (funct3=000): state[32*rs2[3:0] +: 32] = rs1     (1 cycle)
//   ascon.rd  (funct3=001): rd = state[32*rs1[3:0] +: 32]      (1 cycle)
//   ascon.p12 (funct3=010): state = P12(state)                 (multi-cycle)
//   ascon.p8  (funct3=011): state = P8(state)                  (multi-cycle)
//
// Word index is 0..9 (10 x 32-bit = 320-bit state). The permutation reuses the
// KAT-verified p12/p8 modules from ascon_permutation.v. perm_start is a LEVEL
// (asserted while the instruction is in EX and not done); the internal FSM
// pulses the p12/p8 start once and latches the result on done.
// =============================================================================
module ascon_ise (
    input  wire         clk,
    input  wire         rst_n,

    // state word write (ascon.w)
    input  wire         wr_en,
    input  wire [3:0]   wr_idx,
    input  wire [31:0]  wr_data,

    // state word read (ascon.rd)
    input  wire [3:0]   rd_idx,
    output wire [31:0]  rd_data,

    // permutation (ascon.p12 / ascon.p8)
    input  wire         perm_start,   // level
    input  wire         perm_p12,     // 1 = P12, 0 = P8
    output reg          perm_done
);

    reg [319:0] state;
    reg         perm_run;
    reg         p_start;

    wire [319:0] p12_out, p8_out;
    wire         p12_done, p8_done;
    wire [319:0] p_out  = perm_p12 ? p12_out : p8_out;
    wire         p_done = perm_p12 ? p12_done : p8_done;

    p12 u_p12 (
        .clk(clk), .rst_n(rst_n),
        .start(p_start & perm_p12),
        .s_in(state), .s_out(p12_out), .done(p12_done), .busy()
    );
    p8 u_p8 (
        .clk(clk), .rst_n(rst_n),
        .start(p_start & ~perm_p12),
        .s_in(state), .s_out(p8_out), .done(p8_done), .busy()
    );

    assign rd_data = state[32*rd_idx +: 32];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= 320'd0;
            perm_run  <= 1'b0;
            p_start   <= 1'b0;
            perm_done <= 1'b0;
        end else begin
            p_start   <= 1'b0;
            perm_done <= 1'b0;

            if (wr_en)
                state[32*wr_idx +: 32] <= wr_data;

            if (perm_start && !perm_run) begin
                p_start  <= 1'b1;
                perm_run <= 1'b1;
            end else if (perm_run && p_done) begin
                state     <= p_out;
                perm_done <= 1'b1;
                perm_run  <= 1'b0;
            end
        end
    end

endmodule

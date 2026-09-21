`timescale 1ns / 1ps
//============================================================================
// SVA Property Module: icache_props
// Description:
//   Safety properties for the instruction cache:
//   - miss/redirect/fence request gating
//   - fill FSM/count behavior
//   - NOP output while no delayed hit is available
//   - fence invalidates valid bits except for a simultaneous last fill beat
//============================================================================
module icache_props #(
    parameter XLEN = 32,
    parameter ICACHE_SET_SIZE = 64
) (
    input                         clk,
    input                         rst_n,
    input      [XLEN-1:0]         cpu_addr_i,
    input      [31:0]             cpu_inst_o,
    input                         cpu_stall_o,
    input      [XLEN-1:0]         mem_addr_o,
    input                         mem_rdata_valid,
    input                         icache_miss,
    input                         redirect_i,
    input                         fence_i_flush,

    input                         state,
    input                         hit,
    input                         hit_r,
    input                         fetch_miss,
    input                         fill_active,
    input      [2:0]              fill_cnt,
    input      [ICACHE_SET_SIZE-1:0] valid_way0,
    input      [ICACHE_SET_SIZE-1:0] valid_way1
);

    localparam IDLE = 1'b0;
    localparam FILL = 1'b1;

    prop_legal_state: assert property (
        @(posedge clk) disable iff (!rst_n)
        (state == IDLE) || (state == FILL)
    ) else $error("icache entered an illegal FSM state");

    prop_miss_definition: assert property (
        @(posedge clk) disable iff (!rst_n)
        icache_miss == fetch_miss
    ) else $error("icache_miss does not match fetch_miss");

    prop_miss_gated_by_redirect_flush: assert property (
        @(posedge clk) disable iff (!rst_n)
        (redirect_i || fence_i_flush) |-> !icache_miss
    ) else $error("icache issued a miss while redirect/fence flush was active");

    prop_mem_addr_tracks_cpu_addr: assert property (
        @(posedge clk) disable iff (!rst_n)
        mem_addr_o == cpu_addr_i
    ) else $error("icache memory address does not track CPU address");

    prop_nop_without_delayed_hit: assert property (
        @(posedge clk) disable iff (!rst_n)
        !hit_r |-> (cpu_inst_o == 32'h0000_0013)
    ) else $error("icache did not output NOP while delayed hit was invalid");

    prop_stall_expr: assert property (
        @(posedge clk) disable iff (!rst_n)
        cpu_stall_o == !(hit && hit_r)
    ) else $error("icache stall output does not match hit/hit_r expression");

    prop_idle_clears_fill_count: assert property (
        @(posedge clk) disable iff (!rst_n)
        (state == IDLE) |=> (fill_cnt == 3'd0)
    ) else $error("icache fill counter did not clear in IDLE");

    prop_fill_count_increments: assert property (
        @(posedge clk) disable iff (!rst_n)
        (state == FILL && mem_rdata_valid && fill_cnt < 3'd3) |=>
        (fill_cnt == $past(fill_cnt) + 3'd1)
    ) else $error("icache fill counter did not increment on valid fill beat");

    prop_fence_clears_valids: assert property (
        @(posedge clk) disable iff (!rst_n)
        (fence_i_flush && !(fill_active && fill_cnt == 3'd3)) |=>
        (valid_way0 == {ICACHE_SET_SIZE{1'b0}} &&
         valid_way1 == {ICACHE_SET_SIZE{1'b0}})
    ) else $error("icache fence flush did not invalidate both ways");

    cov_icache_miss: cover property (@(posedge clk) icache_miss);
    cov_icache_fill_done: cover property (
        @(posedge clk) state == FILL && mem_rdata_valid && fill_cnt == 3'd3);
    cov_icache_fence: cover property (@(posedge clk) fence_i_flush);
    cov_icache_hit_ready: cover property (@(posedge clk) hit && hit_r && !cpu_stall_o);

endmodule

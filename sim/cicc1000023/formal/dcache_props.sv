`timescale 1ns / 1ps
//============================================================================
// SVA Property Module: dcache_props
// Description:
//   Safety properties for the data cache:
//   - cacheable memory vs MMIO routing
//   - request suppression while upstream pipeline is stalled
//   - fill FSM/count behavior
//   - write-through bus capture and store-miss flagging
//============================================================================
module dcache_props #(
    parameter XLEN = 32,
    parameter DCACHE_SET_SIZE = 64
) (
    input                         clk,
    input                         rst_n,
    input      [XLEN-1:0]         cpu_addr_i,
    input      [XLEN-1:0]         cpu_wdata_i,
    input      [XLEN/8-1:0]       cpu_wmask_i,
    input                         cpu_re_i,
    input                         cpu_we_i,
    input                         cpu_req_stall_i,
    input                         cpu_stall_o,
    input      [XLEN-1:0]         bus_addr_o,
    input                         bus_mem_re_o,
    input                         bus_mem_we_o,
    input                         bus_mmio_re_o,
    input                         bus_mmio_we_o,
    input      [XLEN/8-1:0]       bus_wmask_o,
    input      [XLEN-1:0]         bus_wdata_o,
    input                         bus_load_miss_o,
    input                         bus_store_miss_o,
    input                         bus_rdata_valid_i,

    input      [1:0]              state,
    input                         hit,
    input                         cacheable,
    input                         load_miss_now,
    input                         store_now,
    input                         mmio_read_now,
    input                         mmio_write_now,
    input                         fill_we,
    input      [2:0]              fill_cnt
);

    localparam IDLE = 2'd0;
    localparam FILL = 2'd1;

    asm_single_cpu_request: assume property (
        @(posedge clk) disable iff (!rst_n)
        !(cpu_re_i && cpu_we_i)
    );

    prop_legal_state: assert property (
        @(posedge clk) disable iff (!rst_n)
        (state == IDLE) || (state == FILL)
    ) else $error("dcache entered an illegal FSM state");

    prop_no_request_when_pipeline_stalled: assert property (
        @(posedge clk) disable iff (!rst_n)
        cpu_req_stall_i |-> !(load_miss_now || store_now || mmio_read_now || mmio_write_now)
    ) else $error("dcache accepted a new CPU request while cpu_req_stall_i was high");

    prop_load_miss_definition: assert property (
        @(posedge clk) disable iff (!rst_n)
        load_miss_now == ((state == IDLE) && !cpu_req_stall_i && cpu_re_i && cacheable && !hit)
    ) else $error("dcache load_miss_now definition mismatch");

    prop_store_now_definition: assert property (
        @(posedge clk) disable iff (!rst_n)
        store_now == ((state == IDLE) && !cpu_req_stall_i && cpu_we_i && cacheable)
    ) else $error("dcache store_now definition mismatch");

    prop_mmio_read_definition: assert property (
        @(posedge clk) disable iff (!rst_n)
        mmio_read_now == ((state == IDLE) && !cpu_req_stall_i && cpu_re_i && !cacheable)
    ) else $error("dcache mmio_read_now definition mismatch");

    prop_mmio_write_definition: assert property (
        @(posedge clk) disable iff (!rst_n)
        mmio_write_now == ((state == IDLE) && !cpu_req_stall_i && cpu_we_i && !cacheable)
    ) else $error("dcache mmio_write_now definition mismatch");

    prop_bus_capture_next_cycle: assert property (
        @(posedge clk) disable iff (!rst_n)
        (load_miss_now || store_now || mmio_read_now || mmio_write_now) |=>
        (bus_addr_o == $past(cpu_addr_i) &&
         bus_wdata_o == $past(cpu_wdata_i) &&
         bus_wmask_o == $past(cpu_wmask_i))
    ) else $error("dcache bus request bundle was not captured correctly");

    prop_bus_pulses_next_cycle: assert property (
        @(posedge clk) disable iff (!rst_n)
        load_miss_now |=> (bus_mem_re_o && bus_load_miss_o && !bus_mem_we_o)
    ) else $error("dcache load miss did not produce memory read pulse");

    prop_store_pulse_next_cycle: assert property (
        @(posedge clk) disable iff (!rst_n)
        store_now |=> (bus_mem_we_o && !bus_mem_re_o)
    ) else $error("dcache store did not produce memory write pulse");

    prop_mmio_read_pulse_next_cycle: assert property (
        @(posedge clk) disable iff (!rst_n)
        mmio_read_now |=> (bus_mmio_re_o && !bus_mem_re_o && !bus_mem_we_o)
    ) else $error("dcache MMIO read routing pulse mismatch");

    prop_mmio_write_pulse_next_cycle: assert property (
        @(posedge clk) disable iff (!rst_n)
        mmio_write_now |=> (bus_mmio_we_o && !bus_mem_re_o && !bus_mem_we_o)
    ) else $error("dcache MMIO write routing pulse mismatch");

    prop_idle_clears_fill_count: assert property (
        @(posedge clk) disable iff (!rst_n)
        (state == IDLE) |=> (fill_cnt == 3'd0)
    ) else $error("dcache fill counter did not clear in IDLE");

    prop_fill_count_increments: assert property (
        @(posedge clk) disable iff (!rst_n)
        (state == FILL && bus_rdata_valid_i && fill_cnt < 3'd3) |=>
        (fill_cnt == $past(fill_cnt) + 3'd1)
    ) else $error("dcache fill counter did not increment on valid fill beat");

    prop_stall_observable: assert property (
        @(posedge clk) disable iff (!rst_n)
        (state == FILL) |-> cpu_stall_o
    ) else $error("dcache did not stall while a fill was active");

    cov_dcache_load_miss: cover property (@(posedge clk) load_miss_now);
    cov_dcache_store: cover property (@(posedge clk) store_now);
    cov_dcache_mmio_read: cover property (@(posedge clk) mmio_read_now);
    cov_dcache_fill_done: cover property (
        @(posedge clk) state == FILL && bus_rdata_valid_i && fill_cnt == 3'd3);

endmodule

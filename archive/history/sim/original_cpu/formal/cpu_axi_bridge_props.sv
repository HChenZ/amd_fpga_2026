`timescale 1ns / 1ps
//============================================================================
// SVA Property Module: cpu_axi_bridge_props
// Description:
//   Safety properties for the cache-to-AXI bridge:
//   - read launch/capture and 4-beat return bookkeeping
//   - write FIFO full/empty/count behavior
//   - AXI control constants and response completion pulse
//============================================================================
module cpu_axi_bridge_props #(parameter XLEN = 32) (
    input                   clk,
    input                   rst_n,

    input                   cache_re,
    input                   cache_we,
    input   [XLEN-1:0]      cache_addr,
    input   [2:0]           cache_arsize,
    input                   cache_rid,
    input                   cache_valid,
    input                   cache_ready,
    input   [XLEN-1:0]      cache_rdata,
    input                   cache_rdata_valid,
    input                   cache_rdata_last,
    input                   cache_rid_o,
    input                   write_full,
    input                   write_empty,

    input                   cpu_wdata_ready,
    input                   cpu_rdata_valid,
    input   [XLEN-1:0]      cpu_rdata,
    input                   cpu_rid_i,
    input                   resp_en,
    input                   cpu_re,
    input                   cpu_we,
    input   [XLEN-1:0]      cpu_raddr,
    input                   cpu_wid,
    input                   cpu_rid,
    input   [1:0]           cpu_arburst,
    input   [2:0]           cpu_arsize,
    input   [7:0]           cpu_arlen,
    input   [1:0]           cpu_awburst,
    input   [2:0]           cpu_awsize,
    input   [7:0]           cpu_awlen,
    input                   cpu_wdata_valid,
    input                   cpu_rdata_ready,
    input                   rd_ready,
    input                   write_done_pulse,

    input                   rd_state,
    input                   wr_state,
    input   [1:0]           rdata_cnt,
    input                   rdata_done,
    input   [2:0]           fifo_cnt,
    input                   fifo_we,
    input                   fifo_re,
    input                   full,
    input                   empty
);

    localparam RD_IDLE = 1'b0;
    localparam RD_BUSY = 1'b1;
    localparam WR_IDLE = 1'b0;
    localparam WR_BUSY = 1'b1;
    localparam [2:0] EXPECTED_AWSIZE = (XLEN == 64) ? 3'b011 : 3'b010;

    reg past_valid;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            past_valid <= 1'b0;
        else
            past_valid <= 1'b1;
    end

    wire read_launch = (rd_state == RD_IDLE) && cache_re && cache_valid && cache_ready;

    prop_legal_read_state: assert property (
        @(posedge clk) disable iff (!rst_n)
        (rd_state == RD_IDLE) || (rd_state == RD_BUSY)
    ) else $error("cpu_axi_bridge read FSM entered an illegal state");

    prop_legal_write_state: assert property (
        @(posedge clk) disable iff (!rst_n)
        (wr_state == WR_IDLE) || (wr_state == WR_BUSY)
    ) else $error("cpu_axi_bridge write FSM entered an illegal state");

    prop_ready_defs: assert property (
        @(posedge clk) disable iff (!rst_n)
        cache_ready == (rd_state == RD_IDLE) &&
        rd_ready == ((rd_state == RD_IDLE) && cache_re)
    ) else $error("cpu_axi_bridge ready outputs mismatch");

    prop_axi_read_constants: assert property (
        @(posedge clk) disable iff (!rst_n)
        cpu_arlen == 8'd3 && cpu_arburst == 2'b10
    ) else $error("cpu_axi_bridge read burst constants mismatch");

    prop_axi_write_constants: assert property (
        @(posedge clk) disable iff (!rst_n || !past_valid)
        cpu_wid == 1'b1 && cpu_awlen == 8'd0 &&
        cpu_awburst == 2'b00 && cpu_awsize == EXPECTED_AWSIZE
    ) else $error("cpu_axi_bridge write burst constants mismatch");

    prop_read_launch_captured: assert property (
        @(posedge clk) disable iff (!rst_n)
        read_launch |=>
        (rd_state == RD_BUSY &&
         cpu_re == 1'b1 &&
         cpu_raddr == $past(cache_addr) &&
         cpu_arsize == $past(cache_arsize) &&
         cpu_rid == $past(cache_rid))
    ) else $error("cpu_axi_bridge failed to launch/capture a read request");

    prop_read_data_forwarding: assert property (
        @(posedge clk) disable iff (!rst_n)
        cache_rdata_valid == ((rd_state == RD_BUSY) && cpu_rdata_valid) &&
        cache_rdata_last  == ((rd_state == RD_BUSY) && cpu_rdata_valid && (rdata_cnt == 2'd3)) &&
        cpu_rdata_ready   == (rd_state == RD_BUSY)
    ) else $error("cpu_axi_bridge read data/ready forwarding mismatch");

    prop_read_data_value_and_id: assert property (
        @(posedge clk) disable iff (!rst_n)
        (cache_rdata == ((rd_state == RD_BUSY) ? cpu_rdata : {XLEN{1'b0}})) &&
        (cache_rid_o == cpu_rid_i)
    ) else $error("cpu_axi_bridge read data value or RID forwarding mismatch");

    prop_idle_clears_rdata_count: assert property (
        @(posedge clk) disable iff (!rst_n)
        (rd_state == RD_IDLE) |=> (rdata_cnt == 2'd0)
    ) else $error("cpu_axi_bridge rdata counter did not clear in IDLE");

    prop_rdata_count_increments: assert property (
        @(posedge clk) disable iff (!rst_n)
        ((rd_state == RD_BUSY) && cpu_rdata_valid && (rdata_cnt < 2'd3)) |=>
        (rdata_cnt == $past(rdata_cnt) + 2'd1)
    ) else $error("cpu_axi_bridge rdata counter did not increment");

    prop_rdata_done_pulse: assert property (
        @(posedge clk) disable iff (!rst_n)
        ((rdata_cnt == 2'd3) && cpu_rdata_valid) |=> rdata_done
    ) else $error("cpu_axi_bridge rdata_done definition mismatch");

    prop_rdata_done_clears: assert property (
        @(posedge clk) disable iff (!rst_n)
        !((rdata_cnt == 2'd3) && cpu_rdata_valid) |=> !rdata_done
    ) else $error("cpu_axi_bridge rdata_done did not clear");

    prop_read_returns_to_idle_after_done: assert property (
        @(posedge clk) disable iff (!rst_n)
        ((rd_state == RD_BUSY) && rdata_done) |=> (rd_state == RD_IDLE)
    ) else $error("cpu_axi_bridge read FSM did not return to IDLE after done");

    prop_fifo_flags: assert property (
        @(posedge clk) disable iff (!rst_n)
        write_full == full &&
        write_empty == empty &&
        full == (fifo_cnt == 3'd4) &&
        empty == (fifo_cnt == 3'd0)
    ) else $error("cpu_axi_bridge FIFO flags mismatch");

    prop_fifo_count_in_range: assert property (
        @(posedge clk) disable iff (!rst_n)
        fifo_cnt <= 3'd4
    ) else $error("cpu_axi_bridge FIFO count exceeded depth");

    prop_fifo_enqueue: assert property (
        @(posedge clk) disable iff (!rst_n)
        (fifo_we && !fifo_re) |=> (fifo_cnt == $past(fifo_cnt) + 3'd1)
    ) else $error("cpu_axi_bridge FIFO enqueue count mismatch");

    prop_fifo_dequeue: assert property (
        @(posedge clk) disable iff (!rst_n)
        (fifo_re && !fifo_we && !empty) |=> (fifo_cnt == $past(fifo_cnt) - 3'd1)
    ) else $error("cpu_axi_bridge FIFO dequeue count mismatch");

    prop_fifo_simultaneous_enq_deq: assert property (
        @(posedge clk) disable iff (!rst_n)
        (fifo_we && fifo_re) |=> (fifo_cnt == $past(fifo_cnt))
    ) else $error("cpu_axi_bridge FIFO simultaneous enqueue/dequeue count mismatch");

    prop_no_enqueue_when_full: assert property (
        @(posedge clk) disable iff (!rst_n)
        full |-> !fifo_we
    ) else $error("cpu_axi_bridge accepted a FIFO write while full");

    prop_write_start: assert property (
        @(posedge clk) disable iff (!rst_n)
        ((wr_state == WR_IDLE) && !empty) |=> (wr_state == WR_BUSY && cpu_we && cpu_wdata_valid)
    ) else $error("cpu_axi_bridge write FSM did not start for queued write");

    prop_write_done_pulse: assert property (
        @(posedge clk) disable iff (!rst_n)
        (resp_en && (wr_state == WR_BUSY) && empty) |=> write_done_pulse
    ) else $error("cpu_axi_bridge write_done_pulse missing");

    prop_write_done_only_on_response: assert property (
        @(posedge clk) disable iff (!rst_n)
        !(resp_en && (wr_state == WR_BUSY) && empty) |=> !write_done_pulse
    ) else $error("cpu_axi_bridge write_done_pulse asserted without completed write response");

    cov_bridge_read_launch: cover property (@(posedge clk) read_launch);
    cov_bridge_read_last: cover property (
        @(posedge clk) rd_state == RD_BUSY && cpu_rdata_valid && rdata_cnt == 2'd3);
    cov_bridge_fifo_full: cover property (@(posedge clk) full);
    cov_bridge_write_done: cover property (@(posedge clk) write_done_pulse);

endmodule

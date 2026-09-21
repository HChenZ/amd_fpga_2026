`timescale 1ns / 1ps
//============================================================================
// SVA Property Module: bus_interconnect_props
// Description:
//   Safety properties for the cache/MMIO bus interconnect:
//   - dcache/icache read arbitration and RID/ARSIZE routing
//   - store buffering under write FIFO backpressure
//   - MMIO decode and write-data routing
//   - cache read response valid routing
//============================================================================
module bus_interconnect_props #(parameter XLEN = 32) (
    input                   clk,
    input                   rst_n,

    input   [XLEN-1:0]      cpu_addr,
    input   [XLEN-1:0]      cpu_wdata,
    input   [XLEN/8-1:0]    cpu_w_mask,
    input                   mem_re,
    input                   mem_we,
    input                   mmio_re,
    input                   mmio_we,
    input   [XLEN-1:0]      cpu_rdata,
    input                   cpu_rdata_valid,
    input                   cpu_axi_stall_req,

    input                   icache_miss_i,
    input   [XLEN-1:0]      icache_addr_i,
    input   [31:0]          icache_rdata_o,
    input                   icache_rdata_valid_o,

    input                   cache_ready_i,
    input   [XLEN-1:0]      cache_rdata_i,
    input                   cache_rdata_valid_i,
    input                   cache_rdata_last_i,
    input                   write_full_i,
    input                   write_done_pulse_i,
    input                   cache_rid_i,
    input                   cache_re_o,
    input                   cache_we_o,
    input   [XLEN-1:0]      cache_addr_o,
    input   [XLEN-1:0]      cache_waddr_o,
    input   [XLEN-1:0]      cache_wdata_o,
    input   [XLEN/8-1:0]    cache_wmask_o,
    input   [2:0]           cache_arsize_o,
    input                   cache_rid_o,
    input                   cache_valid_o,
    input                   write_done_pulse_o,

    input                   clint_re,
    input                   clint_we,
    input   [2:0]           clint_addr_sel,
    input   [XLEN-1:0]      clint_wdata,
    input   [XLEN/8-1:0]    clint_w_mask,
    input                   uart_re,
    input                   uart_we,
    input   [1:0]           uart_addr_sel,
    input   [31:0]          uart_wdata,
    input                   gpio_re,
    input                   gpio_we,
    input                   gpio_addr_sel,
    input   [31:0]          gpio_wdata,
    input                   cpi_re,
    input   [2:0]           cpi_addr_sel,

    input   [1:0]           rd_state,
    input                   store_fifo_not_empty,
    input                   we_buf,
    input   [XLEN-1:0]      waddr_buf,
    input   [XLEN-1:0]      wdata_buf,
    input   [XLEN/8-1:0]    wmask_buf,
    input   [XLEN-1:0]      dcache_re_addr,
    input   [XLEN-1:0]      icache_re_addr,
    input                   dcache_re_buf,
    input                   icache_re_buf,
    input   [1:0]           icache_resp_cnt,
    input                   icache_rdata_fire
);

    localparam RD_IDLE           = 2'b00;
    localparam RD_DCACHE_WAIT_HS = 2'b01;
    localparam RD_ICACHE_WAIT_HS = 2'b10;
    localparam RD_BUSY           = 2'b11;
    localparam [2:0] DCACHE_ARSIZE = (XLEN == 64) ? 3'b011 : 3'b010;

    wire [15:0] addr_high = cpu_addr[31:16];
    wire hit_clint = (addr_high == 16'h1200);
    wire hit_uart  = (addr_high == 16'h2000);
    wire hit_gpio  = (addr_high == 16'h2001);
    wire hit_cpi   = (addr_high == 16'h6000);
    wire [31:0] wdata_32;
    wire [31:0] expected_icache_rdata;

    generate
        if (XLEN == 64) begin : gen_rv64_bus_props
            wire icache_lane_hi = icache_re_addr[2] ^ icache_resp_cnt[0];
            assign wdata_32 = cpu_addr[2] ? cpu_wdata[63:32] : cpu_wdata[31:0];
            assign expected_icache_rdata = icache_lane_hi ? cache_rdata_i[63:32] : cache_rdata_i[31:0];
        end
        else begin : gen_rv32_bus_props
            assign wdata_32 = cpu_wdata[31:0];
            assign expected_icache_rdata = cache_rdata_i[31:0];
        end
    endgenerate

    function [XLEN-1:0] aligned_addr;
        input [XLEN-1:0] addr;
        begin
            if (XLEN == 64)
                aligned_addr = {addr[XLEN-1:3], 3'b000};
            else
                aligned_addr = {addr[XLEN-1:2], 2'b00};
        end
    endfunction

    prop_legal_read_state: assert property (
        @(posedge clk) disable iff (!rst_n)
        (rd_state == RD_IDLE) ||
        (rd_state == RD_DCACHE_WAIT_HS) ||
        (rd_state == RD_ICACHE_WAIT_HS) ||
        (rd_state == RD_BUSY)
    ) else $error("bus_interconnect read FSM entered an illegal state");

    prop_cache_valid_expr: assert property (
        @(posedge clk) disable iff (!rst_n)
        cache_valid_o == ((rd_state == RD_DCACHE_WAIT_HS) || (rd_state == RD_ICACHE_WAIT_HS))
    ) else $error("bus_interconnect cache_valid_o expression mismatch");

    prop_cache_write_expr: assert property (
        @(posedge clk) disable iff (!rst_n)
        cache_we_o == (we_buf || mem_we)
    ) else $error("bus_interconnect cache_we_o expression mismatch");

    prop_dcache_wait_outputs: assert property (
        @(posedge clk) disable iff (!rst_n)
        (rd_state == RD_DCACHE_WAIT_HS) |->
        (cache_valid_o && cache_rid_o && cache_arsize_o == DCACHE_ARSIZE)
    ) else $error("bus_interconnect dcache read routing mismatch");

    prop_dcache_wait_blocks_read_behind_store: assert property (
        @(posedge clk) disable iff (!rst_n)
        (rd_state == RD_DCACHE_WAIT_HS) |->
        (cache_re_o == !store_fifo_not_empty)
    ) else $error("bus_interconnect dcache read/store ordering mismatch");

    prop_icache_wait_outputs: assert property (
        @(posedge clk) disable iff (!rst_n)
        (rd_state == RD_ICACHE_WAIT_HS) |->
        (cache_valid_o && cache_re_o && !cache_rid_o && cache_arsize_o == 3'b010)
    ) else $error("bus_interconnect icache read routing mismatch");

    prop_cpu_axi_stall_expr: assert property (
        @(posedge clk) disable iff (!rst_n)
        cpu_axi_stall_req == ((we_buf || mem_we) && write_full_i)
    ) else $error("bus_interconnect AXI stall expression mismatch");

    prop_write_done_passthrough: assert property (
        @(posedge clk) disable iff (!rst_n)
        write_done_pulse_o == write_done_pulse_i
    ) else $error("bus_interconnect write_done_pulse passthrough mismatch");

    prop_dcache_addr_capture: assert property (
        @(posedge clk) disable iff (!rst_n)
        mem_re |=> (dcache_re_addr == aligned_addr($past(cpu_addr)))
    ) else $error("bus_interconnect did not capture aligned dcache read address");

    prop_icache_addr_capture: assert property (
        @(posedge clk) disable iff (!rst_n)
        icache_miss_i |=> (icache_re_addr == $past(icache_addr_i))
    ) else $error("bus_interconnect did not capture icache read address");

    prop_idle_dcache_priority: assert property (
        @(posedge clk) disable iff (!rst_n)
        (rd_state == RD_IDLE && mem_re) |=> (rd_state == RD_DCACHE_WAIT_HS)
    ) else $error("bus_interconnect did not prioritize dcache read from IDLE");

    prop_idle_icache_when_no_dcache: assert property (
        @(posedge clk) disable iff (!rst_n)
        (rd_state == RD_IDLE && !mem_re && icache_miss_i) |=> (rd_state == RD_ICACHE_WAIT_HS)
    ) else $error("bus_interconnect did not accept icache read from IDLE");

    prop_busy_dcache_replay: assert property (
        @(posedge clk) disable iff (!rst_n)
        (rd_state == RD_BUSY && cache_rdata_last_i && cache_rdata_valid_i && dcache_re_buf) |=>
        (rd_state == RD_DCACHE_WAIT_HS)
    ) else $error("bus_interconnect did not replay buffered dcache read");

    prop_busy_icache_replay: assert property (
        @(posedge clk) disable iff (!rst_n)
        (rd_state == RD_BUSY && cache_rdata_last_i && cache_rdata_valid_i && !dcache_re_buf && icache_re_buf) |=>
        (rd_state == RD_ICACHE_WAIT_HS)
    ) else $error("bus_interconnect did not replay buffered icache read");

    prop_store_buffer_capture: assert property (
        @(posedge clk) disable iff (!rst_n)
        (mem_we && write_full_i && !we_buf) |=>
        (we_buf &&
         waddr_buf == $past(cpu_addr) &&
         wdata_buf == $past(cpu_wdata) &&
         wmask_buf == $past(cpu_w_mask))
    ) else $error("bus_interconnect did not capture buffered store");

    prop_store_buffer_drains: assert property (
        @(posedge clk) disable iff (!rst_n)
        (we_buf && !write_full_i) |=> !we_buf
    ) else $error("bus_interconnect buffered store did not drain when FIFO became ready");

    prop_write_outputs_current: assert property (
        @(posedge clk) disable iff (!rst_n)
        !we_buf |->
        (cache_waddr_o == cpu_addr &&
         cache_wdata_o == cpu_wdata &&
         cache_wmask_o == cpu_w_mask)
    ) else $error("bus_interconnect current store outputs mismatch");

    prop_write_outputs_buffered: assert property (
        @(posedge clk) disable iff (!rst_n)
        we_buf |->
        (cache_waddr_o == waddr_buf &&
         cache_wdata_o == wdata_buf &&
         cache_wmask_o == wmask_buf)
    ) else $error("bus_interconnect buffered store outputs mismatch");

    prop_response_valid_routing: assert property (
        @(posedge clk) disable iff (!rst_n)
        cpu_rdata_valid == (cache_rid_i && cache_rdata_valid_i)
    ) else $error("bus_interconnect dcache response-valid routing mismatch");

    prop_icache_valid_routing: assert property (
        @(posedge clk) disable iff (!rst_n)
        icache_rdata_valid_o == icache_rdata_fire &&
        icache_rdata_fire == ((rd_state == RD_BUSY) && !cache_rid_i && cache_rdata_valid_i)
    ) else $error("bus_interconnect icache response-valid routing mismatch");

    prop_icache_data_routing: assert property (
        @(posedge clk) disable iff (!rst_n)
        icache_rdata_valid_o |-> (icache_rdata_o == expected_icache_rdata)
    ) else $error("bus_interconnect icache response-data routing mismatch");

    prop_mmio_decode: assert property (
        @(posedge clk) disable iff (!rst_n)
        clint_re == (mmio_re && hit_clint) &&
        clint_we == (mmio_we && hit_clint) &&
        uart_re  == (mmio_re && hit_uart)  &&
        uart_we  == (mmio_we && hit_uart)  &&
        gpio_re  == (mmio_re && hit_gpio)  &&
        gpio_we  == (mmio_we && hit_gpio)  &&
        cpi_re   == (mmio_re && hit_cpi)
    ) else $error("bus_interconnect MMIO decode mismatch");

    prop_mmio_write_data: assert property (
        @(posedge clk) disable iff (!rst_n)
        clint_wdata == cpu_wdata &&
        clint_w_mask == cpu_w_mask &&
        uart_wdata == wdata_32 &&
        gpio_wdata == wdata_32
    ) else $error("bus_interconnect MMIO write-data routing mismatch");

    prop_clint_addr_0000: assert property (
        @(posedge clk) disable iff (!rst_n)
        (cpu_addr[15:0] == 16'h0000) |-> (clint_addr_sel == 3'b000)
    ) else $error("bus_interconnect CLINT 0x0000 select mismatch");

    prop_clint_addr_4000: assert property (
        @(posedge clk) disable iff (!rst_n)
        (cpu_addr[15:0] == 16'h4000) |-> (clint_addr_sel == 3'b001)
    ) else $error("bus_interconnect CLINT 0x4000 select mismatch");

    prop_clint_addr_4004: assert property (
        @(posedge clk) disable iff (!rst_n)
        (cpu_addr[15:0] == 16'h4004) |-> (clint_addr_sel == 3'b010)
    ) else $error("bus_interconnect CLINT 0x4004 select mismatch");

    prop_clint_addr_bff8: assert property (
        @(posedge clk) disable iff (!rst_n)
        (cpu_addr[15:0] == 16'hBFF8) |-> (clint_addr_sel == 3'b011)
    ) else $error("bus_interconnect CLINT 0xBFF8 select mismatch");

    prop_clint_addr_bffc: assert property (
        @(posedge clk) disable iff (!rst_n)
        (cpu_addr[15:0] == 16'hBFFC) |-> (clint_addr_sel == 3'b100)
    ) else $error("bus_interconnect CLINT 0xBFFC select mismatch");

    prop_uart_addr_0: assert property (
        @(posedge clk) disable iff (!rst_n)
        (cpu_addr[3:0] == 4'h0) |-> (uart_addr_sel == 2'b00)
    ) else $error("bus_interconnect UART 0x0 select mismatch");

    prop_uart_addr_4: assert property (
        @(posedge clk) disable iff (!rst_n)
        (cpu_addr[3:0] == 4'h4) |-> (uart_addr_sel == 2'b01)
    ) else $error("bus_interconnect UART 0x4 select mismatch");

    prop_uart_addr_8: assert property (
        @(posedge clk) disable iff (!rst_n)
        (cpu_addr[3:0] == 4'h8) |-> (uart_addr_sel == 2'b10)
    ) else $error("bus_interconnect UART 0x8 select mismatch");

    prop_gpio_addr_0: assert property (
        @(posedge clk) disable iff (!rst_n)
        (cpu_addr[3:0] == 4'h0) |-> (gpio_addr_sel == 1'b0)
    ) else $error("bus_interconnect GPIO 0x0 select mismatch");

    prop_gpio_addr_4: assert property (
        @(posedge clk) disable iff (!rst_n)
        (cpu_addr[3:0] == 4'h4) |-> (gpio_addr_sel == 1'b1)
    ) else $error("bus_interconnect GPIO 0x4 select mismatch");

    prop_cpi_addr_00: assert property (
        @(posedge clk) disable iff (!rst_n)
        (cpu_addr[7:0] == 8'h00) |-> (cpi_addr_sel == 3'b000)
    ) else $error("bus_interconnect CPI 0x00 select mismatch");

    prop_cpi_addr_04: assert property (
        @(posedge clk) disable iff (!rst_n)
        (cpu_addr[7:0] == 8'h04) |-> (cpi_addr_sel == 3'b001)
    ) else $error("bus_interconnect CPI 0x04 select mismatch");

    prop_cpi_addr_08: assert property (
        @(posedge clk) disable iff (!rst_n)
        (cpu_addr[7:0] == 8'h08) |-> (cpi_addr_sel == 3'b010)
    ) else $error("bus_interconnect CPI 0x08 select mismatch");

    prop_cpi_addr_0c: assert property (
        @(posedge clk) disable iff (!rst_n)
        (cpu_addr[7:0] == 8'h0C) |-> (cpi_addr_sel == 3'b011)
    ) else $error("bus_interconnect CPI 0x0C select mismatch");

    prop_cpi_addr_10: assert property (
        @(posedge clk) disable iff (!rst_n)
        (cpu_addr[7:0] == 8'h10) |-> (cpi_addr_sel == 3'b100)
    ) else $error("bus_interconnect CPI 0x10 select mismatch");

    prop_cpi_addr_14: assert property (
        @(posedge clk) disable iff (!rst_n)
        (cpu_addr[7:0] == 8'h14) |-> (cpi_addr_sel == 3'b101)
    ) else $error("bus_interconnect CPI 0x14 select mismatch");

    prop_cpi_addr_18: assert property (
        @(posedge clk) disable iff (!rst_n)
        (cpu_addr[7:0] == 8'h18) |-> (cpi_addr_sel == 3'b110)
    ) else $error("bus_interconnect CPI 0x18 select mismatch");

    prop_cpi_addr_1c: assert property (
        @(posedge clk) disable iff (!rst_n)
        (cpu_addr[7:0] == 8'h1C) |-> (cpi_addr_sel == 3'b111)
    ) else $error("bus_interconnect CPI 0x1C select mismatch");

    cov_bus_dcache_read: cover property (@(posedge clk) rd_state == RD_DCACHE_WAIT_HS && cache_re_o);
    cov_bus_icache_read: cover property (@(posedge clk) rd_state == RD_ICACHE_WAIT_HS && cache_re_o);
    cov_bus_store_buffer: cover property (@(posedge clk) we_buf);
    cov_bus_mmio_uart: cover property (@(posedge clk) uart_we);
    cov_bus_replay: cover property (@(posedge clk) rd_state == RD_BUSY && icache_re_buf);

endmodule

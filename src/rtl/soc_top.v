`timescale 1ns / 1ps
`include "defines.v"
module soc_top #(
    parameter XLEN = `XLEN,
    parameter RAM_DEPTH = `RAM_DEPTH,
    parameter INDEX_WIDTH = `INDEX_WIDTH,
    parameter UART_CLK_FREQ = 50000000,
    parameter UART_BPS = 115200,
    parameter UART_BAUD_CNT_MAX = UART_CLK_FREQ / UART_BPS,
    parameter UART_RX_FIFO_DEPTH = 16,
    parameter UART_TX_FIFO_DEPTH = 16
)(

    input       clk,
    input       rst_n,

    //uart 接口
    input               uart_rxd,
    output              uart_txd,

    //gpio 接口
    input   [1:0]       button,
    output  [1:0]       led,

    // AXI Master 接口
    input                       m_awready,
    output                      m_awvalid,
    output                      m_awid,
    output      [XLEN-1:0]      m_awaddr,
    output      [7:0]           m_awlen,
    output      [2:0]           m_awsize,
    output      [1:0]           m_awburst,
    output                      m_awlock,
    output      [3:0]           m_awcache,
    output      [2:0]           m_awprot,
    output      [3:0]           m_awqos,
    output      [3:0]           m_awregion,
    output                      m_awuser,

    input                       m_wready,
    output                      m_wvalid,
    output                      m_wlast,
    output      [XLEN-1:0]      m_wdata,
    output      [XLEN/8-1:0]    m_wstrb,
    output                      m_wuser,

    input                       m_bvalid,
    input                       m_bid,
    input       [1:0]           m_bresp,
    input                       m_buser,
    output                      m_bready,

    input                       m_arready,
    output                      m_arvalid,
    output                      m_arlock,
    output                      m_arid,
    output      [XLEN-1:0]      m_araddr,
    output      [7:0]           m_arlen,
    output      [2:0]           m_arsize,
    output      [1:0]           m_arburst,
    output      [3:0]           m_arcache,
    output      [2:0]           m_arprot,
    output      [3:0]           m_arqos,
    output      [3:0]           m_arregion,
    output                      m_aruser,

    input                       m_rvalid,
    input                       m_rlast,
    input                       m_rid,
    input       [XLEN-1:0]      m_rdata,
    input       [1:0]           m_rresp,
    input                       m_ruser,
    output                      m_rready

);


    //  wire clk;
    //  wire vio_reset;
    //  wire rst_n_vio;
    //  (* mark_debug = "true" *) wire rst_n;

    //  vio_0 vio_0_inst (
    //      .clk(clk_sys),
    //      .probe_out0(vio_reset)
    //  );

    //  assign rst_n_vio = vio_reset;


    //  clock_generator u_clock_generator(
    //      .clk_in_50m(clk_sys),   // 板子输入时钟
    //      .rst_n_vio(rst_n_vio),    // VIO控制的复位（低有效）

    //      .clk_100m(clk),     // 输出100MHz
    //      .rst_n_out(rst_n)
    //  );


    // =========================================================================
    // 内部连线
    // =========================================================================

    // cpu 数据访存接口（经 bus_interconnect 路由）
    wire    [XLEN-1:0]  cpu_r_data;
    wire                cpu_r_data_valid;
    wire                cpu_axi_stall_req;
    wire                cpu_mem_re;
    wire                cpu_mmio_re;
    wire                cpu_load_miss;
    wire                cpu_store_miss;
    wire                cpu_mem_we;
    wire                cpu_mmio_we;
    wire    [XLEN-1:0]  cpu_addr;
    wire    [XLEN-1:0]  cpu_w_data;
    wire    [XLEN/8-1:0]cpu_w_mask;

    // icache 接口（cpu_core → bus → bridge）
    wire  [XLEN-1:0]    bus_icache_addr;
    wire                bus_icache_miss;
    wire  [31:0]        bus_icache_rdata_to_cpu;
    wire                bus_icache_rdata_valid_to_cpu;

    // bus → bridge 统一 Cache 接口
    wire                bus_cache_re;
    wire                bus_cache_we;
    wire  [XLEN-1:0]    bus_cache_addr;
    wire  [XLEN-1:0]    bus_cache_waddr;
    wire  [XLEN-1:0]    bus_cache_wdata;
    wire  [XLEN/8-1:0]  bus_cache_wmask;
    wire  [2:0]         bus_cache_arsize;
    wire                bus_cache_rid;       // bus → bridge (ARID)
    wire                bus_cache_rid_back;  // bridge → bus (RID return)
    wire                bus_cache_valid;
    wire                bus_cache_ready;
    wire  [XLEN-1:0]    bus_cache_rdata;
    wire                bus_cache_rdata_valid;
    wire                bus_cache_rdata_last;

    // bridge <-> axi_master 自定义接口
    wire                axi_cpu_re;
    wire                axi_cpu_we;
    wire  [XLEN-1:0]    axi_cpu_wdata;
    wire  [XLEN-1:0]    axi_cpu_raddr;
    wire  [XLEN-1:0]    axi_cpu_waddr;
    wire  [XLEN/8-1:0]  axi_cpu_wmask;
    wire                axi_cpu_wid;
    wire                axi_cpu_rid_req;
    wire                axi_cpu_rid_resp;
    wire  [1:0]         axi_cpu_arburst;
    wire  [2:0]         axi_cpu_arsize;
    wire  [7:0]         axi_cpu_arlen;
    wire  [1:0]         axi_cpu_awburst;
    wire  [2:0]         axi_cpu_awsize;
    wire  [7:0]         axi_cpu_awlen;
    wire                axi_cpu_wdata_valid;
    wire                axi_cpu_rdata_ready;
    wire                axi_cpu_wdata_ready;
    wire                axi_cpu_rdata_valid;
    wire  [XLEN-1:0]    axi_cpu_rdata;
    wire  [1:0]         axi_resp;
    wire                axi_resp_en;

    wire                write_empty;        // bridge → cpu_core
    wire                dcache_write_full;
    wire                write_done_pulse;
    wire                bus_write_done_pulse;
    // clint
    wire                clint_re;
    wire                clint_we;
    wire  [XLEN-1:0]    clint_wdata;
    wire  [XLEN-1:0]    clint_rdata;
    wire  [2:0]         clint_addr_sel;
    wire  [XLEN/8-1:0]  clint_w_mask;
    wire                ireq_software;
    wire                ireq_timer;

    // uart
    wire         uart_re;
    wire         uart_we;
    wire  [1:0]  uart_addr_sel;
    wire  [31:0] uart_wdata;
    wire  [31:0] uart_rdata;
    wire         uart_irq;

    // gpio
    wire         gpio_re;
    wire         gpio_we;
    wire         gpio_addr_sel;
    wire         gpio_irq;
    wire  [31:0] gpio_wdata;
    wire  [31:0] gpio_rdata;

    // ascon
    wire         ascon_re;
    wire         ascon_we;
    wire  [5:0]  ascon_addr_sel;
    wire  [31:0] ascon_wdata;
    wire  [31:0] ascon_rdata;
    wire         ascon_irq;

    wire         ireq_external = gpio_irq | uart_irq | ascon_irq;

    // cpi
    wire              probe_inst_valid;
    wire              probe_stall_ld;
    wire              probe_stall_md;
    wire              probe_flush_br;
    wire              cpi_re;
    wire   [2:0]      cpi_addr_sel;
    wire   [XLEN-1:0] cpi_rdata;

    wire              icache_flush;

    // =========================================================================
    // CPU Core
    // =========================================================================
    cpu_core #(.XLEN(XLEN),
               .INDEX_WIDTH(INDEX_WIDTH))
        u_cpu_core(
        .clk(clk),
        .rst_n(rst_n),

        .imem_mem_addr(bus_icache_addr),
        .imem_icache_miss(bus_icache_miss),
        .imem_mem_rdata(bus_icache_rdata_to_cpu),
        .imem_mem_rdata_valid(bus_icache_rdata_valid_to_cpu),

        .dmem_mem_rdata(cpu_r_data),
        .dmem_mem_rdata_valid(cpu_r_data_valid),
        .dmem_axi_stall_req(cpu_axi_stall_req),
        .dmem_write_done_pulse(bus_write_done_pulse),
        .dmem_write_empty(write_empty),
        .dmem_mem_re(cpu_mem_re),
        .dmem_mmio_re(cpu_mmio_re),
        .dmem_mem_load_miss(cpu_load_miss),
        .dmem_mem_store_miss(cpu_store_miss),
        .dmem_mem_we(cpu_mem_we),
        .dmem_mmio_we(cpu_mmio_we),
        .dmem_mem_addr(cpu_addr),
        .dmem_mem_wdata(cpu_w_data),
        .dmem_mem_wmask(cpu_w_mask),

        .ireq_software(ireq_software),
        .ireq_timer(ireq_timer),
        .ireq_external(ireq_external),

        .probe_inst_valid(probe_inst_valid),
        .probe_stall_ld(probe_stall_ld),
        .probe_stall_md(probe_stall_md),
        .probe_flush_br(probe_flush_br),

        .icache_flush(icache_flush)
    );

    // =========================================================================
    // 总线（icache 透传 + dcache 路由 + 外设路由）
    // =========================================================================
    bus_interconnect #(.XLEN(XLEN)) u_bus_interconnect(
        .clk(clk),
        .rst_n(rst_n),

        .cpu_addr(cpu_addr),
        .cpu_wdata(cpu_w_data),
        .cpu_w_mask(cpu_w_mask),
        .mem_re(cpu_mem_re),
        .mem_we(cpu_mem_we),
        .mmio_re(cpu_mmio_re),
        .mmio_we(cpu_mmio_we),
        .cpu_rdata(cpu_r_data),
        .cpu_rdata_valid(cpu_r_data_valid),
        .cpu_axi_stall_req(cpu_axi_stall_req),

        .icache_miss_i(bus_icache_miss),
        .icache_addr_i(bus_icache_addr),
        .icache_rdata_o(bus_icache_rdata_to_cpu),
        .icache_rdata_valid_o(bus_icache_rdata_valid_to_cpu),

        .cache_re_o(bus_cache_re),
        .cache_we_o(bus_cache_we),
        .cache_addr_o(bus_cache_addr),
        .cache_waddr_o(bus_cache_waddr),
        .cache_wdata_o(bus_cache_wdata),
        .cache_wmask_o(bus_cache_wmask),
        .cache_arsize_o(bus_cache_arsize),
        .cache_rid_o(bus_cache_rid),
        .cache_rid_i(bus_cache_rid_back),
        .cache_valid_o(bus_cache_valid),
        .cache_ready_i(bus_cache_ready),
        .cache_rdata_i(bus_cache_rdata),
        .cache_rdata_valid_i(bus_cache_rdata_valid),
        .cache_rdata_last_i(bus_cache_rdata_last),
        .write_full_i(dcache_write_full),
        .write_empty_i(write_empty),
        .write_done_pulse_i(write_done_pulse),
        .write_done_pulse_o(bus_write_done_pulse),
        .load_miss_i(cpu_load_miss),
        .store_miss_i(cpu_store_miss),

        .clint_re(clint_re),
        .clint_we(clint_we),
        .clint_addr_sel(clint_addr_sel),
        .clint_w_mask(clint_w_mask),
        .clint_wdata(clint_wdata),
        .clint_rdata(clint_rdata),

        .uart_re(uart_re),
        .uart_we(uart_we),
        .uart_addr_sel(uart_addr_sel),
        .uart_wdata(uart_wdata),
        .uart_rdata(uart_rdata),

        .gpio_re(gpio_re),
        .gpio_we(gpio_we),
        .gpio_wdata(gpio_wdata),
        .gpio_addr_sel(gpio_addr_sel),
        .gpio_rdata(gpio_rdata),

        .cpi_re(cpi_re),
        .cpi_addr_sel(cpi_addr_sel),
        .cpi_rdata(cpi_rdata),

        .ascon_re(ascon_re),
        .ascon_we(ascon_we),
        .ascon_addr_sel(ascon_addr_sel),
        .ascon_wdata(ascon_wdata),
        .ascon_rdata(ascon_rdata)
    );

    // =========================================================================
    // CPU/AXI Bridge
    // =========================================================================
    cpu_axi_bridge #(.XLEN(XLEN)) u_cpu_axi_bridge(
        .clk(clk),
        .rst_n(rst_n),

        .cache_re(bus_cache_re),
        .cache_we(bus_cache_we),
        .cache_addr(bus_cache_addr),
        .cache_waddr(bus_cache_waddr),
        .cache_wdata(bus_cache_wdata),
        .cache_wmask(bus_cache_wmask),
        .cache_arsize(bus_cache_arsize),
        .cache_rid(bus_cache_rid),
        .cache_rid_o(bus_cache_rid_back),
        .cpu_rid_i(axi_cpu_rid_resp),
        .cache_valid(bus_cache_valid),
        .cache_ready(bus_cache_ready),
        .cache_rdata(bus_cache_rdata),
        .cache_rdata_valid(bus_cache_rdata_valid),
        .cache_rdata_last(bus_cache_rdata_last),
        .write_full(dcache_write_full),
        .write_empty(write_empty),

        .cpu_wdata_ready(axi_cpu_wdata_ready),
        .cpu_rdata_valid(axi_cpu_rdata_valid),
        .cpu_rdata(axi_cpu_rdata),
        .resp(axi_resp),
        .resp_en(axi_resp_en),

        .cpu_re(axi_cpu_re),
        .cpu_we(axi_cpu_we),
        .cpu_wdata(axi_cpu_wdata),
        .cpu_raddr(axi_cpu_raddr),
        .cpu_waddr(axi_cpu_waddr),
        .cpu_wmask(axi_cpu_wmask),
        .cpu_wid(axi_cpu_wid),
        .cpu_rid(axi_cpu_rid_req),
        .cpu_arburst(axi_cpu_arburst),
        .cpu_arsize(axi_cpu_arsize),
        .cpu_arlen(axi_cpu_arlen),
        .cpu_awburst(axi_cpu_awburst),
        .cpu_awsize(axi_cpu_awsize),
        .cpu_awlen(axi_cpu_awlen),
        .cpu_wdata_valid(axi_cpu_wdata_valid),
        .cpu_rdata_ready(axi_cpu_rdata_ready),

        .rd_ready(rd_ready),
        .write_done_pulse(write_done_pulse)
    );

    // =========================================================================
    // AXI Master
    // =========================================================================
    axi_master #(.XLEN(XLEN)) u_axi_master(
        .m_aclk(clk),
        .m_arst_n(rst_n),

        .m_awready(m_awready),
        .m_awvalid(m_awvalid),
        .m_awid(m_awid),
        .m_awaddr(m_awaddr),
        .m_awlen(m_awlen),
        .m_awsize(m_awsize),
        .m_awburst(m_awburst),
        .m_awlock(m_awlock),
        .m_awcache(m_awcache),
        .m_awprot(m_awprot),
        .m_awqos(m_awqos),
        .m_awregion(m_awregion),
        .m_awuser(m_awuser),

        .m_wready(m_wready),
        .m_wvalid(m_wvalid),
        .m_wlast(m_wlast),
        .m_wdata(m_wdata),
        .m_wstrb(m_wstrb),
        .m_wuser(m_wuser),

        .m_bvalid(m_bvalid),
        .m_bid(m_bid),
        .m_bresp(m_bresp),
        .m_buser(m_buser),
        .m_bready(m_bready),

        .m_arready(m_arready),
        .m_arvalid(m_arvalid),
        .m_arlock(m_arlock),
        .m_arid(m_arid),
        .m_araddr(m_araddr),
        .m_arlen(m_arlen),
        .m_arsize(m_arsize),
        .m_arburst(m_arburst),
        .m_arcache(m_arcache),
        .m_arprot(m_arprot),
        .m_arqos(m_arqos),
        .m_arregion(m_arregion),
        .m_aruser(m_aruser),

        .m_rvalid(m_rvalid),
        .m_rlast(m_rlast),
        .m_rid(m_rid),
        .m_rdata(m_rdata),
        .m_rresp(m_rresp),
        .m_ruser(m_ruser),
        .m_rready(m_rready),

        .cpu_re(axi_cpu_re),
        .cpu_we(axi_cpu_we),
        .cpu_wdata(axi_cpu_wdata),
        .cpu_raddr(axi_cpu_raddr),
        .cpu_waddr(axi_cpu_waddr),
        .cpu_wmask(axi_cpu_wmask),
        .cpu_wid(axi_cpu_wid),
        .cpu_rid(axi_cpu_rid_req),
        .cpu_arburst(axi_cpu_arburst),
        .cpu_arsize(axi_cpu_arsize),
        .cpu_arlen(axi_cpu_arlen),
        .cpu_awburst(axi_cpu_awburst),
        .cpu_awsize(axi_cpu_awsize),
        .cpu_awlen(axi_cpu_awlen),
        .cpu_wdata_valid(axi_cpu_wdata_valid),
        .cpu_rdata_ready(axi_cpu_rdata_ready),
        .cpu_wdata_ready(axi_cpu_wdata_ready),
        .cpu_rdata_valid(axi_cpu_rdata_valid),
        .cpu_rdata(axi_cpu_rdata),
        .resp(axi_resp),
        .resp_en(axi_resp_en),
        .cpu_rid_o(axi_cpu_rid_resp)
    );

    // =========================================================================
    // 外设
    // =========================================================================
    uart_ctrl #(
        .CLK_FREQ(UART_CLK_FREQ),
        .UART_BPS(UART_BPS),
        .BAUD_CNT_MAX(UART_BAUD_CNT_MAX),
        .RX_FIFO_DEPTH(UART_RX_FIFO_DEPTH),
        .TX_FIFO_DEPTH(UART_TX_FIFO_DEPTH)
    ) u_uart_ctrl(
        .clk(clk),
        .rst_n(rst_n),
        .addr_sel(uart_addr_sel),
        .cpu_w_data(uart_wdata),
        .cpu_w_en(uart_we),
        .cpu_r_en(uart_re),
        .cpu_r_data(uart_rdata),
        .uart_irq(uart_irq),
        .uart_rxd(uart_rxd),
        .uart_txd(uart_txd)
    );

    clint #(.XLEN(XLEN)) u_clint(
        .clk(clk),
        .rst_n(rst_n),
        .clint_re(clint_re),
        .clint_we(clint_we),
        .clint_addr_sel(clint_addr_sel),
        .clint_w_mask(clint_w_mask),
        .clint_wdata(clint_wdata),
        .clint_rdata(clint_rdata),
        .irq_timer(ireq_timer),
        .irq_software(ireq_software)
    );

    gpio_ctrl u_gpio_ctrl(
        .clk(clk),
        .rst_n(rst_n),
        .cpu_re(gpio_re),
        .cpu_we(gpio_we),
        .cpu_wdata(gpio_wdata),
        .addr_sel(gpio_addr_sel),
        .cpu_rdata(gpio_rdata),
        .gpio_irq(gpio_irq),
        .led_pins(led),
        .btn_pins(button)
    );

    cpi_cnt #(.XLEN(XLEN)) u_cpi_cnt(
        .clk(clk),
        .rst_n(rst_n),
        .probe_inst_valid(probe_inst_valid),
        .probe_stall_ld(probe_stall_ld),
        .probe_stall_md(probe_stall_md),
        .probe_flush_br(probe_flush_br),
        .cpi_re(cpi_re),
        .addr_sel(cpi_addr_sel),
        .cpi_rdata(cpi_rdata)
    );

    // =========================================================================
    // Ascon-AEAD128 MMIO accelerator
    // =========================================================================
    ascon_mmio #(
        .MAX_AD_BYTES (256),
        .MAX_MSG_BYTES(256)
    ) u_ascon_mmio(
        .clk(clk),
        .rst_n(rst_n),
        .ascon_re(ascon_re),
        .ascon_we(ascon_we),
        .ascon_addr_sel(ascon_addr_sel),
        .ascon_wdata(ascon_wdata),
        .ascon_rdata(ascon_rdata),
        .ascon_irq(ascon_irq)
    );

endmodule

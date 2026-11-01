//============================================================================
// Bind File: dcache_bind.sv
//============================================================================
bind dcache dcache_props #(
    .XLEN(XLEN),
    .DCACHE_SET_SIZE(DCACHE_SET_SIZE)
) u_dcache_props (
    .clk(clk),
    .rst_n(rst_n),
    .cpu_addr_i(cpu_addr_i),
    .cpu_wdata_i(cpu_wdata_i),
    .cpu_wmask_i(cpu_wmask_i),
    .cpu_re_i(cpu_re_i),
    .cpu_we_i(cpu_we_i),
    .cpu_req_stall_i(cpu_req_stall_i),
    .cpu_stall_o(cpu_stall_o),
    .bus_addr_o(bus_addr_o),
    .bus_mem_re_o(bus_mem_re_o),
    .bus_mem_we_o(bus_mem_we_o),
    .bus_mmio_re_o(bus_mmio_re_o),
    .bus_mmio_we_o(bus_mmio_we_o),
    .bus_wmask_o(bus_wmask_o),
    .bus_wdata_o(bus_wdata_o),
    .bus_load_miss_o(bus_load_miss_o),
    .bus_store_miss_o(bus_store_miss_o),
    .bus_rdata_valid_i(bus_rdata_valid_i),
    .state(state),
    .hit(hit),
    .cacheable(cacheable),
    .load_miss_now(load_miss_now),
    .store_now(store_now),
    .mmio_read_now(mmio_read_now),
    .mmio_write_now(mmio_write_now),
    .fill_we(fill_we),
    .fill_cnt(fill_cnt)
);

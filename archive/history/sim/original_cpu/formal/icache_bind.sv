//============================================================================
// Bind File: icache_bind.sv
//============================================================================
bind icache icache_props #(
    .XLEN(XLEN),
    .ICACHE_SET_SIZE(ICACHE_SET_SIZE)
) u_icache_props (
    .clk(clk),
    .rst_n(rst_n),
    .cpu_addr_i(cpu_addr_i),
    .cpu_inst_o(cpu_inst_o),
    .cpu_stall_o(cpu_stall_o),
    .mem_addr_o(mem_addr_o),
    .mem_rdata_valid(mem_rdata_valid),
    .icache_miss(icache_miss),
    .redirect_i(redirect_i),
    .fence_i_flush(fence_i_flush),
    .state(state),
    .hit(hit),
    .hit_r(hit_r),
    .fetch_miss(fetch_miss),
    .fill_active(fill_active),
    .fill_cnt(fill_cnt),
    .valid_way0(valid_way0),
    .valid_way1(valid_way1)
);

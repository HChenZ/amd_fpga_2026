//============================================================================
// Bind File: bypass_bind.sv
// Description: Bind SVA properties to bypass DUT (non-intrusive)
//============================================================================
bind bypass bypass_props #(.XLEN(XLEN)) u_bypass_props (
    .rs1_i          (rs1_i),
    .rs2_i          (rs2_i),
    .ex_mem_rd_data (ex_mem_rd_data),
    .mem_wb_rd_data (mem_wb_rd_data),
    .sel_ex_mem_rs1 (sel_ex_mem_rs1),
    .sel_mem_wb_rs1 (sel_mem_wb_rs1),
    .sel_ex_mem_rs2 (sel_ex_mem_rs2),
    .sel_mem_wb_rs2 (sel_mem_wb_rs2),
    .rs1_o          (rs1_o),
    .rs2_o          (rs2_o)
);

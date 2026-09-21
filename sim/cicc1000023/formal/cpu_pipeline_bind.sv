//============================================================================
// Bind File: cpu_pipeline_bind.sv
// Description:
//   Non-intrusive bind of pipeline properties to top_formal.  This bind file
//   matches the optimized pipeline in which load/store requests are generated
//   in EX, mem_stage only post-processes returned load data, and the bypass
//   network has EX/MEM and MEM/WB sources.
//============================================================================
bind top_formal cpu_pipeline_props #(.XLEN(XLEN)) u_cpu_props (
    .clk                (clk),
    .rst_n              (rst_n),

    // ----- Register File -----
    .regfile_rs1        (u_cpu_core.reg_rs1),
    .regfile_rs2        (u_cpu_core.reg_rs2),
    .regfile_r_addr1    (u_cpu_core.rs1_addr),
    .regfile_r_addr2    (u_cpu_core.rs2_addr),
    .regfile_w_addr     (u_cpu_core.mem_reg_addr_o),
    .regfile_w_data     (u_cpu_core.mem_rd_data_o),
    .regfile_w_en       (u_cpu_core.mem_reg_w_en_o),

    // ----- ID stage / hazard inputs -----
    .id_rs1_addr        (u_cpu_core.rs1_addr),
    .id_rs2_addr        (u_cpu_core.rs2_addr),
    .rs1_en             (u_cpu_core.if_id_rs1_en),
    .rs2_en             (u_cpu_core.if_id_rs2_en),

    // ----- Bypass selection computed in ID -----
    .id_sel_ex_mem_rs1  (u_cpu_core.id_sel_ex_mem_rs1),
    .id_sel_mem_wb_rs1  (u_cpu_core.id_sel_mem_wb_rs1),
    .id_sel_ex_mem_rs2  (u_cpu_core.id_sel_ex_mem_rs2),
    .id_sel_mem_wb_rs2  (u_cpu_core.id_sel_mem_wb_rs2),

    // ----- ID/EX pipeline register outputs -----
    .id_ex_waddr        (u_cpu_core.w_reg_waddr_o),
    .id_ex_reg_w_en     (u_cpu_core.reg_w_en_o),
    .id_ex_mem_r_en     (u_cpu_core.mem_r_en_o),
    .id_ex_rs1          (u_cpu_core.rs1_o),
    .id_ex_rs2          (u_cpu_core.rs2_o),

    // ----- EX/MEM pipeline register outputs -----
    .ex_mem_reg_addr    (u_cpu_core.ex_reg_addr_o),
    .ex_mem_reg_w_en    (u_cpu_core.ex_reg_w_en_o),
    .ex_mem_mem_r_en    (u_cpu_core.ex_mem_r_en_o),
    .ex_mem_rd_data     (u_cpu_core.ex_rd_data_o),

    // ----- MEM/WB pipeline register outputs -----
    .mem_wb_reg_addr    (u_cpu_core.mem_reg_addr_o),
    .mem_wb_reg_w_en    (u_cpu_core.mem_reg_w_en_o),
    .mem_wb_rd_data     (u_cpu_core.mem_rd_data_o),

    // ----- Bypass module outputs -----
    .bypass_rs1         (u_cpu_core.rs1_forward),
    .bypass_rs2         (u_cpu_core.rs2_forward),

    // ----- Bypass selection registered in EX -----
    .ex_sel_ex_mem_rs1  (u_cpu_core.ex_sel_ex_mem_rs1),
    .ex_sel_mem_wb_rs1  (u_cpu_core.ex_sel_mem_wb_rs1),
    .ex_sel_ex_mem_rs2  (u_cpu_core.ex_sel_ex_mem_rs2),
    .ex_sel_mem_wb_rs2  (u_cpu_core.ex_sel_mem_wb_rs2),

    // ----- Control signals -----
    .stall_vec          (u_cpu_core.stall),
    .flush_vec          (u_cpu_core.flush),
    .ex_stall_req       (u_cpu_core.ex_stall_req),
    .dcache_stall       (u_cpu_core.dcache_stall),
    .dmem_axi_stall_req (u_cpu_core.dmem_axi_stall_req),
    .icache_stall       (u_cpu_core.icache_stall),
    .fence_i_stall      (u_cpu_core.fence_i_stall),
    .jump_sel           (u_cpu_core.jump_sel),
    .jump_en            (u_cpu_core.jump_en),
    .jump_trap_en       (u_cpu_core.jump_trap_en),
    .jump_trap_out      (u_cpu_core.jump_trap_out),
    .inter_req          (u_cpu_core.inter_req),

    // ----- PC / branch predictor -----
    .pc                 (u_cpu_core.pc),
    .pred_taken         (u_cpu_core.pred_taken),
    .pred_target        (u_cpu_core.pred_target)
);

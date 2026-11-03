`timescale 1ns / 1ps
//============================================================================
// SVA Property Module: cpu_pipeline_props
// Description:
//   CPU-level pipeline formal properties aligned with the current RTL:
//   - load/store access is issued from EX into D-Cache
//   - mem_stage only post-processes returned load data
//   - bypass network has EX/MEM and MEM/WB sources
//============================================================================
module cpu_pipeline_props #(parameter XLEN = 32) (
    input              clk,
    input              rst_n,

    // ----- Register File -----
    input [XLEN-1:0]   regfile_rs1,
    input [XLEN-1:0]   regfile_rs2,
    input [4:0]        regfile_r_addr1,
    input [4:0]        regfile_r_addr2,
    input [4:0]        regfile_w_addr,
    input [XLEN-1:0]   regfile_w_data,
    input              regfile_w_en,

    // ----- ID stage / hazard inputs -----
    input [4:0]        id_rs1_addr,
    input [4:0]        id_rs2_addr,
    input              rs1_en,
    input              rs2_en,

    // ----- Bypass selection computed in ID -----
    input              id_sel_ex_mem_rs1,
    input              id_sel_mem_wb_rs1,
    input              id_sel_ex_mem_rs2,
    input              id_sel_mem_wb_rs2,

    // ----- ID/EX pipeline register outputs -----
    input [4:0]        id_ex_waddr,
    input              id_ex_reg_w_en,
    input              id_ex_mem_r_en,
    input [XLEN-1:0]   id_ex_rs1,
    input [XLEN-1:0]   id_ex_rs2,

    // ----- EX/MEM pipeline register outputs -----
    input [4:0]        ex_mem_reg_addr,
    input              ex_mem_reg_w_en,
    input              ex_mem_mem_r_en,
    input [XLEN-1:0]   ex_mem_rd_data,

    // ----- MEM/WB pipeline register outputs -----
    input [4:0]        mem_wb_reg_addr,
    input              mem_wb_reg_w_en,
    input [XLEN-1:0]   mem_wb_rd_data,

    // ----- Bypass module outputs -----
    input [XLEN-1:0]   bypass_rs1,
    input [XLEN-1:0]   bypass_rs2,

    // ----- Bypass selection registered in EX -----
    input              ex_sel_ex_mem_rs1,
    input              ex_sel_mem_wb_rs1,
    input              ex_sel_ex_mem_rs2,
    input              ex_sel_mem_wb_rs2,

    // ----- Control signals -----
    input [4:0]        stall_vec,
    input [4:0]        flush_vec,
    input              ex_stall_req,
    input              dcache_stall,
    input              dmem_axi_stall_req,
    input              icache_stall,
    input              fence_i_stall,
    input [1:0]        jump_sel,
    input              jump_en,
    input              jump_trap_en,
    input              jump_trap_out,
    input              inter_req,

    // ----- PC / predictor -----
    input [XLEN-1:0]   pc,
    input              pred_taken,
    input [XLEN-1:0]   pred_target
);

    wire stall          = |stall_vec;
    wire if_id_flush    = flush_vec[3];
    wire id_ex_flush    = flush_vec[2];
    wire ex_mem_flush   = flush_vec[1];

    // =====================================================================
    // Section 1: Register x0 is hardwired to zero on read ports
    // =====================================================================
    prop_x0_read_rs1: assert property (
        @(posedge clk) disable iff (!rst_n)
        (regfile_r_addr1 == 5'h0) |-> (regfile_rs1 == {XLEN{1'b0}})
    ) else $error("x0 read port1 returned non-zero");

    prop_x0_read_rs2: assert property (
        @(posedge clk) disable iff (!rst_n)
        (regfile_r_addr2 == 5'h0) |-> (regfile_rs2 == {XLEN{1'b0}})
    ) else $error("x0 read port2 returned non-zero");

    // =====================================================================
    // Section 2: Bypass selection logic correctness
    // Current RTL computes two sources:
    //   - EX/MEM source from current ID/EX destination
    //   - MEM/WB source from current EX/MEM destination
    // =====================================================================
    prop_sel_ex_mem_rs1: assert property (
        @(posedge clk) disable iff (!rst_n)
        id_sel_ex_mem_rs1 == (
            rs1_en && (id_rs1_addr != 5'h0) &&
            id_ex_reg_w_en && (id_rs1_addr == id_ex_waddr)
        )
    ) else $error("sel_ex_mem_rs1 mismatch vs current RTL spec");

    prop_sel_ex_mem_rs2: assert property (
        @(posedge clk) disable iff (!rst_n)
        id_sel_ex_mem_rs2 == (
            rs2_en && (id_rs2_addr != 5'h0) &&
            id_ex_reg_w_en && (id_rs2_addr == id_ex_waddr)
        )
    ) else $error("sel_ex_mem_rs2 mismatch vs current RTL spec");

    prop_sel_mem_wb_rs1: assert property (
        @(posedge clk) disable iff (!rst_n)
        id_sel_mem_wb_rs1 == (
            rs1_en && (id_rs1_addr != 5'h0) &&
            ex_mem_reg_w_en && (id_rs1_addr == ex_mem_reg_addr)
        )
    ) else $error("sel_mem_wb_rs1 mismatch vs current RTL spec");

    prop_sel_mem_wb_rs2: assert property (
        @(posedge clk) disable iff (!rst_n)
        id_sel_mem_wb_rs2 == (
            rs2_en && (id_rs2_addr != 5'h0) &&
            ex_mem_reg_w_en && (id_rs2_addr == ex_mem_reg_addr)
        )
    ) else $error("sel_mem_wb_rs2 mismatch vs current RTL spec");

    prop_no_bypass_x0_rs1: assert property (
        @(posedge clk) disable iff (!rst_n)
        (id_rs1_addr == 5'h0) |-> (!id_sel_ex_mem_rs1 && !id_sel_mem_wb_rs1)
    ) else $error("Bypass triggered for x0 on rs1");

    prop_no_bypass_x0_rs2: assert property (
        @(posedge clk) disable iff (!rst_n)
        (id_rs2_addr == 5'h0) |-> (!id_sel_ex_mem_rs2 && !id_sel_mem_wb_rs2)
    ) else $error("Bypass triggered for x0 on rs2");

    // =====================================================================
    // Section 3: Bypass mux output correctness
    // =====================================================================
    prop_bypass_rs1_ex_mem: assert property (
        @(posedge clk) disable iff (!rst_n)
        ex_sel_ex_mem_rs1 |-> (bypass_rs1 == ex_mem_rd_data)
    ) else $error("Bypass rs1: ex_mem selected but data mismatch");

    prop_bypass_rs1_mem_wb: assert property (
        @(posedge clk) disable iff (!rst_n)
        (!ex_sel_ex_mem_rs1 && ex_sel_mem_wb_rs1) |-> (bypass_rs1 == mem_wb_rd_data)
    ) else $error("Bypass rs1: mem_wb selected but data mismatch");

    prop_bypass_rs1_none: assert property (
        @(posedge clk) disable iff (!rst_n)
        (!ex_sel_ex_mem_rs1 && !ex_sel_mem_wb_rs1) |-> (bypass_rs1 == id_ex_rs1)
    ) else $error("Bypass rs1: no forwarding selected but output mismatch");

    prop_bypass_rs2_ex_mem: assert property (
        @(posedge clk) disable iff (!rst_n)
        ex_sel_ex_mem_rs2 |-> (bypass_rs2 == ex_mem_rd_data)
    ) else $error("Bypass rs2: ex_mem selected but data mismatch");

    prop_bypass_rs2_mem_wb: assert property (
        @(posedge clk) disable iff (!rst_n)
        (!ex_sel_ex_mem_rs2 && ex_sel_mem_wb_rs2) |-> (bypass_rs2 == mem_wb_rd_data)
    ) else $error("Bypass rs2: mem_wb selected but data mismatch");

    prop_bypass_rs2_none: assert property (
        @(posedge clk) disable iff (!rst_n)
        (!ex_sel_ex_mem_rs2 && !ex_sel_mem_wb_rs2) |-> (bypass_rs2 == id_ex_rs2)
    ) else $error("Bypass rs2: no forwarding selected but output mismatch");

    // =====================================================================
    // Section 4: Load-use hazard and ctrl priority
    // Current ctrl.v treats load-use hazard only from the ID/EX load, because
    // data access is initiated early from EX. EX/MEM load is no longer part of
    // stall_ld.
    // =====================================================================
    wire mem_rd_valid_1st = id_ex_mem_r_en && (id_ex_waddr != 5'h0);
    wire rs1_hit_1st = mem_rd_valid_1st && (id_ex_waddr == id_rs1_addr);
    wire rs2_hit_1st = mem_rd_valid_1st && (id_ex_waddr == id_rs2_addr);
    wire load_use_rs1 = rs1_en && rs1_hit_1st;
    wire load_use_rs2 = rs2_en && rs2_hit_1st;
    wire load_use_any = load_use_rs1 || load_use_rs2;

    wire trap_entry = inter_req || jump_trap_en;
    wire higher_pri_before_load =
        trap_entry || jump_trap_out || dcache_stall || dmem_axi_stall_req ||
        ex_stall_req || jump_en;

    prop_ctrl_trap_entry_priority: assert property (
        @(posedge clk) disable iff (!rst_n)
        trap_entry |-> (flush_vec[3:1] == 3'b111 && !stall && (jump_sel == 2'b10))
    ) else $error("Trap-entry control action mismatch vs ctrl.v priority");

    prop_ctrl_trap_return_priority: assert property (
        @(posedge clk) disable iff (!rst_n)
        (!trap_entry && jump_trap_out) |->
        (flush_vec[3:1] == 3'b111 && !stall && (jump_sel == 2'b11))
    ) else $error("Trap-return control action mismatch vs ctrl.v priority");

    prop_ctrl_dcache_stall_priority: assert property (
        @(posedge clk) disable iff (!rst_n)
        (!trap_entry && !jump_trap_out && dcache_stall) |->
        (stall_vec == 5'b11111 && flush_vec == 5'b00000 && (jump_sel == 2'b00))
    ) else $error("D-Cache stall control action mismatch");

    prop_ctrl_axi_stall_priority: assert property (
        @(posedge clk) disable iff (!rst_n)
        (!trap_entry && !jump_trap_out && !dcache_stall && dmem_axi_stall_req) |->
        (stall_vec == 5'b11111 && flush_vec == 5'b00000 && (jump_sel == 2'b00))
    ) else $error("AXI backpressure stall control action mismatch");

    prop_ctrl_ex_stall_priority: assert property (
        @(posedge clk) disable iff (!rst_n)
        (!trap_entry && !jump_trap_out && !dcache_stall && !dmem_axi_stall_req &&
         ex_stall_req) |->
        (stall_vec[4:2] == 3'b111 && ex_mem_flush && !if_id_flush &&
         !id_ex_flush && (jump_sel == 2'b00))
    ) else $error("EX multi-cycle stall action mismatch");

    prop_ctrl_jump_priority: assert property (
        @(posedge clk) disable iff (!rst_n)
        (!trap_entry && !jump_trap_out && !dcache_stall && !dmem_axi_stall_req &&
         !ex_stall_req && jump_en) |->
        (if_id_flush && id_ex_flush && !ex_mem_flush && !stall && (jump_sel == 2'b01))
    ) else $error("Jump/branch redirect action mismatch");

    prop_load_use_stall: assert property (
        @(posedge clk) disable iff (!rst_n)
        (load_use_any && !higher_pri_before_load) |->
        (stall_vec[4:3] == 2'b11 && id_ex_flush && !if_id_flush &&
         !ex_mem_flush && (jump_sel == 2'b00))
    ) else $error("Current one-stage load-use hazard did not trigger expected ctrl action");

    prop_icache_or_fence_stall: assert property (
        @(posedge clk) disable iff (!rst_n)
        (!trap_entry && !jump_trap_out && !dcache_stall && !dmem_axi_stall_req &&
         !ex_stall_req && !jump_en && !load_use_any && (icache_stall || fence_i_stall)) |->
        (stall_vec[4:3] == 2'b11 && id_ex_flush && !if_id_flush &&
         !ex_mem_flush && (jump_sel == 2'b00))
    ) else $error("I-Cache/fence stall action mismatch");

    prop_ctrl_idle_clean: assert property (
        @(posedge clk) disable iff (!rst_n)
        (!trap_entry && !jump_trap_out && !dcache_stall && !dmem_axi_stall_req &&
         !ex_stall_req && !jump_en && !load_use_any && !icache_stall && !fence_i_stall) |->
        (stall_vec == 5'b00000 && flush_vec == 5'b00000 && (jump_sel == 2'b00))
    ) else $error("Control outputs not clean under no-event condition");

    // =====================================================================
    // Section 5: Flush clears registered bypass selects
    // =====================================================================
    prop_flush_clears_bypass: assert property (
        @(posedge clk) disable iff (!rst_n)
        id_ex_flush |=> (!ex_sel_ex_mem_rs1 && !ex_sel_mem_wb_rs1 &&
                         !ex_sel_ex_mem_rs2 && !ex_sel_mem_wb_rs2)
    ) else $error("ID/EX flush did not clear bypass selects");

    // =====================================================================
    // Section 6: PC progress
    // =====================================================================
    prop_pc_progresses: assert property (
        @(posedge clk) disable iff (!rst_n)
        (!stall && !ex_stall_req && jump_sel == 2'b00 && !pred_taken)
        |=> (pc != $past(pc, 1)) || stall || ex_stall_req
    ) else $error("PC stuck without stall, jump, or prediction");

    prop_pc_follows_pred: assert property (
        @(posedge clk) disable iff (!rst_n)
        (!stall && !ex_stall_req && jump_sel == 2'b00 && pred_taken)
        |=> (pc == $past(pred_target, 1))
    ) else $error("PC did not follow branch prediction target");

    // =====================================================================
    // Covers
    // =====================================================================
    cov_bypass_rs1_ex_mem: cover property (@(posedge clk) ex_sel_ex_mem_rs1);
    cov_bypass_rs1_mem_wb: cover property (@(posedge clk) ex_sel_mem_wb_rs1);
    cov_bypass_rs2_ex_mem: cover property (@(posedge clk) ex_sel_ex_mem_rs2);
    cov_bypass_rs2_mem_wb: cover property (@(posedge clk) ex_sel_mem_wb_rs2);
    cov_load_use_stall: cover property (@(posedge clk) load_use_any && stall_vec[4] && stall_vec[3]);
    cov_dcache_stall: cover property (@(posedge clk) dcache_stall && (stall_vec == 5'b11111));
    cov_axi_stall: cover property (@(posedge clk) dmem_axi_stall_req && (stall_vec == 5'b11111));
    cov_icache_stall: cover property (@(posedge clk) icache_stall && stall_vec[4] && stall_vec[3]);
    cov_ex_stall_req: cover property (@(posedge clk) ex_stall_req && stall_vec[4] && ex_mem_flush);
    cov_jump_flush: cover property (@(posedge clk) jump_en && if_id_flush && id_ex_flush);
    cov_trap_entry: cover property (@(posedge clk) trap_entry && (jump_sel == 2'b10));
    cov_normal_exec: cover property (@(posedge clk) stall_vec == 5'b00000 && flush_vec == 5'b00000);

endmodule

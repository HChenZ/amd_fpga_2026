`timescale 1ns / 1ps
`include "defines.v"
module cpu_core #(
    parameter XLEN = 32,
    parameter INDEX_WIDTH = 6
)(

    input               rst_n,
    input               clk,


    //imem - icache 对外存储器接口（连外部 BRAM/AXI）
    output  [XLEN-1:0]  imem_mem_addr,
    output              imem_icache_miss,
    input   [31:0]      imem_mem_rdata,
    input               imem_mem_rdata_valid,

    //dmem - dcache 对外存储器接口（连 bus_interconnect）
    input   [XLEN-1:0]  dmem_mem_rdata,
    input               dmem_mem_rdata_valid,
    input               dmem_axi_stall_req,
    input               dmem_write_done_pulse,
    input               dmem_write_empty,
    output              dmem_mem_re,
    output              dmem_mmio_re,
    output              dmem_mem_load_miss,
    output              dmem_mem_store_miss,
    output              dmem_mem_we,
    output              dmem_mmio_we,
    output  [XLEN-1:0]  dmem_mem_addr,
    output  [XLEN-1:0]  dmem_mem_wdata,
    output  [XLEN/8-1:0]dmem_mem_wmask,

    //interrupt
    input               ireq_software,          //软件中断(MSI)
    input               ireq_timer,             //定时器中断(MTI)
    input               ireq_external,           //外部中断(MEI)

   

    output              probe_inst_valid,
    output              probe_stall_ld,
    output              probe_stall_md,
    output              probe_flush_br,

    //icache
    output              icache_flush
);




    wire    stall_ld;
    wire    stall_md;
    wire    flush_br;

    wire    if_id_inst_valid;
    wire    id_ex_inst_valid;
    wire    ex_mem_inst_valid;
    wire    mem_wb_inst_valid;

    assign probe_inst_valid = mem_wb_inst_valid;
    assign probe_stall_ld = stall_ld;
    assign probe_stall_md = stall_md;    
    assign probe_flush_br = flush_br;
                 

    //csr_file
    wire   [XLEN-1:0]      mtvec_pc;
    wire   [XLEN-1:0]      mepc_pc;

    wire                   inter_req;


    // =========================================================================
    // if stage
    // =========================================================================  
    wire    [XLEN-1:0]      pc;

    //inst_mem


    wire  [31:0]        if_inst;
    wire  [XLEN-1:0]    if_pc;

    wire                if_pred_taken_o;
    wire  [XLEN-1:0]    if_pred_target_o;



    //to ex_stage
    wire   [XLEN-1:0]     if_pc_o;
    wire   [31:0]     if_inst_o ;

    wire [4:0]   rs1_addr;
    wire [4:0]   rs2_addr; 

    wire [4:0]   regfile_rs1_addr = rs1_addr;
    wire [4:0]   regfile_rs2_addr = rs2_addr;
(* max_fanout = "10" *) wire [4:0]   ctrl_rs1_addr = rs1_addr;
(* max_fanout = "10" *) wire [4:0]   ctrl_rs2_addr = rs2_addr;


    wire [6:0]  opcode;
    



    // =========================================================================
    // id stage
    // ========================================================================= 
    wire    [XLEN-1:0]  reg_rs1;
    wire    [XLEN-1:0]  reg_rs2;
    wire     [4:0]      w_reg_waddr;
    wire     [4:0]      reg_addr1;
    wire     [4:0]      reg_addr2;
    wire [XLEN-1:0]  rs1;
    wire [XLEN-1:0]  rs2;   
    wire [2:0]   op_sel;
    wire [5:0]   func_sel;
    wire         reg_w_en;
    wire         mem_w_en;
    wire         id_mem_r_en;    
    wire [XLEN-1:0]  imm;

    wire [4:0]   id_rs1_addr;
    wire [4:0]   id_rs2_addr;  

    wire         rs1_en;       // id_stage 输出（保留原有连接）
    wire         rs2_en;
    wire         if_id_rs1_en; // if_id 提前译码输出，用于 stall_ctrl 关键路径
    wire         if_id_rs2_en;
    wire         csr_w_en;
    wire [11:0]  id_csr_addr;

    wire         id_is_branch;

    //id to ex and ex stage input
    wire   [XLEN-1:0]     rs1_o; 
    wire   [XLEN-1:0]     rs2_o;    
    wire   [2:0]      op_sel_o; 
    wire   [4:0]      w_reg_waddr_o; 
    wire   [5:0]      func_sel_o; 
    wire              reg_w_en_o; 
    wire              mem_w_en_o;
    wire              mem_r_en_o;    
    wire   [XLEN-1:0]     imm_o; 
    wire   [XLEN-1:0]     id_pc; 
    wire   [XLEN-1:0]     ex_pc; 

    wire              csr_w_en_o;
    wire [11:0]  id_csr_addr_o;
    //分支预测器信号
    wire                id_ex_is_branch_o;
    wire                id_ex_pred_taken_o;
    wire  [XLEN-1:0]    id_ex_pred_target_o;

    wire                id_illegal_inst_en;
    wire                id_ex_illegal_inst_en;
    wire  [31:0]        id_inst;
    wire  [31:0]        id_ex_inst_o;

    wire                id_is_word_op;
    wire                id_ex_is_word_op;

    wire                fence_i_en;
    wire                fence_i_flush;
    reg                 fence_i_en_d;

    always @(posedge clk or negedge rst_n)
    begin
        if (!rst_n)
            fence_i_en_d <= 1'b0;
        else
            fence_i_en_d <= fence_i_en;
    end

    assign fence_i_flush = fence_i_en && !fence_i_en_d;

    // fence.i 停顿：等待 AXI 写完成后再放行后续取指
    reg fence_i_stall;
    always @(posedge clk or negedge rst_n) 
    begin
        if (!rst_n)
            fence_i_stall <= 1'b0;
        else if (dmem_write_done_pulse)
            fence_i_stall <= 1'b0;
        else if (fence_i_en && ~dmem_write_empty)
            fence_i_stall <= 1'b1;
    end


    // =========================================================================
    // ex stage
    // ========================================================================= 
    wire         ex_reg_w_en; 
    wire         ex_mem_w_en; 
    wire  [XLEN-1:0] ex_rd_data; 
    wire  [4:0]  ex_reg_addr; 
    wire  [2:0]  ex_op_sel; 
    wire  [XLEN-1:0] ex_mem_addr; 
    wire  [5:0]  ex_func_sel;
    wire  [XLEN-1:0] ex_pc_shift;

    wire            ex_mem_r_en;
    wire  [XLEN-1:0] mul_result;   // 乘法器 2 级流水输出
    wire            ex_is_mul;     // EX 阶段乘法标识

    wire         jump_en;
    wire         jump_trap_en;
    wire         jump_trap_out;  

    wire   [XLEN-1:0]    csr_rdata;
    wire   [XLEN-1:0]    csr_wdata;
    wire              csr_we;
    wire              csr_re;
    wire              trap_en; 
    wire   [XLEN-1:0]     trap_pc; 
    wire   [3:0]      trap_cause;  
    wire              trap_out;     
    wire   [XLEN-1:0]     trap_val; 


    //to ctrl
    wire               ex_stall_req;



    //ex_mem to mem input
    wire            ex_reg_w_en_o;
    wire            ex_mem_w_en_o;
    wire  [XLEN-1:0]    ex_rd_data_o;
    wire  [XLEN-1:0]    ex_mem_addr_o;
    wire  [4:0]     ex_reg_addr_o;
    wire  [2:0]     ex_op_sel_o;
    wire  [5:0]     ex_func_sel_o;
    wire            ex_mem_r_en_o;
    wire            ex_mem_is_mul;  // ex_mem 流水线出来的乘法标识



    // =========================================================================
    // mem stage
    // ========================================================================= 

    // mem_stage → mem_wb
    wire              mem_reg_w_en;
    wire  [XLEN-1:0]  mem_rd_data;
    wire  [4:0]       mem_reg_addr;
    wire  [2:0]       mem_op_sel;

    // mem_wb → regfile
    wire  [2:0]       mem_op_sel_o;
    wire              mem_is_mul_o;  // 当前无用，预留

    //mem_wb
    wire              mem_reg_w_en_o;
    wire   [XLEN-1:0] mem_rd_data_o;
    wire   [4:0]      mem_reg_addr_o;


    // =========================================================================
    // ctrl 相关信号
    // =========================================================================
    wire [4:0]  stall;   // {IF, IF/ID, ID/EX, EX/MEM, MEM/WB}
    wire [4:0]  flush;
    wire [1:0]  jump_sel;


    // =========================================================================
    // 组合计算逻辑（非实例化，统一放顶部）
    // =========================================================================

    // --- Store 写数据/写掩码 ---
    wire [2:0] ex_byte_offset;
    generate
        if(XLEN==64)
            assign ex_byte_offset = ex_mem_addr[2:0];
        else
            assign ex_byte_offset = {1'b0, ex_mem_addr[1:0]};
    endgenerate

    reg  [(XLEN/8)-1:0] ex_mask_base;
    reg  [XLEN-1:0]     ex_w_data;

    always @(*) begin
        ex_w_data    = {XLEN{1'b0}};
        ex_mask_base = 0;
        case(ex_func_sel)
            `EXE_SB_OP: 
            begin 
                ex_w_data = {(XLEN/8){ex_rd_data[7:0]}};  
                ex_mask_base = 1;   
            end
            `EXE_SH_OP:
            begin 
                ex_w_data = {(XLEN/16){ex_rd_data[15:0]}}; 
                ex_mask_base = 3;   
                end
            `EXE_SW_OP: 
            begin 
                ex_w_data = {(XLEN/32){ex_rd_data[31:0]}}; 
                ex_mask_base = 15;  
                end
            `EXE_SD_OP: 
            begin 
                ex_w_data = ex_rd_data;                    
                ex_mask_base = 255; 
                end
            default: ;
        endcase
    end

    wire [(XLEN/8)-1:0] ex_w_mask = ex_mask_base << ex_byte_offset;

    // --- mem_wb 输入---
    wire [XLEN-1:0] mem_wb_data_in = mem_rd_data;

    // --- DMEM 结构冲突 ---

    // --- dcache 连线 ---
    wire [XLEN-1:0] dcache_cpu_addr  = ex_mem_addr;
    wire [XLEN-1:0] dcache_cpu_rdata;
    wire            dcache_stall;


    // =========================================================================
    // icache 内部连线
    // =========================================================================
    wire            icache_stall;
    wire  [31:0]    icache_inst;

    // Accept an interrupt only when trap_pc identifies a valid instruction
    // that can be replayed and no older memory or multicycle work is pending.
    wire inter_accept_ready = id_ex_inst_valid
                           && !dcache_stall
                           && !dmem_axi_stall_req
                           && !ex_stall_req
                           && !icache_stall
                           && !fence_i_stall;

    // =========================================================================
    // branch predictor
    // =========================================================================


    wire            pred_taken;
    wire [XLEN-1:0] pred_target;
    wire            update_en;
    wire [XLEN-1:0] pc_ex;
    wire            actual_taken;
    wire [XLEN-1:0] actual_target;










 

 
    // =========================================================================
    // cpu_core与外部交互信号
    // =========================================================================
    // 端口A：取指，由内部 icache 接管




    // =========================================================================
    // 旁路模块信号：在 ID 阶段提前计算旁路选择信号
    // ========================================================================= 
    wire id_ex_rd_valid  = reg_w_en_o && (w_reg_waddr_o != 5'h0);
    wire ex_mem_rd_valid = ex_reg_w_en_o && (ex_reg_addr_o != 5'h0);

    // 对应 ex_mem 旁路：对比的是当前在 id_ex 里的指令 (下一拍它会到 ex_mem)
    wire id_sel_ex_mem_rs1 = if_id_rs1_en && id_ex_rd_valid && (rs1_addr == w_reg_waddr_o);
    wire id_sel_ex_mem_rs2 = if_id_rs2_en && id_ex_rd_valid && (rs2_addr == w_reg_waddr_o);

    // 对应 mem_wb 旁路：ex_mem 里的指令下一拍经 mem(组合) 到达 mem_wb
    wire id_sel_mem_wb_rs1 = if_id_rs1_en && ex_mem_rd_valid && (rs1_addr == ex_reg_addr_o);
    wire id_sel_mem_wb_rs2 = if_id_rs2_en && ex_mem_rd_valid && (rs2_addr == ex_reg_addr_o);

    // 从 id_ex 输出的旁路选择信号
    wire ex_sel_ex_mem_rs1, ex_sel_mem_wb_rs1;
    wire ex_sel_ex_mem_rs2, ex_sel_mem_wb_rs2;

    wire  [XLEN-1:0] rs1_forward;
    wire  [XLEN-1:0] rs2_forward;





  


    // =========================================================================
    // 子模块实例化
    // ========================================================================= 

   predictor #(
    .XLEN(XLEN),
    .INDEX_WIDTH(INDEX_WIDTH) // 64 项表 (2^6)
    ) u_predictor(
    .clk(clk),
    .rst_n(rst_n),

    // ================= IF 阶段：预测接口 =================
    .pc_if(pc),          
    .pred_taken(pred_taken),     
    .pred_target(pred_target),   

    // ================= EX 阶段：更新接口 (裁判) =================
    .update_en(update_en), 
    .pc_ex(pc_ex), 
    .actual_taken(actual_taken),
    .actual_target(actual_target) 
    );

    // =========================================================================
    // I-Cache（2路组相联，CPU 取指 → icache → 外部 MEM）
    // =========================================================================
    icache #(.XLEN(XLEN),
             .ICACHE_SET_SIZE(64),
             .ICACHE_LINE_WORDS(4))
        u_icache(
        .clk(clk),
        .rst_n(rst_n),

        .cpu_addr_i(pc),
        .cpu_inst_o(icache_inst),
        .cpu_stall_o(icache_stall),

        .mem_addr_o(imem_mem_addr),
        .icache_miss(imem_icache_miss),
        .mem_rdata_i(imem_mem_rdata),
        .mem_rdata_valid(imem_mem_rdata_valid),

        .redirect_i(icache_flush),
        .fence_i_flush(fence_i_flush)
    );

    // =========================================================================
    // D-Cache（写直达，写不分配，2路组相联）
    // =========================================================================
    dcache #(.XLEN(XLEN),
             .DCACHE_SET_SIZE(64),
             .DCACHE_LINE_WORDS(4))
        u_dcache(
        .clk(clk),
        .rst_n(rst_n),

        .cpu_addr_i(dcache_cpu_addr),
        .cpu_wdata_i(ex_w_data),
        .cpu_wmask_i(ex_w_mask),
        .cpu_re_i(ex_mem_r_en),
        .cpu_we_i(ex_mem_w_en && !(inter_req || jump_trap_en || jump_trap_out || ex_stall_req)),
        .cpu_req_stall_i(stall[2]),
        .cpu_rdata_o(dcache_cpu_rdata),
        .cpu_stall_o(dcache_stall),

        .bus_addr_o(dmem_mem_addr),
        .bus_mem_re_o(dmem_mem_re),
        .bus_mem_we_o(dmem_mem_we),
        .bus_mmio_re_o(dmem_mmio_re),
        .bus_mmio_we_o(dmem_mmio_we),
        .bus_wmask_o(dmem_mem_wmask),
        .bus_wdata_o(dmem_mem_wdata),
        .bus_load_miss_o(dmem_mem_load_miss),
        .bus_store_miss_o(dmem_mem_store_miss),
        .bus_rdata_i(dmem_mem_rdata),
        .bus_rdata_valid_i(dmem_mem_rdata_valid)
    );

    // if stage

    if_stage #(
        .XLEN(XLEN)
    ) u_if_stage
    ( 
        .clk(clk),
        .rst_n(rst_n),

        //from ctrl
        .stall(stall[4]),
        .jump_sel(jump_sel), 

        //from branch predictor
        .pred_taken(pred_taken),
        .pred_target(pred_target),             

        //from ex stage
        .ex_pc_shift(ex_pc_shift),    

        //from scr file
        .mtvec_pc(mtvec_pc), 
        .mepc_pc(mepc_pc),
        
        //to inst_mem
        .pc(pc)
    );                   




    //if_id
   if_id #( .XLEN(XLEN)
   )
    u_if_id(


        .clk(clk),
        .rst_n(rst_n),

        //from icache
        .imem_inst_i(icache_inst),

        //from ctrl
        .flush(flush[3]),
        .stall(stall[3]),

        //from predictor
        .pred_taken_i(pred_taken),
        .pred_target_i(pred_target),            

        //from pc_cnt
        .pc(pc),

        //to ex stage
        .pred_taken_o(if_pred_taken_o),
        .pred_target_o(if_pred_target_o),      
        .if_inst_o(if_inst_o),
        .if_pc_o(if_pc_o),
        .opcode(opcode),

        .rs1_addr(rs1_addr),
        .rs2_addr(rs2_addr),
        .rs1_en(if_id_rs1_en),
        .rs2_en(if_id_rs2_en),

        .inst_valid(if_id_inst_valid)


    );


   // id stage
    id_stage  #( 
        .XLEN(XLEN)
    )
    u_id_stage
    (
    //from IF
    .if_pc(if_pc_o),
    .if_inst(if_inst_o),
    .opcode(opcode),

    //from register
    .reg_rs1(reg_rs1),
    .reg_rs2(reg_rs2),

    //to register
    .reg_addr1(reg_addr1),
    .reg_addr2(reg_addr2),

    //to EX
    .id_rs1(rs1),
    .id_rs2(rs2),
    .id_pc(id_pc),
    .id_op_sel(op_sel),
    .id_func_sel(func_sel),
    .id_w_reg_waddr(w_reg_waddr),
    .id_reg_w_en(reg_w_en),
    .id_mem_w_en(mem_w_en),
    .id_mem_r_en(id_mem_r_en),    
    .id_imm(imm),
    .rs1_addr(id_rs1_addr),
    .rs2_addr(id_rs2_addr),
    .is_branch(id_is_branch),

    .csr_w_en(csr_w_en),
    .csr_addr(id_csr_addr),

    .illegal_inst_en(id_illegal_inst_en),
    .id_inst(id_inst),
    .is_word_op(id_is_word_op),
    .fence_i_en(fence_i_en)

);

    //id to ex
    id_ex  #(
    .XLEN(XLEN))
    id_ex_u 
    (
    .clk(clk),
    .rst_n(rst_n),
    .rs1_i(rs1),
    .rs2_i(rs2), 
    .pc_i(id_pc),
    .op_sel_i(op_sel),
    .func_sel_i(func_sel),
    .w_reg_waddr_i(w_reg_waddr),
    .reg_w_en_i(reg_w_en),
    .mem_w_en_i(mem_w_en),
    .mem_r_en_i(id_mem_r_en),    
    .imm_i(imm),
    .rs1_o(rs1_o),
    .rs2_o(rs2_o),   
    .pc_o(ex_pc),
    .op_sel_o(op_sel_o),
    .func_sel_o(func_sel_o),
    .w_reg_waddr_o(w_reg_waddr_o),
    .reg_w_en_o(reg_w_en_o),
    .mem_w_en_o(mem_w_en_o),
    .mem_r_en_o(mem_r_en_o),    
    .imm_o(imm_o),
    .csr_w_en_i(csr_w_en),
    .csr_addr_i(id_csr_addr),
    .is_branch_i(id_is_branch),
    .illegal_inst_en_i(id_illegal_inst_en),
    .inst_i(id_inst),
    .is_word_op_i(id_is_word_op),

    //分支预测器信号
    .pred_taken_i(if_pred_taken_o),
    .pred_target_i(if_pred_target_o),  
    .is_branch_o(id_ex_is_branch_o),  
    //to ex_stage
    .pred_taken_o(id_ex_pred_taken_o),
    .pred_target_o(id_ex_pred_target_o),   

    .stall(stall[2]),
    .flush(flush[2]),
    .csr_w_en_o(csr_w_en_o),
    .csr_addr_o(id_csr_addr_o),
    //旁路选择信号
    .sel_ex_mem_rs1_i(id_sel_ex_mem_rs1),
    .sel_mem_wb_rs1_i(id_sel_mem_wb_rs1),
    .sel_ex_mem_rs2_i(id_sel_ex_mem_rs2),
    .sel_mem_wb_rs2_i(id_sel_mem_wb_rs2),

    .sel_ex_mem_rs1_o(ex_sel_ex_mem_rs1),
    .sel_mem_wb_rs1_o(ex_sel_mem_wb_rs1),
    .sel_ex_mem_rs2_o(ex_sel_ex_mem_rs2),
    .sel_mem_wb_rs2_o(ex_sel_mem_wb_rs2),

    .illegal_inst_en_o(id_ex_illegal_inst_en),
    .inst_o(id_ex_inst_o),
    .is_word_op_o(id_ex_is_word_op),

    .inst_valid_i(if_id_inst_valid),
    .inst_valid_o(id_ex_inst_valid)

);


//bypass
    bypass #(
        .XLEN(XLEN)
    )
    u_bypass(
    //id_ex
    .rs1_i(rs1_o),
    .rs2_i(rs2_o),
    // 传入旁路数据
    .ex_mem_rd_data(ex_rd_data_o),
    .mem_wb_rd_data(mem_rd_data_o),

    .sel_ex_mem_rs1(ex_sel_ex_mem_rs1),
    .sel_mem_wb_rs1(ex_sel_mem_wb_rs1),
    .sel_ex_mem_rs2(ex_sel_ex_mem_rs2),
    .sel_mem_wb_rs2(ex_sel_mem_wb_rs2),

    .rs1_o(rs1_forward),
    .rs2_o(rs2_forward)    


);

    //register files
    regfile  #(
    .XLEN(XLEN))
    regfile_u
    (
    .clk(clk),
    .rst_n(rst_n),

    .w_reg_addr(mem_reg_addr_o),
    .r_reg_addr1(regfile_rs1_addr),
    .r_reg_addr2(regfile_rs2_addr),
    .w_reg_data(mem_rd_data_o),
    .w_reg_en(mem_reg_w_en_o),

    .reg_rs1(reg_rs1),
    .reg_rs2(reg_rs2)

);





    //ex stage
    ex_stage #(
        .XLEN(XLEN)
    ) u_ex_stage(
        
        .clk(clk),
        .rst_n(rst_n),
        .ex_hold(stall[2]),

        //from ID
        .id_pc(ex_pc),
        .id_rs1(rs1_forward),
        .id_rs2(rs2_forward),
        .id_op_sel(op_sel_o),   
        .id_func_sel(func_sel_o),
        .id_reg_w_en(reg_w_en_o),
        .id_mem_w_en(mem_w_en_o),
        .id_imm(imm_o),
        .id_w_reg_waddr(w_reg_waddr_o),
        .id_mem_r_en(mem_r_en_o),
        .csr_w_en(csr_w_en_o),
        .id_csr_addr(id_csr_addr_o),
        .is_word_op(id_ex_is_word_op),

        .is_branch(id_ex_is_branch_o),
        .pred_taken(id_ex_pred_taken_o),
        .pred_target(id_ex_pred_target_o),         
            

        //from csr_file
        .csr_rdata(csr_rdata),

        //中断信号
        .inter_req(inter_req),

        .id_illegal_inst_en(id_ex_illegal_inst_en),
        .id_inst(id_ex_inst_o),

        //to MEM
        .ex_reg_w_en(ex_reg_w_en),
        .ex_mem_w_en(ex_mem_w_en),
        .ex_rd_data(ex_rd_data),
        .ex_reg_addr(ex_reg_addr),
        .ex_op_sel(ex_op_sel),
        .ex_mem_addr(ex_mem_addr),
        .ex_func_sel(ex_func_sel),
        .ex_mem_r_en(ex_mem_r_en),
        
        //to IF
        .ex_pc_shift(ex_pc_shift),

        //to ctrl
        .jump_en(jump_en),
        .jump_trap_en(jump_trap_en),
        .jump_trap_out(jump_trap_out),
        .ex_stall_req(ex_stall_req),

        //to predictor
        .pred_real_taken(actual_taken),
        .pred_real_addr(actual_target),
        .is_branch_o(update_en),
        .ex_pc(pc_ex),


        //to csr_file
        .csr_wdata(csr_wdata),
        .csr_we(csr_we),
        .csr_re(csr_re),
        .trap_en(trap_en),
        .trap_pc(trap_pc),
        .trap_cause(trap_cause),
        .trap_out(trap_out),
        .trap_val(trap_val),

        .mul_result_out(mul_result),
        .ex_is_mul(ex_is_mul)
    );


    //CSR
      csr_file #(
        .XLEN(XLEN)
    )
    u_csr_file(
      .clk(clk),
      .rst_n(rst_n),

      //from ex stage
      .addr(id_csr_addr_o),
      .we(csr_we),
      .re(csr_re),

      .trap_pc(trap_pc),
      .trap_en(trap_en),
      .trap_cause(trap_cause),
      .wdata(csr_wdata),
      .trap_out(trap_out),
      .trap_val(trap_val),

        //中断信号
      .ireq_software(ireq_software),
      .ireq_timer(ireq_timer),
      .ireq_external(ireq_external),
      .inter_accept_ready(inter_accept_ready),
      .inter_req(inter_req),
        //to ex stage
      .rdata(csr_rdata),

      //to if stage
      .mtvec_pc(mtvec_pc),
      .mepc_pc(mepc_pc)
  );


    // ex to mem

     ex_mem #(
    .XLEN(XLEN)
     )   u_ex_mem(
    .clk(clk),
    .rst_n(rst_n),

    .ex_reg_w_en_i(ex_reg_w_en),
    .ex_mem_w_en_i(ex_mem_w_en),
    .ex_rd_data_i(ex_rd_data),
    .ex_mem_addr_i(ex_mem_addr),
    .ex_reg_addr_i(ex_reg_addr),
    .ex_op_sel_i(ex_op_sel),
    .ex_func_sel_i(ex_func_sel),
    .ex_mem_r_en_i(ex_mem_r_en),
    .ex_is_mul_i(ex_is_mul),

    //from ctrl
    .flush(flush[1]),
    .stall(stall[1]),

    //to MEM
    .ex_reg_w_en_o(ex_reg_w_en_o),
    .ex_mem_w_en_o(ex_mem_w_en_o),
    .ex_rd_data_o(ex_rd_data_o),
    .ex_mem_addr_o(ex_mem_addr_o),
    .ex_reg_addr_o(ex_reg_addr_o),
    .ex_op_sel_o(ex_op_sel_o),
    .ex_func_sel_o(ex_func_sel_o),
    .ex_mem_r_en_o(ex_mem_r_en_o),
    .ex_is_mul_o(ex_mem_is_mul),

    .inst_valid_i(id_ex_inst_valid),
    .inst_valid_o(ex_mem_inst_valid)


);


// mem1 stage

// mem stage (合并 mem1 + mem2, 纯组合逻辑)
mem_stage #(
    .XLEN(XLEN)
) u_mem_stage (
    .ex_reg_w_en(ex_reg_w_en_o),
    .ex_rd_data(ex_rd_data_o),
    .ex_mem_addr(ex_mem_addr_o),
    .ex_reg_addr(ex_reg_addr_o),
    .ex_op_sel(ex_op_sel_o),
    .ex_func_sel(ex_func_sel_o),

    .mem_r_data(dcache_cpu_rdata),

    .mem_reg_w_en(mem_reg_w_en),
    .mem_rd_data(mem_rd_data),
    .mem_reg_addr(mem_reg_addr),
    .mem_op_sel(mem_op_sel)
);

// mem_wb
mem_wb #(
    .XLEN(XLEN)
) u_mem_wb(
    .clk(clk),
    .rst_n(rst_n),

    .ex_reg_w_en_i(mem_reg_w_en),
    .ex_rd_data_i(mem_wb_data_in),
    .ex_reg_addr_i(mem_reg_addr),
    .ex_op_sel_i(mem_op_sel),
    .ex_is_mul_i(ex_mem_is_mul),
    .stall(stall[0]),

    .mem_reg_w_en_o(mem_reg_w_en_o),
    .mem_rd_data_o(mem_rd_data_o),
    .mem_reg_addr_o(mem_reg_addr_o),
    .mem_op_sel_o(mem_op_sel_o),
    .mem_is_mul_o(mem_is_mul_o),

    .inst_valid_i(ex_mem_inst_valid),
    .inst_valid_o(mem_wb_inst_valid)
);







    //ctrl
    stall_ctrl u_stall_ctrl(

    //from id stage
    .rs1_addr(ctrl_rs1_addr),
    .rs2_addr(ctrl_rs2_addr),
    .rs1_en(if_id_rs1_en),
    .rs2_en(if_id_rs2_en),

    //from id_ex
    .id_ex_reg_addr(w_reg_waddr_o),
    .id_ex_mem_r_en(mem_r_en_o),

    //from ex_mem
    .ex_mem_mem_reg_addr(ex_reg_addr_o),
    .ex_mem_mem_r_en(ex_mem_r_en_o),

    //from ex stage
    .jump_en(jump_en),
    .jump_trap_en(jump_trap_en),
    .jump_trap_out(jump_trap_out),
    .ex_stall_req(ex_stall_req),

    //中断信号
    .inter_req(inter_req),

    .icache_stall(icache_stall),
    .icache_flush(icache_flush),

    .fence_i_stall(fence_i_stall),

    .dcache_stall(dcache_stall),
    .dmem_axi_stall_req(dmem_axi_stall_req),

    .jump_sel(jump_sel),
    .stall(stall),
    .flush(flush),

    .stall_ld(stall_ld),
    .stall_md(stall_md),
    .flush_br(flush_br)
);




endmodule

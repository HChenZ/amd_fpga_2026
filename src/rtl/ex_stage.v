`timescale 1ns / 1ps
`include "defines.v"

module ex_stage #(
    parameter XLEN = 32
) (

    input                     clk,
    input                     rst_n,
    input                     ex_hold, // ID/EX held by pipeline control

    input   [XLEN-1:0]        id_pc,
    input   [XLEN-1:0]        id_rs1,
    input   [XLEN-1:0]        id_rs2,
    input   [2:0]             id_op_sel,   
    input   [5:0]             id_func_sel,
    input                     id_reg_w_en,
    input                     id_mem_w_en,
    input   [XLEN-1:0]        id_imm,
    input   [4:0]             id_w_reg_waddr,
    input                     id_mem_r_en,
    input                     csr_w_en,
    input   [11:0]            id_csr_addr,
    input   [XLEN-1:0]        csr_rdata,
    input                     is_word_op,


    input                     is_branch,
    input                     pred_taken,
    input   [XLEN-1:0]        pred_target,    

    //中断请求信号
    input                     inter_req,

    input                     id_illegal_inst_en,
    input   [31:0]            id_inst,

    //to mem
    output                    ex_reg_w_en,
    output                    ex_mem_w_en,
    output  reg [XLEN-1:0]    ex_rd_data,
    output       [4:0]        ex_reg_addr,
    output       [2:0]        ex_op_sel,
    output      [XLEN-1:0]    ex_mem_addr,
    output       [5:0]        ex_func_sel,   
    output                    ex_mem_r_en, 

    //to IF    
    output      [XLEN-1:0]    ex_pc_shift, 

    //to ctrl
    output                    jump_en,     
    output  reg               ex_stall_req,

    //to predictor
    output                    pred_real_taken,
    output      [XLEN-1:0]    pred_real_addr,
    output                    is_branch_o,
    output      [XLEN-1:0]    ex_pc,

    //to csr
    output                    jump_trap_en,
    output                    jump_trap_out,

    output  reg [XLEN-1:0]    csr_wdata,
    output                    csr_we,
    output  reg               csr_re,
    output  reg               trap_en,
    output  reg [XLEN-1:0]    trap_pc,
    output  reg [3:0]         trap_cause,
    output  reg               trap_out,
    output  reg [XLEN-1:0]    trap_val,

    output      [XLEN-1:0]    mul_result_out,  // 送出给 cpu_core 做 WB MUX
    output                     ex_is_mul       // 乘法标识，透传至 mem_wb
);

    //RV64独有的字处理操作(需要当作32位处理，高32位置零)
    wire  [XLEN-1:0] id_rs1_reg;
    wire  [XLEN-1:0] id_rs2_reg;
    wire  [XLEN-1:0] id_imm_reg;    

    generate
      if(XLEN==64)
      begin
        assign id_rs1_reg = is_word_op ? {32'h0,id_rs1[31:0]} : id_rs1;  
        assign id_rs2_reg = is_word_op ? {32'h0,id_rs2[31:0]} : id_rs2;  
        assign id_imm_reg = is_word_op ? {32'h0,id_imm[31:0]} : id_imm;  
      end   
      else
      begin
        assign id_rs1_reg = id_rs1;  
        assign id_rs2_reg = id_rs2;  
        assign id_imm_reg = id_imm; 

      end
    endgenerate   



    // =========================================================================
    // M拓展
    // =========================================================================
    reg             mul_start;
    wire [XLEN-1:0] mul_rs1;
    wire [XLEN-1:0] mul_rs2;
    wire [XLEN-1:0] mul_result;
    wire            mul_done;
    reg             is_mul;

    reg             div_start;
    wire [XLEN-1:0] div_rs1;
    wire [XLEN-1:0] div_rs2;    
    wire [XLEN-1:0] div_result;
    wire            div_done;
    wire [XLEN-1:0] final_mul_data;


    assign final_mul_data = is_mul ? mul_result : div_result;
    assign mul_result_out = mul_result;

    // Register both sides of the multiplier; keep done until EX advances.
    multiplier #(.XLEN(XLEN))
    u_multiplier (
    .clk       (clk),
    .rst_n     (rst_n),
    .mul_start (mul_start),
    .rs1_data  (mul_rs1),
    .rs2_data  (mul_rs2),
    .func_sel  (id_func_sel),
    .mul_result(mul_result),
    .mul_done  (mul_done),
    .mul_ack   (mul_done && !ex_hold),
    .cancel    (inter_req || jump_trap_en || jump_trap_out)
    );

    //例化除法/取余模块
    divider #(.XLEN(XLEN))
    u_divider (
    .clk       (clk),
    .rst_n     (rst_n),
    .div_start (div_start),
    .rs1_data  (div_rs1),  
    .rs2_data  (div_rs2),
    .func_sel  (id_func_sel), 
    .div_result(div_result),
    .div_done  (div_done),
    .is_word_op(is_word_op)
    );        


    // =========================================================================
    // ASCON ISE (custom-0) permutation coprocessor
    // =========================================================================
    wire [31:0] ascon_rd_data;
    wire        ascon_perm_done;
    reg         ascon_perm_start;
    wire        ascon_cancel = inter_req || jump_trap_en || jump_trap_out;
    wire        ascon_wr_en = (id_func_sel == `EXE_ASCON_W_OP) && !ex_hold && !ascon_cancel;
    wire [3:0]  ascon_wr_idx    = (id_rs2 < 10) ? id_rs2[3:0] : 4'hf;
    wire [31:0] ascon_wr_data   = id_rs1[31:0];
    wire [3:0]  ascon_rd_idx    = (id_rs1 < 10) ? id_rs1[3:0] : 4'hf;
    wire        ascon_perm_p12  = (id_func_sel == `EXE_ASCON_P12_OP);

    ascon_ise u_ascon_ise (
        .clk(clk), .rst_n(rst_n),
        .cancel(ascon_cancel), .perm_ack(ascon_perm_done && !ex_hold),
        .wr_en(ascon_wr_en), .wr_idx(ascon_wr_idx), .wr_data(ascon_wr_data),
        .rd_idx(ascon_rd_idx), .rd_data(ascon_rd_data),
        .perm_start(ascon_perm_start), .perm_p12(ascon_perm_p12),
        .perm_done(ascon_perm_done)
    );


    // =========================================================================
    // 分支判断基本条件 (独立并行比较，避免复用主ALU加法器)
    // =========================================================================
    wire [XLEN-1:0] diff_bits = id_rs1_reg ^ id_rs2_reg;
    wire rs1_eq_rs2  = ~(|diff_bits);
    
   
    (* use_dsp = "no" *) wire rs1_lt_rs2  = ($signed(id_rs1_reg) < $signed(id_rs2_reg));
    (* use_dsp = "no" *) wire rs1_ltu_rs2 = (id_rs1_reg < id_rs2_reg);


    // =========================================================================
    // 分支预测处理与地址计算（关键路径优化区域）
    // =========================================================================

    reg [XLEN-1:0] jump_link_addr; // 用于 JAL/JALR 的 RD 写回数据
    reg [XLEN-1:0] branch_real_addr; //分支跳转的真实地址
    reg            jump_taken;

    // 加法器独立计算
    wire [XLEN-1:0] pc_plus_imm  = id_pc + id_imm_reg; 
    wire [XLEN-1:0] rs1_plus_imm = (id_rs1_reg + id_imm_reg) & {{(XLEN-1){1'b1}}, 1'b0};
    wire [XLEN-1:0] pc_plus_4 = id_pc + 4;
    // 实际跳转地址逻辑
    always @(*) 
    begin
        branch_real_addr = {XLEN{1'b0}};
        if (id_func_sel == `EXE_JALR_OP)
            branch_real_addr = rs1_plus_imm; 
        else
            branch_real_addr = pc_plus_imm; 
    end

    // 预测更新信号
    (* max_fanout = 16 *) wire pred_real_taken_opt = jump_taken;                    
    
    assign            pred_real_taken = pred_real_taken_opt;
    assign            pred_real_addr = branch_real_addr;
    assign            is_branch_o = is_branch;
    assign            ex_pc_shift = jump_taken ? branch_real_addr : pc_plus_4;
    assign            ex_pc = id_pc;


    // 分支预测结果判断
    wire target_wrong_pc  = (pred_target != pc_plus_imm);                               //除jalr外指令预测结果判断
    wire target_wrong_rs1 = (pred_target != rs1_plus_imm);                              //jalr指令预测结果判断
    wire is_jalr = (id_func_sel == `EXE_JALR_OP);                                       //判断是否是jalr指令
    wire target_wrong = is_jalr ? target_wrong_rs1 : target_wrong_pc;                   

    wire dir_wrong    = (pred_taken  != jump_taken);                                    //用于判断非分支跳转指令但预测器跳转的情况          


    wire mispredict;
    assign mispredict = is_branch ?                                                     //分支预测错误有效信号
                       (jump_taken ? (dir_wrong || target_wrong) : dir_wrong) 
                       : pred_taken; 


    (* max_fanout = 10 *) wire jump_en_opt;
    assign jump_en_opt = mispredict;

    assign jump_en = jump_en_opt;                                                       // 传给外部 controller 的清空信号


    // =========================================================================
    // 透传信号
    // =========================================================================
    assign ex_mem_r_en = id_mem_r_en;
    assign ex_reg_w_en = id_reg_w_en;
    assign ex_mem_w_en = id_mem_w_en;
    assign ex_op_sel   = id_op_sel;
    assign ex_is_mul   = is_mul;
    assign ex_reg_addr = id_w_reg_waddr;
    assign ex_func_sel = id_func_sel;
    assign jump_trap_en  = trap_en;      
    assign jump_trap_out = trap_out;
    assign csr_we        = csr_w_en;


    //目的寄存器不是x0时才能读csr寄存器
    wire rd_is_x0 = (id_w_reg_waddr == 5'h0);


    // =========================================================================
    // 主 ALU (算术与逻辑)
    // =========================================================================
    reg [XLEN-1:0] arith_out;
    reg [XLEN-1:0] logic_out;
    reg [XLEN-1:0] shift_out;
    reg [31:0]     shift_out_32;

    wire  [5:0]     shamt = (XLEN == 64  && ~is_word_op) ? id_rs2_reg[5:0] : {1'b0,id_rs2_reg[4:0]};



    // 逻辑运算
    always @(*) 
    begin
        case(id_func_sel)         
            `EXE_XOR_OP: logic_out = id_rs1_reg ^ id_rs2_reg;
            `EXE_OR_OP:  logic_out = id_rs1_reg | id_rs2_reg;
            `EXE_AND_OP: logic_out = id_rs1_reg & id_rs2_reg;
            `EXE_CSRRW_OP, `EXE_CSRRS_OP, `EXE_CSRRC_OP,
            `EXE_CSRRWI_OP,`EXE_CSRRSI_OP,`EXE_CSRRCI_OP: logic_out = csr_rdata;
            `EXE_ASCON_RD_OP: logic_out = {{(XLEN-32){1'b0}}, ascon_rd_data};
            default:     logic_out = {XLEN{1'b0}};
        endcase
    end

    // 算术运算
    always @(*) 
    begin
        case(id_func_sel)
            `EXE_ADD_OP,`EXE_ADDW_OP:  arith_out = id_rs1_reg + id_rs2_reg;
            `EXE_SUB_OP,`EXE_SUBW_OP:  arith_out = id_rs1_reg - id_rs2_reg;                              
            `EXE_SLT_OP:  arith_out = {{(XLEN-1){1'b0}}, rs1_lt_rs2};  
            `EXE_SLTU_OP: arith_out = {{(XLEN-1){1'b0}}, rs1_ltu_rs2}; 
            `EXE_LUI_OP:  arith_out = id_imm_reg;  
            `EXE_AUIPC_OP:arith_out = id_pc + id_imm_reg;                   
            default:      arith_out = {XLEN{1'b0}};
        endcase                                
    end

    // 移位运算
    always @(*) 
    begin
        case(id_func_sel)
            `EXE_SLL_OP,`EXE_SLLW_OP: shift_out = id_rs1_reg << shamt;      
            `EXE_SRL_OP,`EXE_SRLW_OP: shift_out = id_rs1_reg >> shamt;                      
            `EXE_SRA_OP: shift_out = $signed(id_rs1_reg) >>> shamt;
            `EXE_SRAW_OP: shift_out = { {XLEN-32{1'b0}}, $signed(id_rs1_reg[31:0]) >>> shamt };

            default:     shift_out = {XLEN{1'b0}};
        endcase                                 
    end

    // 乘法运算控制
    assign mul_rs1 = id_rs1_reg;
    assign mul_rs2 = id_rs2_reg;

    assign div_rs1 = id_rs1_reg;
    assign div_rs2 = id_rs2_reg;

    always @(*) 
    begin
        case(id_func_sel)
        `EXE_MUL_OP, `EXE_MULH_OP, `EXE_MULHSU_OP, `EXE_MULHU_OP,`EXE_MULW_OP:
        begin
            mul_start = ~mul_done;
            div_start = 1'b0;
            ascon_perm_start = 1'b0;
            ex_stall_req = ~mul_done;
            is_mul = 1'b1;
        end
        `EXE_DIV_OP, `EXE_DIVU_OP, `EXE_REM_OP, `EXE_REMU_OP, `EXE_DIVW_OP, `EXE_DIVUW_OP, `EXE_REMW_OP, `EXE_REMUW_OP:
        begin
            mul_start = 1'b0;
            div_start = ~div_done;
            ascon_perm_start = 1'b0;
            ex_stall_req = ~div_done;
            is_mul = 1'b0;
        end
        `EXE_ASCON_P12_OP, `EXE_ASCON_P8_OP:
        begin
            mul_start = 1'b0;
            div_start = 1'b0;
            ascon_perm_start = ~ascon_perm_done;
            ex_stall_req = ~ascon_perm_done;
            is_mul = 1'b0;
        end
        default:
        begin
            mul_start = 1'b0;
            div_start = 1'b0;
            ascon_perm_start = 1'b0;
            ex_stall_req = 1'b0;
            is_mul = 1'b0;
        end
        endcase
    end


    // =========================================================================
    // 分支跳转计算
    // =========================================================================
    always @(*) 
    begin
        jump_taken = 1'b0;
        jump_link_addr = {XLEN{1'b0}};

        case(id_func_sel)
            `EXE_BEQ_OP:  jump_taken = rs1_eq_rs2;
            `EXE_BNE_OP:  jump_taken = !rs1_eq_rs2;
            `EXE_BLT_OP:  jump_taken = rs1_lt_rs2;
            `EXE_BGE_OP:  jump_taken = !rs1_lt_rs2;
            `EXE_BLTU_OP: jump_taken = rs1_ltu_rs2;
            `EXE_BGEU_OP: jump_taken = !rs1_ltu_rs2;
            
            `EXE_JAL_OP, `EXE_JALR_OP: 
            begin
                jump_taken = 1'b1;
                jump_link_addr = pc_plus_4;
            end
            default: ;
        endcase
    end


    // =========================================================================
    // CSR 控制信号逻辑
    // =========================================================================
    always @(*)
    begin
        csr_wdata = {XLEN{1'b0}};
        csr_re    = 1'b0;

        case(id_func_sel)
            `EXE_CSRRW_OP: 
            begin 
                csr_re = !rd_is_x0; 
                csr_wdata = id_rs1_reg; 
            end
            `EXE_CSRRS_OP: 
            begin 
                csr_re = 1'b1;      
                csr_wdata = id_rs1_reg | csr_rdata; 
            end
            `EXE_CSRRC_OP: 
            begin 
                csr_re = 1'b1;      
                csr_wdata = ~id_rs1_reg & csr_rdata; 
            end
            `EXE_CSRRWI_OP: 
            begin 
                csr_re = !rd_is_x0; 
                csr_wdata = id_imm_reg; 
            end
            `EXE_CSRRSI_OP: 
            begin 
                csr_re = 1'b1;      
                csr_wdata = id_imm_reg | csr_rdata; 
            end       
            `EXE_CSRRCI_OP: 
            begin 
                csr_re = 1'b1;      
                csr_wdata = ~id_imm_reg & csr_rdata; 
            end
            default:
            begin
                csr_re = 1'b0;
            end
        endcase
    end

    // =========================================================================
    // 访存地址生成 (Load/Store Addr) & 非对齐检测
    // =========================================================================
    
    wire [XLEN-1:0] mem_addr = id_rs1_reg + id_imm_reg;
    

    //assign ex_mem_addr = id_op_sel == `EXE_RES_LOAD_STORE ? mem_addr : {XLEN{1'b0}};
    assign ex_mem_addr = mem_addr;

    // 非对齐检测逻辑
    reg non_aligned_word;
    reg non_aligned_half;
    reg non_aligned_double_word;
    
    always @(*) 
    begin
        non_aligned_word = (ex_mem_addr[1:0] != 2'b00);
        non_aligned_half = (ex_mem_addr[0]   != 1'b0);
        non_aligned_double_word = (ex_mem_addr[2:0] != 3'b000);
    end

    // =========================================================================
    // Trap 触发逻辑
    // =========================================================================
    always @(*) 
    begin
        trap_en    = 0;
        trap_pc    = id_pc;    
        trap_cause = 4'h0;
        trap_out   = 0;
        trap_val   = {XLEN{1'b0}};    

        // A. 中断请求 (优先级高)
        if(inter_req)
          trap_en = 1;

        // B. 非法指令（各 case default / 译码失败，且 inst!=32'h0）
        else if (id_illegal_inst_en)
        begin
            trap_en    = 1;
            trap_cause = 4'h2;
            trap_val   = {{(XLEN-32){1'b0}},id_inst};
        end

        // C. Load/Store 非对齐检测
        else if (id_op_sel == `EXE_RES_LOAD_STORE) 
        begin
            case(id_func_sel)
              `EXE_LD_OP,`EXE_SD_OP:
              begin
                if(non_aligned_double_word)
                begin
                    trap_en    = 1;
                    trap_val   = ex_mem_addr; // 记录坏地址
                    trap_cause = (id_func_sel == `EXE_SD_OP) ? 4'h6 : 4'h4;
                end
              end
              `EXE_LW_OP,`EXE_SW_OP,`EXE_LWU_OP:
              begin
                if(non_aligned_word)
                begin
                    trap_en    = 1;
                    trap_val   = ex_mem_addr; // 记录坏地址
                    trap_cause = (id_func_sel == `EXE_SW_OP) ? 4'h6 : 4'h4;
                end
              end
              `EXE_LH_OP,`EXE_LHU_OP,`EXE_SH_OP:
              begin
                if(non_aligned_half)
                begin
                    trap_en    = 1;
                    trap_val   = ex_mem_addr; // 记录坏地址
                    trap_cause = (id_func_sel == `EXE_SH_OP) ? 4'h6 : 4'h4;
                end
              end
              default:
              begin
                trap_en    = 0;
                trap_val   = {XLEN{1'b0}}; // 记录坏地址
                trap_cause = 4'h0;
              end
            endcase
        end

        // D. 系统指令检测
        else 
        begin
            case(id_func_sel)
                `EXE_ECALL_OP: 
                begin
                    trap_en    = 1;
                    trap_cause = 4'hb; 
                end
                `EXE_EBREAK_OP: 
                begin
                    trap_en    = 1;
                    trap_cause = 4'h3; 
                end
                `EXE_MRET_OP: 
                begin
                    trap_out   = 1;
                end
            endcase
        end
    end

    // =========================================================================
    // 最终结果 MUX
    // =========================================================================

    //对RV64中字操作指令的计算结果进行截取和拓展
    wire [XLEN-1:0] arith_out_final;
    wire [XLEN-1:0] shift_out_fianl;
    wire [XLEN-1:0] mul_data_final;     

    generate
      if(XLEN==64)
      begin
        assign arith_out_final = is_word_op ? {{32{arith_out[31]}},arith_out[31:0]} : arith_out;  
        assign shift_out_fianl = is_word_op ? {{32{shift_out[31]}},shift_out[31:0]} : shift_out;  
        assign mul_data_final = is_word_op ? {{32{final_mul_data[31]}},final_mul_data[31:0]} : final_mul_data;  
      end   
      else
      begin
        assign arith_out_final = arith_out;  
        assign shift_out_fianl = shift_out;  
        assign mul_data_final = final_mul_data; 
      end
    endgenerate


    always @(*) begin
        case(id_op_sel)
            `EXE_RES_ARITH:      ex_rd_data = arith_out_final;
            `EXE_RES_LOGIC:      ex_rd_data = logic_out;
            `EXE_RES_SHIFT:      ex_rd_data = shift_out_fianl;
            `EXE_RES_LOAD_STORE: ex_rd_data = id_rs2_reg;     
            `EXE_RES_JUMP_BRANCH:ex_rd_data = jump_link_addr; 
            `EXE_RES_MUL        :ex_rd_data = mul_data_final;
            default:             ex_rd_data = {XLEN{1'b0}};
        endcase
    end

endmodule

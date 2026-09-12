`timescale 1ns / 1ps
`include "defines.v"
module id_stage #(
    parameter XLEN = 32
) (
    //from IF
    input       [XLEN-1:0]    if_pc,
    input       [31:0]        if_inst,
    input       [6:0]         opcode,

    //from register
    input       [XLEN-1:0]    reg_rs1,
    input       [XLEN-1:0]    reg_rs2,

    //to register
    output   [4:0]            reg_addr1,
    output   [4:0]            reg_addr2,

    //to EX
    output  reg [XLEN-1:0]    id_rs1,
    output  reg [XLEN-1:0]    id_rs2,
    output      [XLEN-1:0]    id_pc,
    output   [4:0]            id_w_reg_waddr,
    output  reg [2:0]         id_op_sel,
    output  reg [5:0]         id_func_sel,
    output  reg               id_reg_w_en,
    output  reg               id_mem_w_en,
    output  reg               id_mem_r_en,   
    output  reg [XLEN-1:0]    id_imm,
    output  reg               is_branch,
    output      [31:0]        id_inst,
    output                    is_word_op,
    
    //to bypass
    output      [4:0]         rs1_addr,
    output      [4:0]         rs2_addr,

    //to ex stage
    output  reg               csr_w_en,
    output      [11:0]        csr_addr,  

    // 仅当译码失败(illegal_inst)或 inst全0或全1 时有效，经 id_ex 送 EX 触发非法指令异常
    output                    illegal_inst_en,

    output  wire              fence_i_en

);





    // =========================================================================
    // 参数与信号定义
    // =========================================================================

    //用于支持RV64I切换的参数
    localparam IMM_I_S = XLEN - 12;
    localparam IMM_U = XLEN - 32;
    localparam IMM_B = XLEN - 13;
    localparam IMM_J = XLEN - 21;
    localparam IMM_CSR = XLEN - 5;


    //从指令inst中译码出的结果
    wire [4:0]        rs1;
    wire [4:0]        rs2;
    wire [4:0]        rd;

    wire [2:0]        func3;
    wire [6:0]        func7;

    wire [11:0]       I_imm;
    wire [19:0]       U_imm;
    wire [11:0]       S_imm;
    wire [12:0]       B_imm;
    wire [20:0]       J_imm;
    wire [XLEN-1:0]   CSR_zimm;

    //源寄存器有效信号
    wire rs1_en;
    wire rs2_en;


    //pc直传给执行模块
    assign id_pc = if_pc;




    // =========================================================================
    // 译码执行阶段
    // =========================================================================

    //译码内部信号
    //assign opcode = if_inst[6:0];
    assign rs1 = if_inst[19:15];
    assign rs2 = if_inst[24:20];
    assign rd = if_inst[11:7];


    assign reg_addr1 = rs1;
    assign reg_addr2 = rs2;    
    assign id_w_reg_waddr = rd;

    assign func3 = if_inst[14:12];
    assign func7 = if_inst[31:25];

    assign I_imm = if_inst[31:20];
    assign U_imm = if_inst[31:12];
    assign S_imm = {if_inst[31:25], if_inst[11:7]};
    assign B_imm = {if_inst[31], if_inst[7], if_inst[30:25], if_inst[11:8], 1'b0};
    assign J_imm = {if_inst[31], if_inst[19:12], if_inst[20], if_inst[30:21], 1'b0};
    assign CSR_zimm = {{IMM_CSR{1'b0}},if_inst[19:15]};


    // 提取指令类型的快速判断
    wire is_alu_w    = (opcode == `OP_OP_W) || (opcode == `OP_OP_IMM_W);
    wire is_alu      = (opcode == `OP_OP) || (opcode == `OP_OP_IMM);
    wire is_load     = (opcode == `OP_LOAD);
    wire is_store    = (opcode == `OP_STORE);
    wire is_branch_op= (opcode == `OP_BRANCH);
    wire is_jal      = (opcode == `OP_JAL);
    wire is_jalr     = (opcode == `OP_JALR);
    wire is_lui      = (opcode == `OP_LUI);
    wire is_auipc    = (opcode == `OP_AUIPC);
    wire is_system   = (opcode == `OP_SYSTEM);
    wire is_misc_mem = (opcode == `OP_MISC_MEM);

    assign fence_i_en = is_misc_mem && (func3 == `FUNCT3_FENCEI);

    wire csr_imm_op  = is_system && (func3 == `FUNCT3_CSRRWI || func3 == `FUNCT3_CSRRSI || func3 == `FUNCT3_CSRRCI);
    wire csr_reg_op  = is_system && (func3 == `FUNCT3_CSRRW  || func3 == `FUNCT3_CSRRS  || func3 == `FUNCT3_CSRRC);



    //非法指令判断
    reg   illegal_inst;
    wire  inst_all_0_1 = (if_inst == 32'h0) || (if_inst == 32'hFFFFFFFF);
    wire  csr_rs1_en;
    assign illegal_inst_en = illegal_inst && inst_all_0_1;
    assign id_inst = if_inst;
    //csr有效控制信号
    assign csr_rs1_en = (opcode == 7'b1110011) && (rs1 != 5'h0);

    assign csr_addr = I_imm;


    //判断RV64特有的字操作指令
    wire R_I_type_word = (opcode == `OP_OP_W) || (opcode == `OP_OP_IMM_W);
    reg  load_store_word;

    generate
      if(XLEN==64)
      begin
        assign is_word_op = (load_store_word || R_I_type_word);  
      end   
      else
      begin
        assign is_word_op = 0;
      end
    endgenerate

    


    //根据不同指令执行译码
    always @(*) 
    begin
      begin
        id_op_sel = `EXE_RES_NOP;
        id_func_sel = `EXE_NOP_OP;
        id_reg_w_en = 1'b0;
        id_mem_w_en = 1'b0;
        id_mem_r_en = 1'b0;
        
        
        
        csr_w_en = 1'b0;
        is_branch = 1'b0;
        illegal_inst = 1'b0;
        load_store_word = 1'b0;

        case (opcode)
        //-----------------------RV64 only (OP-32)----------------------//
          `OP_OP_W:
           begin
            illegal_inst = 1'b0;
            if (XLEN == 64) 
            begin
            if(func7 == `FUNCT7_MULTIPLY)
            begin
            //R type(M拓展) 
              case (func3)

                `FUNCT3_MULW:
                begin
                  id_op_sel = `EXE_RES_MUL;
                  id_func_sel = `EXE_MULW_OP;
                  id_reg_w_en = 1'b1;
                  id_mem_w_en = 1'b0;
                  id_mem_r_en = 1'b0;
                  is_branch = 1'b0; 
                end

                `FUNCT3_DIVW:
                begin
                  id_op_sel = `EXE_RES_MUL;
                  id_func_sel = `EXE_DIVW_OP;
                  id_reg_w_en = 1'b1;
                  id_mem_w_en = 1'b0;
                  id_mem_r_en = 1'b0;
                  is_branch = 1'b0; 
                end
                `FUNCT3_DIVUW:
                begin
                  id_op_sel = `EXE_RES_MUL;
                  id_func_sel = `EXE_DIVUW_OP;
                  id_reg_w_en = 1'b1;
                  id_mem_w_en = 1'b0;
                  id_mem_r_en = 1'b0;
                  is_branch = 1'b0; 
                end
                `FUNCT3_REMW:
                begin
                  id_op_sel = `EXE_RES_MUL;
                  id_func_sel = `EXE_REMW_OP;
                  id_reg_w_en = 1'b1;
                  id_mem_w_en = 1'b0;
                  id_mem_r_en = 1'b0;
                  is_branch = 1'b0; 
                end
                `FUNCT3_REMUW:
                begin
                  id_op_sel = `EXE_RES_MUL;
                  id_func_sel = `EXE_REMUW_OP;
                  id_reg_w_en = 1'b1;
                  id_mem_w_en = 1'b0;
                  id_mem_r_en = 1'b0;
                  is_branch = 1'b0; 
                end
                default:
                begin
                  illegal_inst = 1'b1;
                  id_op_sel = `EXE_RES_NOP;
                  id_func_sel = `EXE_NOP_OP;
                  id_reg_w_en = 1'b0;
                  id_mem_w_en = 1'b0;
                  id_mem_r_en = 1'b0;
                  is_branch = 1'b0; 
                end
              endcase
            end
            else
            begin
              //R type(基础整数指令)
              case (func3)
                  `FUNCT3_ADD_SUB:
                  begin
                    if (func7 == `FUNCT7_ADD)
                      begin
                        id_op_sel = `EXE_RES_ARITH;
                        id_func_sel = `EXE_ADDW_OP;
                        id_reg_w_en = 1'b1;
                        id_mem_w_en = 1'b0;
                        id_mem_r_en = 1'b0;
                        is_branch = 1'b0; 
                      end
                      else
                      begin
                        id_op_sel = `EXE_RES_ARITH;
                        id_func_sel = `EXE_SUBW_OP;
                        id_reg_w_en = 1'b1;
                        id_mem_w_en = 1'b0;
                        id_mem_r_en = 1'b0;
                        is_branch = 1'b0; 
                      end
                  end

                  `FUNCT3_SLL:
                  begin
                    id_op_sel = `EXE_RES_SHIFT;
                    id_func_sel = `EXE_SLLW_OP;
                    id_reg_w_en = 1'b1;
                    id_mem_w_en = 1'b0;
                    id_mem_r_en = 1'b0;
                    is_branch = 1'b0;       
                  end
                  `FUNCT3_SRL_SRA:
                  begin
                    if (func7 == `FUNCT7_SRL)
                      begin
                        id_op_sel = `EXE_RES_SHIFT;
                        id_func_sel = `EXE_SRLW_OP;
                        id_reg_w_en = 1'b1;
                        id_mem_w_en = 1'b0;
                        id_mem_r_en = 1'b0;
                        is_branch = 1'b0; 
                      end
                      else
                      begin
                        id_op_sel = `EXE_RES_SHIFT;
                        id_func_sel = `EXE_SRAW_OP;
                        id_reg_w_en = 1'b1;
                        id_mem_w_en = 1'b0;
                        id_mem_r_en = 1'b0;
                        is_branch = 1'b0; 
                      end
                  end
                default:
                begin
                  illegal_inst = 1'b1;
                  id_op_sel = `EXE_RES_NOP;
                  id_func_sel = `EXE_NOP_OP;
                  id_reg_w_en = 1'b0;
                  id_mem_w_en = 1'b0;
                  id_mem_r_en = 1'b0;
                  is_branch = 1'b0; 
                end
              endcase 
            end        
            end
            else 
            begin
                  illegal_inst = 1'b1;
                  id_op_sel = `EXE_RES_NOP;
                  id_func_sel = `EXE_NOP_OP;
                  id_reg_w_en = 1'b0;
                  id_mem_w_en = 1'b0;
                  id_mem_r_en = 1'b0;
                  is_branch = 1'b0;
            end
          end

        //I type (OP-IMM-32, RV64 only)
        `OP_OP_IMM_W:
          begin
            illegal_inst = 1'b0;
            if (XLEN == 64) begin
                case(func3)
                  `FUNCT3_ADDI:
                  begin
                    id_op_sel = `EXE_RES_ARITH;
                    id_func_sel = `EXE_ADDW_OP;
                    id_reg_w_en = 1'b1;
                    id_mem_w_en = 1'b0;
                    id_mem_r_en = 1'b0; 
                    is_branch = 1'b0; 
                  end
                  `FUNCT3_SLLI:
                  begin
                    id_op_sel = `EXE_RES_SHIFT;
                    id_func_sel = `EXE_SLLW_OP;
                    id_reg_w_en = 1'b1;
                    id_mem_w_en = 1'b0;
                    id_mem_r_en = 1'b0;
                    is_branch = 1'b0; 
                  end 
                  `FUNCT3_SRLI_SRAI:
                  begin
                      if(func7 == `FUNCT7_SRLI)
                      begin
                        id_op_sel = `EXE_RES_SHIFT;
                        id_func_sel = `EXE_SRLW_OP;
                        id_reg_w_en = 1'b1;
                        id_mem_w_en = 1'b0;
                        id_mem_r_en = 1'b0;
                        is_branch = 1'b0; 
                      end
                      else
                      begin
                        id_op_sel = `EXE_RES_SHIFT;
                        id_func_sel = `EXE_SRAW_OP;
                        id_reg_w_en = 1'b1;
                        id_mem_w_en = 1'b0;
                        id_mem_r_en = 1'b0;
                        is_branch = 1'b0; 
                      end
                  end            
                  default:
                  begin
                    illegal_inst = 1'b1;
                    id_op_sel = `EXE_RES_NOP;
                    id_func_sel = `EXE_NOP_OP;
                    id_reg_w_en = 1'b0;
                    id_mem_w_en = 1'b0;
                    id_mem_r_en = 1'b0;
                    is_branch = 1'b0; 
                  end
                endcase
            end
            else 
            begin
                  illegal_inst = 1'b1;
                  id_op_sel = `EXE_RES_NOP;
                  id_func_sel = `EXE_NOP_OP;
                  id_reg_w_en = 1'b0;
                  id_mem_w_en = 1'b0;
                  id_mem_r_en = 1'b0;
                  is_branch = 1'b0;
            end
          end

        //RV64的ld、sd等指令放在后面与RV32一同进行判断


        //-----------------------RV32----------------------//
        `OP_OP:
          begin
            illegal_inst = 1'b0;
            if(func7 == `FUNCT7_MULTIPLY)
            begin
            //R type(M拓展) 
              case (func3)

                `FUNCT3_MUL:
                begin
                  id_op_sel = `EXE_RES_MUL;
                  id_func_sel = `EXE_MUL_OP;
                  id_reg_w_en = 1'b1;
                  id_mem_w_en = 1'b0;
                  id_mem_r_en = 1'b0;
                  is_branch = 1'b0; 
                end
                `FUNCT3_MULH:
                begin
                  id_op_sel = `EXE_RES_MUL;
                  id_func_sel = `EXE_MULH_OP;
                  id_reg_w_en = 1'b1;
                  id_mem_w_en = 1'b0;
                  id_mem_r_en = 1'b0;
                  is_branch = 1'b0; 
                end
                `FUNCT3_MULHSU:
                begin
                  id_op_sel = `EXE_RES_MUL;
                  id_func_sel = `EXE_MULHSU_OP;
                  id_reg_w_en = 1'b1;
                  id_mem_w_en = 1'b0;
                  id_mem_r_en = 1'b0;
                  is_branch = 1'b0; 
                end
                `FUNCT3_MULHU:
                begin
                  id_op_sel = `EXE_RES_MUL;
                  id_func_sel = `EXE_MULHU_OP;
                  id_reg_w_en = 1'b1;
                  id_mem_w_en = 1'b0;
                  id_mem_r_en = 1'b0;
                  is_branch = 1'b0; 
                end
                `FUNCT3_DIV:
                begin
                  id_op_sel = `EXE_RES_MUL;
                  id_func_sel = `EXE_DIV_OP;
                  id_reg_w_en = 1'b1;
                  id_mem_w_en = 1'b0;
                  id_mem_r_en = 1'b0;
                  is_branch = 1'b0; 
                end
                `FUNCT3_DIVU:
                begin
                  id_op_sel = `EXE_RES_MUL;
                  id_func_sel = `EXE_DIVU_OP;
                  id_reg_w_en = 1'b1;
                  id_mem_w_en = 1'b0;
                  id_mem_r_en = 1'b0;
                  is_branch = 1'b0; 
                end
                `FUNCT3_REM:
                begin
                  id_op_sel = `EXE_RES_MUL;
                  id_func_sel = `EXE_REM_OP;
                  id_reg_w_en = 1'b1;
                  id_mem_w_en = 1'b0;
                  id_mem_r_en = 1'b0;
                  is_branch = 1'b0; 
                end
                `FUNCT3_REMU:
                begin
                  id_op_sel = `EXE_RES_MUL;
                  id_func_sel = `EXE_REMU_OP;
                  id_reg_w_en = 1'b1;
                  id_mem_w_en = 1'b0;
                  id_mem_r_en = 1'b0;
                  is_branch = 1'b0; 
                end
                default:
                begin
                  illegal_inst = 1'b1;
                  id_op_sel = `EXE_RES_NOP;
                  id_func_sel = `EXE_NOP_OP;
                  id_reg_w_en = 1'b0;
                  id_mem_w_en = 1'b0;
                  id_mem_r_en = 1'b0;
                  is_branch = 1'b0; 
                end
              endcase
            end
            else
            begin
              //R type(基础整数指令)
              case (func3)
                  `FUNCT3_ADD_SUB:
                  begin
                    if (func7 == `FUNCT7_ADD)
                      begin
                        id_op_sel = `EXE_RES_ARITH;
                        id_func_sel = `EXE_ADD_OP;
                        id_reg_w_en = 1'b1;
                        id_mem_w_en = 1'b0;
                        id_mem_r_en = 1'b0;
                        is_branch = 1'b0; 
                      end
                      else
                      begin
                        id_op_sel = `EXE_RES_ARITH;
                        id_func_sel = `EXE_SUB_OP;
                        id_reg_w_en = 1'b1;
                        id_mem_w_en = 1'b0;
                        id_mem_r_en = 1'b0;
                        is_branch = 1'b0; 
                      end
                  end
                  `FUNCT3_XOR:
                  begin
                    id_op_sel = `EXE_RES_LOGIC;
                    id_func_sel = `EXE_XOR_OP;
                    id_reg_w_en = 1'b1;
                    id_mem_w_en = 1'b0;
                    id_mem_r_en = 1'b0;
                    is_branch = 1'b0; 
                  end
                  `FUNCT3_OR:
                  begin
                    id_op_sel = `EXE_RES_LOGIC;
                    id_func_sel = `EXE_OR_OP;
                    id_reg_w_en = 1'b1;
                    id_mem_w_en = 1'b0;
                    id_mem_r_en = 1'b0;  
                    is_branch = 1'b0;        
                  end
                  `FUNCT3_AND:
                  begin
                    id_op_sel = `EXE_RES_LOGIC;
                    id_func_sel = `EXE_AND_OP;
                    id_reg_w_en = 1'b1;
                    id_mem_w_en = 1'b0;
                    id_mem_r_en = 1'b0;  
                    is_branch = 1'b0;           
                  end
                  `FUNCT3_SLL:
                  begin
                    id_op_sel = `EXE_RES_SHIFT;
                    id_func_sel = `EXE_SLL_OP;
                    id_reg_w_en = 1'b1;
                    id_mem_w_en = 1'b0;
                    id_mem_r_en = 1'b0;  
                    is_branch = 1'b0;       
                  end
                  `FUNCT3_SRL_SRA:
                  begin
                    if (func7 == `FUNCT7_SRL)
                      begin
                        id_op_sel = `EXE_RES_SHIFT;
                        id_func_sel = `EXE_SRL_OP;
                        id_reg_w_en = 1'b1;
                        id_mem_w_en = 1'b0;
                        id_mem_r_en = 1'b0;
                        is_branch = 1'b0; 
                      end
                      else
                      begin
                        id_op_sel = `EXE_RES_SHIFT;
                        id_func_sel = `EXE_SRA_OP;
                        id_reg_w_en = 1'b1;
                        id_mem_w_en = 1'b0;
                        id_mem_r_en = 1'b0;
                        is_branch = 1'b0; 
                      end
                  end
                  `FUNCT3_SLT:
                  begin
                    id_op_sel = `EXE_RES_ARITH;
                    id_func_sel = `EXE_SLT_OP;
                    id_reg_w_en = 1'b1;
                    id_mem_w_en = 1'b0;
                    id_mem_r_en = 1'b0;   
                    is_branch = 1'b0;         
                  end  
                  `FUNCT3_SLTU:
                  begin
                    id_op_sel = `EXE_RES_ARITH;
                    id_func_sel = `EXE_SLTU_OP;
                    id_reg_w_en = 1'b1;
                    id_mem_w_en = 1'b0;
                    id_mem_r_en = 1'b0;
                    is_branch = 1'b0;              
                  end
                default:
                begin
                  illegal_inst = 1'b1;
                  id_op_sel = `EXE_RES_NOP;
                  id_func_sel = `EXE_NOP_OP;
                  id_reg_w_en = 1'b0;
                  id_mem_w_en = 1'b0;
                  id_mem_r_en = 1'b0;
                  is_branch = 1'b0; 
                end
              endcase 
            end        
          end


        //I type(immediate)
        `OP_OP_IMM:
          begin
            illegal_inst = 1'b0;
                case(func3)
                  `FUNCT3_ADDI:
                  begin
                    id_op_sel = `EXE_RES_ARITH;
                    id_func_sel = `EXE_ADD_OP;
                    id_reg_w_en = 1'b1;
                    id_mem_w_en = 1'b0;
                    id_mem_r_en = 1'b0; 
                    is_branch = 1'b0; 
                  end
                  `FUNCT3_XORI:
                  begin
                    id_op_sel = `EXE_RES_LOGIC;
                    id_func_sel = `EXE_XOR_OP;
                    id_reg_w_en = 1'b1;
                    id_mem_w_en = 1'b0;
                    id_mem_r_en = 1'b0;
                    is_branch = 1'b0; 
                  end        
                  `FUNCT3_ORI:
                  begin
                    id_op_sel = `EXE_RES_LOGIC;
                    id_func_sel = `EXE_OR_OP;
                    id_reg_w_en = 1'b1;
                    id_mem_w_en = 1'b0;
                    id_mem_r_en = 1'b0;
                    is_branch = 1'b0; 
                  end 
                  `FUNCT3_ANDI:
                  begin
                    id_op_sel = `EXE_RES_LOGIC;
                    id_func_sel = `EXE_AND_OP;
                    id_reg_w_en = 1'b1;
                    id_mem_w_en = 1'b0;
                    id_mem_r_en = 1'b0;
                    is_branch = 1'b0; 
                  end 
                  `FUNCT3_SLLI:
                  begin
                    id_op_sel = `EXE_RES_SHIFT;
                    id_func_sel = `EXE_SLL_OP;
                    id_reg_w_en = 1'b1;
                    id_mem_w_en = 1'b0;
                    id_mem_r_en = 1'b0; 
                    is_branch = 1'b0; 
                  end 
                  `FUNCT3_SRLI_SRAI:
                  begin
                      if(func7[6:1] == 6'h0)              //因为RV64中移位量占据了func7的最低位，因此只需其中6位来判断
                      begin
                        id_op_sel = `EXE_RES_SHIFT;
                        id_func_sel = `EXE_SRL_OP;
                        id_reg_w_en = 1'b1;
                        id_mem_w_en = 1'b0;
                        id_mem_r_en = 1'b0;
                        is_branch = 1'b0; 
                      end
                      else
                      begin
                        id_op_sel = `EXE_RES_SHIFT;
                        id_func_sel = `EXE_SRA_OP;
                        id_reg_w_en = 1'b1;
                        id_mem_w_en = 1'b0;
                        id_mem_r_en = 1'b0;  
                        is_branch = 1'b0; 
                      end
                  end 
                  `FUNCT3_SLTI:
                  begin
                    id_op_sel = `EXE_RES_ARITH;
                    id_func_sel = `EXE_SLT_OP;
                    id_reg_w_en = 1'b1;
                    id_mem_w_en = 1'b0;
                    id_mem_r_en = 1'b0;
                    is_branch = 1'b0; 
                    end 
                  `FUNCT3_SLTIU:
                  begin
                    id_op_sel = `EXE_RES_ARITH;
                    id_func_sel = `EXE_SLTU_OP;
                    id_reg_w_en = 1'b1;
                    id_mem_w_en = 1'b0;
                    id_mem_r_en = 1'b0;  
                    is_branch = 1'b0; 
                  end                
                  default:
                  begin
                    illegal_inst = 1'b1;
                    id_op_sel = `EXE_RES_NOP;
                    id_func_sel = `EXE_NOP_OP;
                    id_reg_w_en = 1'b0;
                    id_mem_w_en = 1'b0;
                    id_mem_r_en = 1'b0; 
                    is_branch = 1'b0; 
                  end
                endcase           
          end

          //I type(Load)
          `OP_LOAD:
          begin
            illegal_inst = 1'b0;
              case(func3)

                //----------------RV32-------------------//
                `FUNCT3_LB:
                begin
                  id_op_sel = `EXE_RES_LOAD_STORE;
                  id_func_sel = `EXE_LB_OP;
                  id_reg_w_en = 1'b1;
                  id_mem_w_en = 1'b0;
                  id_mem_r_en = 1'b1; 
                  is_branch = 1'b0;  
                end                

                `FUNCT3_LH:
                begin
                  id_op_sel = `EXE_RES_LOAD_STORE;
                  id_func_sel = `EXE_LH_OP;
                  id_reg_w_en = 1'b1;
                  id_mem_w_en = 1'b0;
                  id_mem_r_en = 1'b1;
                  is_branch = 1'b0; 
                end
                `FUNCT3_LW:
                begin
                  id_op_sel = `EXE_RES_LOAD_STORE;
                  id_func_sel = `EXE_LW_OP;
                  id_reg_w_en = 1'b1;
                  id_mem_w_en = 1'b0;
                  id_mem_r_en = 1'b1;
                  is_branch = 1'b0; 
                end  
                `FUNCT3_LBU:
                begin
                  id_op_sel = `EXE_RES_LOAD_STORE;
                  id_func_sel = `EXE_LBU_OP;
                  id_reg_w_en = 1'b1;
                  id_mem_w_en = 1'b0;
                  id_mem_r_en = 1'b1;
                  is_branch = 1'b0;  
                end     
                `FUNCT3_LHU:
                begin
                  id_op_sel = `EXE_RES_LOAD_STORE;
                  id_func_sel = `EXE_LHU_OP;
                  id_reg_w_en = 1'b1;
                  id_mem_w_en = 1'b0;
                  id_mem_r_en = 1'b1;
                  is_branch = 1'b0; 
                end       

              //----------------RV64 only-------------------//

                `FUNCT3_LD:
                begin
                  if (XLEN == 64) 
                  begin
                  id_op_sel = `EXE_RES_LOAD_STORE;
                  id_func_sel = `EXE_LD_OP;
                  id_reg_w_en = 1'b1;
                  id_mem_w_en = 1'b0;
                  id_mem_r_en = 1'b1;
                  is_branch = 1'b0; 
                  load_store_word = 1'b0;
                  end
                  else 
                  begin
                  illegal_inst = 1'b1;
                  id_op_sel = `EXE_RES_NOP;
                  id_func_sel = `EXE_NOP_OP;
                  id_reg_w_en = 1'b0;
                  id_mem_w_en = 1'b0;
                  id_mem_r_en = 1'b0;
                  is_branch = 1'b0;
                  load_store_word = 1'b0;
                  end
                end 

                `FUNCT3_LWU:
                begin
                  if (XLEN == 64) 
                  begin
                  id_op_sel = `EXE_RES_LOAD_STORE;
                  id_func_sel = `EXE_LWU_OP;
                  id_reg_w_en = 1'b1;
                  id_mem_w_en = 1'b0;
                  id_mem_r_en = 1'b1;
                  is_branch = 1'b0; 
                  load_store_word = 1'b0;
                  end
                  else 
                  begin
                  illegal_inst = 1'b1;
                  id_op_sel = `EXE_RES_NOP;
                  id_func_sel = `EXE_NOP_OP;
                  id_reg_w_en = 1'b0;
                  id_mem_w_en = 1'b0;
                  id_mem_r_en = 1'b0;
                  is_branch = 1'b0;
                  load_store_word = 1'b0;
                  end
                end                

              default:
              begin
                illegal_inst = 1'b1;
                id_op_sel = `EXE_RES_NOP;
                id_func_sel = `EXE_NOP_OP;
                id_reg_w_en = 1'b0;
                id_mem_w_en = 1'b0;
                id_mem_r_en = 1'b0;
                is_branch = 1'b0; 
                load_store_word = 1'b0;
              end
            endcase
          end

          //S type
          `OP_STORE:
          begin
            illegal_inst = 1'b0;
            case(func3)
              //----------------RV32-------------------//
              `FUNCT3_SB:
              begin
                id_op_sel = `EXE_RES_LOAD_STORE;
                id_func_sel = `EXE_SB_OP;
                id_reg_w_en = 1'b0;
                id_mem_w_en = 1'b1;
                id_mem_r_en = 1'b0;
                is_branch = 1'b0; 
              end
              `FUNCT3_SH:
              begin
                id_op_sel = `EXE_RES_LOAD_STORE;
                id_func_sel = `EXE_SH_OP;
                id_reg_w_en = 1'b0;
                id_mem_w_en = 1'b1;
                id_mem_r_en = 1'b0;
                is_branch = 1'b0; 
              end
               `FUNCT3_SW:
              begin
                id_op_sel = `EXE_RES_LOAD_STORE;
                id_func_sel = `EXE_SW_OP;
                id_reg_w_en = 1'b0;
                id_mem_w_en = 1'b1;
                id_mem_r_en = 1'b0; 
                is_branch = 1'b0; 
              end  


              //----------------RV64 only-------------------//
              `FUNCT3_SD:
              begin
                if (XLEN == 64) 
                begin
                id_op_sel = `EXE_RES_LOAD_STORE;
                id_func_sel = `EXE_SD_OP;
                id_reg_w_en = 1'b0;
                id_mem_w_en = 1'b1;
                id_mem_r_en = 1'b0;
                is_branch = 1'b0; 
                load_store_word = 1'b0;
                end
                else 
                begin
                illegal_inst = 1'b1;
                id_op_sel = `EXE_RES_NOP;
                id_func_sel = `EXE_NOP_OP;
                id_reg_w_en = 1'b0;
                id_mem_w_en = 1'b0;
                id_mem_r_en = 1'b0;
                is_branch = 1'b0;
                load_store_word = 1'b0;
                end
              end  
              default:
              begin
                illegal_inst = 1'b1;
                id_op_sel = `EXE_RES_NOP;
                id_func_sel = `EXE_NOP_OP;
                id_reg_w_en = 1'b0;
                id_mem_w_en = 1'b0;
                id_mem_r_en = 1'b0;
                is_branch = 1'b0; 
                load_store_word = 1'b0;
              end
            endcase
          end

          //B type
          `OP_BRANCH:
          begin
            illegal_inst = 1'b0;
            case(func3)
              `FUNCT3_BEQ:
              begin
                id_op_sel = `EXE_RES_JUMP_BRANCH;
                id_func_sel = `EXE_BEQ_OP;
                id_reg_w_en = 1'b0;
                id_mem_w_en = 1'b0;
                id_mem_r_en = 1'b0;
                is_branch = 1'b1; 
              end
              `FUNCT3_BNE:
              begin
                id_op_sel = `EXE_RES_JUMP_BRANCH;
                id_func_sel = `EXE_BNE_OP;
                id_reg_w_en = 1'b0;
                id_mem_w_en = 1'b0;
                id_mem_r_en = 1'b0;  
                is_branch = 1'b1; 
              end
              `FUNCT3_BLT:
              begin
                id_op_sel = `EXE_RES_JUMP_BRANCH;
                id_func_sel = `EXE_BLT_OP;
                id_reg_w_en = 1'b0;
                id_mem_w_en = 1'b0;
                id_mem_r_en = 1'b0;
                is_branch = 1'b1; 
              end    
              `FUNCT3_BGE:
              begin
                id_op_sel = `EXE_RES_JUMP_BRANCH;
                id_func_sel = `EXE_BGE_OP;
                id_reg_w_en = 1'b0;
                id_mem_w_en = 1'b0;
                id_mem_r_en = 1'b0;
                is_branch = 1'b1; 
              end            
              `FUNCT3_BLTU:
              begin
                id_op_sel = `EXE_RES_JUMP_BRANCH;
                id_func_sel = `EXE_BLTU_OP;
                id_reg_w_en = 1'b0;
                id_mem_w_en = 1'b0;
                id_mem_r_en = 1'b0;
                is_branch = 1'b1; 
              end                  
              `FUNCT3_BGEU:
              begin
                id_op_sel = `EXE_RES_JUMP_BRANCH;
                id_func_sel = `EXE_BGEU_OP;
                id_reg_w_en = 1'b0;
                id_mem_w_en = 1'b0;
                id_mem_r_en = 1'b0;
                is_branch = 1'b1; 
              end    
              default:
              begin
                illegal_inst = 1'b1;
                id_op_sel = `EXE_RES_NOP;
                id_func_sel = `EXE_NOP_OP;
                id_reg_w_en = 1'b0;
                id_mem_w_en = 1'b0;
                id_mem_r_en = 1'b0;   
                is_branch = 1'b0; 
              end
            endcase
          end

          // JUMP AND LINK
          `OP_JAL:
          begin
            illegal_inst = 1'b0;
            id_op_sel = `EXE_RES_JUMP_BRANCH;
            id_func_sel = `EXE_JAL_OP;
            id_reg_w_en = 1'b1;
            id_mem_w_en = 1'b0;
            id_mem_r_en = 1'b0;  
            is_branch = 1'b1; 
          end
          `OP_JALR:
          begin
            illegal_inst = 1'b0;
            id_op_sel = `EXE_RES_JUMP_BRANCH;
            id_func_sel = `EXE_JALR_OP;
            id_reg_w_en = 1'b1;
            id_mem_w_en = 1'b0;
            id_mem_r_en = 1'b0;  
            is_branch = 1'b1;   
          end          

        //lui and auipc
          `OP_LUI:
          begin
            illegal_inst = 1'b0;
            id_op_sel = `EXE_RES_ARITH;
            id_func_sel = `EXE_LUI_OP;
            id_reg_w_en = 1'b1;
            id_mem_w_en = 1'b0;
            id_mem_r_en = 1'b0;
            is_branch = 1'b0;   
          end
          `OP_AUIPC:
          begin
            illegal_inst = 1'b0;
            id_op_sel = `EXE_RES_ARITH;
            id_func_sel = `EXE_AUIPC_OP;
            id_reg_w_en = 1'b1;
            id_mem_w_en = 1'b0;
            id_mem_r_en = 1'b0;
            is_branch = 1'b0;  
          end        

          //FENCE,FENCE.I(本设计对FENCE指令视作NOP) (FENCI.I指令设计为立即数为4的jal指令，等效于跳转到当前pc+4)
          `OP_MISC_MEM:
          begin
            case(func3)
            `FUNCT3_FENCEI:
            begin
              illegal_inst = 1'b0;
              id_op_sel = `EXE_RES_JUMP_BRANCH;
              id_func_sel = `EXE_JAL_OP;
              id_reg_w_en = 1'b0;
              id_mem_w_en = 1'b0;
              id_mem_r_en = 1'b0;
              is_branch = 1'b1;
            end
            `FUNCT3_FENCE:
            begin
              illegal_inst = 1'b0;
              id_op_sel = `EXE_RES_NOP;
              id_func_sel = `EXE_NOP_OP;
              id_reg_w_en = 1'b0;
              id_mem_w_en = 1'b0;
              id_mem_r_en = 1'b0;
              is_branch = 1'b0;  
            end
            default:
            begin
              illegal_inst = 1'b1;
              id_op_sel = `EXE_RES_NOP;
              id_func_sel = `EXE_NOP_OP;
              id_reg_w_en = 1'b0;
              id_mem_w_en = 1'b0;
              id_mem_r_en = 1'b0;
              is_branch = 1'b0;  
            end
            endcase
          end  

          `OP_SYSTEM:
          begin
            illegal_inst = 1'b0;
            case(func3)
              `FUNCT3_CSRRW:
              begin
                id_op_sel = `EXE_RES_LOGIC;
                id_func_sel = `EXE_CSRRW_OP;
                id_reg_w_en = 1'b1;
                id_mem_w_en = 1'b0;
                id_mem_r_en = 1'b0;
                csr_w_en = 1'b1;
                is_branch = 1'b0;               
              end
              `FUNCT3_CSRRS:
              begin
                id_op_sel = `EXE_RES_LOGIC;
                id_func_sel = `EXE_CSRRS_OP;
                id_reg_w_en = 1'b1;
                id_mem_w_en = 1'b0;
                id_mem_r_en = 1'b0;
                csr_w_en = csr_rs1_en;
                is_branch = 1'b0;                
              end
               `FUNCT3_CSRRC:
              begin
                id_op_sel = `EXE_RES_LOGIC;
                id_func_sel = `EXE_CSRRC_OP;
                id_reg_w_en = 1'b1;
                id_mem_w_en = 1'b0;
                id_mem_r_en = 1'b0;
                csr_w_en = csr_rs1_en; 
                is_branch = 1'b0;               
              end   
               `FUNCT3_CSRRWI:
              begin
                id_op_sel = `EXE_RES_LOGIC;
                id_func_sel = `EXE_CSRRWI_OP;           
                id_reg_w_en = 1'b1;
                id_mem_w_en = 1'b0;
                id_mem_r_en = 1'b0;
                csr_w_en = 1'b1;
                is_branch = 1'b0;                 
              end                         
               `FUNCT3_CSRRSI:
              begin
                id_op_sel = `EXE_RES_LOGIC;
                id_func_sel = `EXE_CSRRSI_OP;
                id_reg_w_en = 1'b1;
                id_mem_w_en = 1'b0;
                id_mem_r_en = 1'b0;
                csr_w_en = csr_rs1_en;   
                is_branch = 1'b0;              
              end   
               `FUNCT3_CSRRCI:
              begin
                id_op_sel = `EXE_RES_LOGIC;
                id_func_sel = `EXE_CSRRCI_OP;
                id_reg_w_en = 1'b1;
                id_mem_w_en = 1'b0;
                id_mem_r_en = 1'b0;
                csr_w_en = csr_rs1_en;   
                is_branch = 1'b0;              
              end   
              //rcall and ebreak
                `FUNCT3_ECALL_EBREAK:
              begin
                if(I_imm == 12'h0 && func7 != `FUNCT7_MSET)
                begin
                  id_op_sel = `EXE_RES_LOGIC;
                  id_func_sel = `EXE_ECALL_OP;     
                  id_reg_w_en = 1'b0;
                  id_mem_w_en = 1'b0;
                  id_mem_r_en = 1'b0;
                  csr_w_en = 1'b0;    
                  is_branch = 1'b0;                
                end
                else if(I_imm == 12'h1 && func7 != `FUNCT7_MSET)
                begin
                  id_op_sel = `EXE_RES_LOGIC;
                  id_func_sel = `EXE_EBREAK_OP;
                  id_reg_w_en = 1'b0;
                  id_mem_w_en = 1'b0;
                  id_mem_r_en = 1'b0;
                  csr_w_en = 1'b0;    
                  is_branch = 1'b0; 
                end
                else if(func7 == `FUNCT7_MSET)
                begin
                  id_op_sel = `EXE_RES_LOGIC;
                  id_func_sel = `EXE_MRET_OP;
                  id_reg_w_en = 1'b0;
                  id_mem_w_en = 1'b0;
                  id_mem_r_en = 1'b0;
                  csr_w_en = 1'b0;  
                  is_branch = 1'b0;  
                end
                else
                begin
                  illegal_inst = 1'b1;
                  id_op_sel = `EXE_RES_NOP;
                  id_func_sel = `EXE_NOP_OP;
                  id_reg_w_en = 1'b0;
                  id_mem_w_en = 1'b0;
                  id_mem_r_en = 1'b0;
                  csr_w_en = 1'b0;   
                  is_branch = 1'b0; 
                end                
              end               

              default:
              begin
                illegal_inst = 1'b1;
                id_op_sel = `EXE_RES_NOP;
                id_func_sel = `EXE_NOP_OP;
                id_reg_w_en = 1'b0;
                id_mem_w_en = 1'b0;
                id_mem_r_en = 1'b0;
                csr_w_en = 1'b0; 
                is_branch = 1'b0; 
              end
            endcase
          end
          default:
          begin
            illegal_inst = 1'b1;
            id_op_sel = `EXE_RES_NOP;
            id_func_sel = `EXE_NOP_OP;
            id_reg_w_en = 1'b0;
            id_mem_w_en = 1'b0;
            id_mem_r_en = 1'b0;
            csr_w_en = 1'b0;
            is_branch = 1'b0;   
            load_store_word = 1'b0;
          end
      endcase

        

    end
end


  //立即数imm(除了U型指令外，其余类型指令RV32和RV64处理方法相同)
  wire  [XLEN-1:0] I_imm_ext = {{IMM_I_S{I_imm[11]}},I_imm};
  wire  [XLEN-1:0] S_imm_ext = {{IMM_I_S{S_imm[11]}},S_imm};
  wire  [XLEN-1:0] B_imm_ext = {{IMM_B{if_inst[31]}},B_imm};
  wire  [XLEN-1:0] U_imm_ext;
  wire  [XLEN-1:0] J_imm_ext = {{IMM_J{if_inst[31]}},J_imm};

  generate
    if(XLEN==64)
    begin
      assign U_imm_ext = {{32{U_imm[19]}},U_imm,{12{1'b0}}}; 
    end
    else
    begin
      assign U_imm_ext = {U_imm,{12{1'b0}}};
    end
  endgenerate

    always @(*) 
      begin
          case (opcode)
              `OP_LOAD, `OP_OP_IMM, `OP_OP_IMM_W, `OP_JALR: id_imm = I_imm_ext;
              `OP_STORE:  id_imm = S_imm_ext; 
              `OP_BRANCH: id_imm = B_imm_ext;
              `OP_LUI, `OP_AUIPC: id_imm = U_imm_ext;   
              `OP_JAL:    id_imm = J_imm_ext;
              `OP_MISC_MEM: id_imm = 4;
              `OP_SYSTEM: 
               begin
                if(func3 == `FUNCT3_CSRRWI ||  func3 == `FUNCT3_CSRRSI || func3 == `FUNCT3_CSRRCI )
                  id_imm = CSR_zimm; // CSR zimm
                else
                  id_imm = {XLEN{1'b0}};
               end
              default:    id_imm = {XLEN{1'b0}};
          endcase
    end


    //rs1_en,rs2_en独立判断

    assign  rs1_en = is_alu_w || is_alu || is_load || is_store || is_branch_op || is_jalr || csr_reg_op;
    assign  rs2_en = (opcode == `OP_OP_W) || (opcode == `OP_OP) || is_store || is_branch_op;

    //旁路模块对比地址
    assign rs1_addr = rs1_en ? rs1 : 5'h0;
    assign rs2_addr = rs2_en ? rs2 : 5'h0; 
    // =========================================================================
    // 根据译码出来的rs1_en(rs2_en)控制信号将rs1(rs2)或立即数传递给下一级
    // =========================================================================

    always @(*)
    begin
      if(rs1_en)
        id_rs1 = reg_rs1;
      else
        id_rs1 = id_imm;
    end


    always @(*)
    begin
      if(rs2_en)
        id_rs2 = reg_rs2;
      else
        id_rs2 = id_imm;
    end

endmodule
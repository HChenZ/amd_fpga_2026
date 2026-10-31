`ifndef DEFINES_V
`define DEFINES_V



// =========================================================================
// Hardware Properties
// =========================================================================  
// 参数配置
`define XLEN 32             //RV32/RV64切换
`define RAM_DEPTH 32768     //RAM深度
`define INDEX_WIDTH 6       //分支预测器表项数�?4 项表 (2^6)�?
// =========================================================================
// Instruction opcode in RISC-V
// =========================================================================  
//================== RV32 ================== 
`define OP_LUI      7'b0110111
`define OP_AUIPC    7'b0010111
`define OP_JAL      7'b1101111
`define OP_JALR     7'b1100111
`define OP_BRANCH   7'b1100011
`define OP_LOAD     7'b0000011
`define OP_STORE    7'b0100011
`define OP_OP_IMM   7'b0010011
`define OP_OP       7'b0110011
`define OP_MISC_MEM 7'b0001111
`define OP_SYSTEM   7'b1110011
`define OP_ASCON    7'b0001011   // custom-0: Ascon permutation ISE

//================== RV64 ================== 
`define OP_OP_IMM_W 7'b0011011
`define OP_OP_W     7'b0111011

// =========================================================================
// Instruction funct3 in RISC-V 
// =========================================================================  

//================== RV32 ================== 
// JALR
`define FUNCT3_JALR 3'b000
// BRANCH
`define FUNCT3_BEQ  3'b000
`define FUNCT3_BNE  3'b001
`define FUNCT3_BLT  3'b100
`define FUNCT3_BGE  3'b101
`define FUNCT3_BLTU 3'b110
`define FUNCT3_BGEU 3'b111
// LOAD
`define FUNCT3_LB   3'b000
`define FUNCT3_LH   3'b001
`define FUNCT3_LW   3'b010
`define FUNCT3_LBU  3'b100
`define FUNCT3_LHU  3'b101
// STORE
`define FUNCT3_SB   3'b000
`define FUNCT3_SH   3'b001
`define FUNCT3_SW   3'b010
// OP-IMM
`define FUNCT3_ADDI      3'b000
`define FUNCT3_SLTI      3'b010
`define FUNCT3_SLTIU     3'b011
`define FUNCT3_XORI      3'b100
`define FUNCT3_ORI       3'b110
`define FUNCT3_ANDI      3'b111
`define FUNCT3_SLLI      3'b001
`define FUNCT3_SRLI_SRAI 3'b101
// OP
`define FUNCT3_ADD_SUB 3'b000
`define FUNCT3_SLL     3'b001
`define FUNCT3_SLT     3'b010
`define FUNCT3_SLTU    3'b011
`define FUNCT3_XOR     3'b100
`define FUNCT3_SRL_SRA 3'b101
`define FUNCT3_OR      3'b110
`define FUNCT3_AND     3'b111
// MISC-MEM
`define FUNCT3_FENCE  3'b000
`define FUNCT3_FENCEI 3'b001
// SCR
`define FUNCT3_CSRRW  3'b001
`define FUNCT3_CSRRS 3'b010
`define FUNCT3_CSRRC  3'b011
`define FUNCT3_CSRRWI 3'b101
`define FUNCT3_CSRRSI  3'b110
`define FUNCT3_CSRRCI 3'b111
// SYSTEM
`define FUNCT3_ECALL_EBREAK 3'b000

// ASCON ISE (custom-0 opcode, func3 selects the operation)
`define FUNCT3_ASCON_W    3'b000   // state word write
`define FUNCT3_ASCON_RD   3'b001   // state word read
`define FUNCT3_ASCON_P12  3'b010   // P12 permutation
`define FUNCT3_ASCON_P8   3'b011   // P8 permutation

//Multiply
`define FUNCT3_MUL 3'b000
`define FUNCT3_MULH 3'b001
`define FUNCT3_MULHSU 3'b010
`define FUNCT3_MULHU 3'b011
`define FUNCT3_DIV 3'b100
`define FUNCT3_DIVU 3'b101
`define FUNCT3_REM 3'b110
`define FUNCT3_REMU 3'b111

//================== RV64 ================== 
`define FUNCT3_MULW  3'b000
`define FUNCT3_DIVW  3'b100
`define FUNCT3_DIVUW 3'b101
`define FUNCT3_REMW  3'b110
`define FUNCT3_REMUW 3'b111

`define FUNCT3_LWU   3'b110
`define FUNCT3_LD    3'b011
`define FUNCT3_SD    3'b011

// =========================================================================
// Instruction funct7 in RISC-V 
// =========================================================================  
`define FUNCT7_SLLI 7'b0000000
// SRLI_SRAI
`define FUNCT7_SRLI 7'b0000000
`define FUNCT7_SRAI 7'b0100000
// ADD_SUB
`define FUNCT7_ADD  7'b0000000
`define FUNCT7_SUB  7'b0100000
`define FUNCT7_SLL  7'b0000000
`define FUNCT7_SLT  7'b0000000
`define FUNCT7_SLTU 7'b0000000
`define FUNCT7_XOR  7'b0000000
// SRL_SRA
`define FUNCT7_SRL 7'b0000000  
`define FUNCT7_SRA 7'b0100000
`define FUNCT7_OR  7'b0000000
`define FUNCT7_AND 7'b0000000

// SYSTEM
`define FUNCT7_MSET 7'b0011000

//Multiply
`define FUNCT7_MULTIPLY 7'b0000001

// =========================================================================
// AluSel
// =========================================================================  
`define EXE_RES_LOGIC       3'b001
`define EXE_RES_SHIFT       3'b010
`define EXE_RES_MOVE        3'b011
`define EXE_RES_NOP         3'b000
`define EXE_RES_ARITH       3'b100
`define EXE_RES_MUL         3'b101
`define EXE_RES_JUMP_BRANCH 3'b110
`define EXE_RES_LOAD_STORE  3'b111

// =========================================================================
// ALU_OP
// =========================================================================  

//================== RV32 ================== 
`define EXE_NOP_OP 6'd0
`define EXE_AND_OP 6'd1
`define EXE_OR_OP  6'd2
`define EXE_XOR_OP 6'd3

`define EXE_SLL_OP 6'd5
`define EXE_SRL_OP 6'd6
`define EXE_SRA_OP 6'd7

`define EXE_ADD_OP  6'd8
`define EXE_SLT_OP  6'd9
`define EXE_SLTU_OP 6'd10
`define EXE_SUB_OP  6'd11

`define EXE_JAL_OP  6'd12
`define EXE_JALR_OP 6'd13
`define EXE_BEQ_OP  6'd14
`define EXE_BNE_OP  6'd15
`define EXE_BLT_OP  6'd16
`define EXE_BGE_OP  6'd17
`define EXE_BLTU_OP 6'd18
`define EXE_BGEU_OP 6'd19

`define EXE_LB_OP  6'd20
`define EXE_LH_OP  6'd21
`define EXE_LW_OP  6'd22
`define EXE_LBU_OP 6'd23
`define EXE_LHU_OP 6'd24
`define EXE_SB_OP  6'd25
`define EXE_SH_OP  6'd26
`define EXE_SW_OP  6'd27
`define EXE_LUI_OP 6'd28
`define EXE_AUIPC_OP 6'd29

`define EXE_CSRRW_OP 6'd30
`define EXE_CSRRS_OP 6'd31
`define EXE_CSRRC_OP 6'd32
`define EXE_CSRRWI_OP 6'd33
`define EXE_CSRRSI_OP 6'd34
`define EXE_CSRRCI_OP 6'd35

`define EXE_ECALL_OP 6'd36
`define EXE_EBREAK_OP 6'd37
`define EXE_MRET_OP 6'd38

//M 拓展
`define EXE_MUL_OP 6'd39
`define EXE_MULH_OP 6'd40
`define EXE_MULHSU_OP 6'd41
`define EXE_MULHU_OP 6'd42
`define EXE_DIV_OP 6'd43
`define EXE_DIVU_OP 6'd44
`define EXE_REM_OP 6'd45
`define EXE_REMU_OP 6'd46

//================== RV64 ================== 
`define EXE_ADDW_OP 6'd47
`define EXE_SUBW_OP 6'd48
`define EXE_SLLW_OP 6'd49
`define EXE_SRLW_OP 6'd50
`define EXE_SRAW_OP 6'd51
`define EXE_SD_OP 6'd52
`define EXE_LD_OP 6'd53
`define EXE_LWU_OP 6'd54

`define EXE_MULW_OP 6'd55
`define EXE_DIVW_OP 6'd56
`define EXE_DIVUW_OP 6'd57
`define EXE_REMW_OP 6'd58
`define EXE_REMUW_OP 6'd59

// Ascon ISE (custom-0)
`define EXE_ASCON_W_OP   6'd60
`define EXE_ASCON_RD_OP  6'd61
`define EXE_ASCON_P12_OP 6'd62
`define EXE_ASCON_P8_OP  6'd63





`endif


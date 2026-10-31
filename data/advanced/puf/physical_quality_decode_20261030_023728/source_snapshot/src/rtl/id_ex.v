`timescale 1ns / 1ps
(* dont_touch = "true" *)module id_ex #(
    parameter XLEN = 32
)(
    input                   clk,
    input                   rst_n,

    input       [XLEN-1:0]  pc_i,
    input       [XLEN-1:0]  rs1_i,
    input       [XLEN-1:0]  rs2_i,   
    input       [2:0]       op_sel_i,
    input       [5:0]       func_sel_i,
    input       [4:0]       w_reg_waddr_i,   
    input                   reg_w_en_i,
    input                   mem_w_en_i,
    input                   mem_r_en_i,   
    input       [XLEN-1:0]  imm_i,
    input                   csr_w_en_i,
    input       [11:0]      csr_addr_i,
    input                   is_branch_i,
    input                   illegal_inst_en_i,
    input       [31:0]      inst_i,
    input                   is_word_op_i,

    input                   inst_valid_i,
    output  reg             inst_valid_o,

    //from inst_mem
    input                   pred_taken_i,
    input       [XLEN-1:0]  pred_target_i,

    //from ctrl
    input                   stall,
    input                   flush,



    //旁路模块信号
    input                   sel_ex_mem_rs1_i,
    input                   sel_mem_wb_rs1_i,
    input                   sel_ex_mem_rs2_i,
    input                   sel_mem_wb_rs2_i,

    output  reg             sel_ex_mem_rs1_o,
    output  reg             sel_mem_wb_rs1_o,
    output  reg             sel_ex_mem_rs2_o,
    output  reg             sel_mem_wb_rs2_o,

    //to ex stage
 (* max_fanout = 16 *)   output  reg [XLEN-1:0]  pc_o,
 (* max_fanout = 16 *)   output  reg [XLEN-1:0]  rs1_o,
 (* max_fanout = 16 *)   output  reg [XLEN-1:0]  rs2_o, 
 (* max_fanout = 16 *)   output  reg [XLEN-1:0]  imm_o,  
    output  reg [2:0]       op_sel_o,
    output  reg [5:0]       func_sel_o,
    output  reg [4:0]       w_reg_waddr_o,    
    output  reg             reg_w_en_o,
    output  reg             mem_w_en_o,
    output  reg             mem_r_en_o,
    output  reg             csr_w_en_o,
    output  reg [11:0]      csr_addr_o,

    output  reg             is_branch_o,
    output  reg             pred_taken_o,
    output  reg [XLEN-1:0]  pred_target_o,
    output  reg             illegal_inst_en_o,
    output  reg [31:0]      inst_o,
    output  reg             is_word_op_o

);


    reg             pred_taken_clean;
    reg [XLEN-1:0] pred_target_clean;

    always @(*)
    begin
      pred_taken_clean = pred_taken_i;
      pred_target_clean = pred_taken_i ? pred_target_i : {XLEN{1'b0}};

      // synthesis translate_off
      if ((pred_taken_i !== 1'b1) || ((^pred_target_i) === 1'bx))
      begin
        pred_taken_clean = 1'b0;
        pred_target_clean = {XLEN{1'b0}};
      end
      // synthesis translate_on
    end


    always @(posedge clk or negedge rst_n)
    begin
      if(!rst_n)
      begin
        rs1_o <= {XLEN{1'b0}}; 
        rs2_o <= {XLEN{1'b0}}; 
        pc_o <= {XLEN{1'b0}};       
        op_sel_o <= 3'h0;
        func_sel_o <= 6'h0;
        w_reg_waddr_o <= 5'h0;       
        reg_w_en_o <= 1'b0;
        mem_w_en_o <= 1'b0;
        mem_r_en_o <= 1'b0;        
        imm_o <= {XLEN{1'b0}};
        csr_w_en_o <= 1'b0;    
        pred_taken_o <= 1'b0;
        pred_target_o <= {XLEN{1'b0}};  
        is_branch_o <= 1'b0;
        illegal_inst_en_o <= 1'b0;
        sel_ex_mem_rs1_o <= 1'b0;
        sel_mem_wb_rs1_o <= 1'b0;
        sel_ex_mem_rs2_o <= 1'b0;
        sel_mem_wb_rs2_o <= 1'b0;
        inst_o <= 32'h00000013;
        is_word_op_o <= 1'b0;
        inst_valid_o <= 0;
        csr_addr_o <= 12'h0;
      end
      else if(flush)
      begin
        op_sel_o <= 3'h0;
        func_sel_o <= 6'h0;
        w_reg_waddr_o <= 5'h0;       
        reg_w_en_o <= 1'b0;
        mem_w_en_o <= 1'b0;
        mem_r_en_o <= 1'b0;        
        csr_w_en_o <= 1'b0;
        pred_taken_o <= 1'b0;
        pred_target_o <= {XLEN{1'b0}};
        is_branch_o <= 1'b0;
        illegal_inst_en_o <= 1'b0;  
        inst_o <= 32'h00000013;
        sel_ex_mem_rs1_o <= 1'b0;
        sel_mem_wb_rs1_o <= 1'b0;
        sel_ex_mem_rs2_o <= 1'b0;
        sel_mem_wb_rs2_o <= 1'b0;   
        is_word_op_o <= 1'b0;
        inst_valid_o <= 0;
      end 
      else if(stall)
      begin
        rs1_o <= rs1_o;
        rs2_o <= rs2_o;
        pc_o <= pc_o;           
        op_sel_o <= op_sel_o;
        func_sel_o <= func_sel_o;
        w_reg_waddr_o <= w_reg_waddr_o;         
        reg_w_en_o <= reg_w_en_o;
        mem_w_en_o <= mem_w_en_o;
        mem_r_en_o <= mem_r_en_o;        
        imm_o <= imm_o;   
        csr_w_en_o <= csr_w_en_o; 
        pred_taken_o <= pred_taken_o;
        pred_target_o <= pred_target_o;   
        is_branch_o <= is_branch_o;
        illegal_inst_en_o <= illegal_inst_en_o;   
        sel_ex_mem_rs1_o <= sel_ex_mem_rs1_o;
        sel_mem_wb_rs1_o <= sel_mem_wb_rs1_o;
        sel_ex_mem_rs2_o <= sel_ex_mem_rs2_o;
        sel_mem_wb_rs2_o <= sel_mem_wb_rs2_o;
        inst_o <= inst_o;
        is_word_op_o <= is_word_op_o;
        inst_valid_o <= inst_valid_o;
        csr_addr_o <= csr_addr_o;
      end
      else
      begin
        rs1_o <= rs1_i;
        rs2_o <= rs2_i;
        pc_o <= pc_i;           
        op_sel_o <= op_sel_i;
        func_sel_o <= func_sel_i;
        w_reg_waddr_o <= w_reg_waddr_i;         
        reg_w_en_o <= reg_w_en_i;
        mem_w_en_o <= mem_w_en_i;
        mem_r_en_o <= mem_r_en_i;        
        imm_o <= imm_i;   
        csr_w_en_o <= csr_w_en_i;   
        pred_taken_o <= pred_taken_clean;
        pred_target_o <= pred_target_clean;
        is_branch_o <= is_branch_i;
        illegal_inst_en_o <= illegal_inst_en_i;  
        sel_ex_mem_rs1_o <= sel_ex_mem_rs1_i;
        sel_mem_wb_rs1_o <= sel_mem_wb_rs1_i;
        sel_ex_mem_rs2_o <= sel_ex_mem_rs2_i;
        sel_mem_wb_rs2_o <= sel_mem_wb_rs2_i;
        inst_o <= inst_i;     
        is_word_op_o <= is_word_op_i;     
        inst_valid_o <= inst_valid_i;
        csr_addr_o <= csr_addr_i;
      end
    end


endmodule

`timescale 1ns / 1ps
(* dont_touch = "true" *)module ex_mem #(
    parameter XLEN = 32
) (
    input               clk,
    input               rst_n,



    input               ex_reg_w_en_i,
    input               ex_mem_w_en_i,
    input   [XLEN-1:0]      ex_rd_data_i,
    input   [XLEN-1:0]  ex_mem_addr_i,
    input   [4:0]       ex_reg_addr_i,
    input   [2:0]       ex_op_sel_i,
    input   [5:0]       ex_func_sel_i,
    input               ex_mem_r_en_i,
    input               ex_is_mul_i,

    input               inst_valid_i,
    output  reg         inst_valid_o,

    //from ctrl
    input               flush,
    input               stall,

    //to MEM
    output  reg              ex_reg_w_en_o,
    output  reg              ex_mem_w_en_o,
    output  reg  [XLEN-1:0]      ex_rd_data_o,
    output  reg  [XLEN-1:0]  ex_mem_addr_o,
    output  reg  [4:0]       ex_reg_addr_o,
    output  reg  [2:0]       ex_op_sel_o,
    output  reg  [5:0]       ex_func_sel_o,
    output  reg              ex_mem_r_en_o,
    output  reg              ex_is_mul_o



);




    always @(posedge clk or negedge rst_n)
    begin
      if(!rst_n)
      begin
        ex_reg_w_en_o <= 1'b0;
        ex_mem_w_en_o <= 1'b0;
        ex_rd_data_o <= {XLEN{1'b0}};
        ex_mem_addr_o <= {XLEN{1'b0}};
        ex_reg_addr_o <= 5'h0;
        ex_op_sel_o <= 3'h0;
        ex_func_sel_o <= 6'h0;
        ex_mem_r_en_o <= 1'b0;
        ex_is_mul_o   <= 1'b0;
        inst_valid_o <= 0;
      end
      else if(flush)
      begin
        ex_reg_w_en_o <= 1'b0;
        ex_mem_w_en_o <= 1'b0;
        ex_reg_addr_o <= 5'h0;
        ex_op_sel_o <= 3'h0;
        ex_func_sel_o <= 6'h0;
        ex_mem_r_en_o <= 1'b0;
        ex_is_mul_o   <= 1'b0;
        inst_valid_o <= 0;
      end
      else if(stall)
      begin
        ex_reg_w_en_o <= ex_reg_w_en_o;
        ex_mem_w_en_o <= ex_mem_w_en_o;
        ex_rd_data_o  <= ex_rd_data_o;
        ex_mem_addr_o <= ex_mem_addr_o;
        ex_reg_addr_o <= ex_reg_addr_o;
        ex_op_sel_o   <= ex_op_sel_o;
        ex_func_sel_o <= ex_func_sel_o;
        ex_mem_r_en_o <= ex_mem_r_en_o;
        ex_is_mul_o   <= ex_is_mul_o;
        inst_valid_o  <= inst_valid_o;
      end
      else
      begin
        ex_reg_w_en_o <= ex_reg_w_en_i;
        ex_mem_w_en_o <= ex_mem_w_en_i;
        ex_rd_data_o <= ex_rd_data_i;
        ex_mem_addr_o <= ex_mem_addr_i;
        ex_reg_addr_o <= ex_reg_addr_i;
        ex_op_sel_o <= ex_op_sel_i;
        ex_func_sel_o <= ex_func_sel_i;
        ex_mem_r_en_o <= ex_mem_r_en_i;
        ex_is_mul_o   <= ex_is_mul_i;
        inst_valid_o <= inst_valid_i;
      end
    end


endmodule

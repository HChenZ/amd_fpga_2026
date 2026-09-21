`timescale 1ns / 1ps
module mem_wb #(
    parameter XLEN = 32
) (
    input                     clk,
    input                     rst_n,
    input                     stall,


    input                    ex_reg_w_en_i,
    input        [XLEN-1:0]  ex_rd_data_i,
    input        [4:0]       ex_reg_addr_i,
    input        [2:0]       ex_op_sel_i,
    input                    ex_is_mul_i,

    input                    inst_valid_i,
    output  reg              inst_valid_o,

    //to regfile
    output  reg               mem_reg_w_en_o,
    output  reg  [XLEN-1:0]   mem_rd_data_o,
    output  reg  [4:0]        mem_reg_addr_o,
    output  reg  [2:0]        mem_op_sel_o,
    output  reg               mem_is_mul_o
 
);

    always@ (posedge clk or negedge rst_n)
    begin
      if(!rst_n)
      begin
        mem_reg_w_en_o <= 0;
        mem_rd_data_o <= {XLEN{1'b0}};
        mem_reg_addr_o <= 5'h0;
        mem_op_sel_o  <= 3'h0;
        mem_is_mul_o  <= 1'b0;
        inst_valid_o   <= 0;
      end
      else if (stall)
      begin
        // hold
      end
      else
      begin
        mem_reg_w_en_o <= ex_reg_w_en_i;
        mem_rd_data_o <= ex_rd_data_i;
        mem_reg_addr_o <= ex_reg_addr_i;
        mem_op_sel_o  <= ex_op_sel_i;
        mem_is_mul_o  <= ex_is_mul_i;
        inst_valid_o   <= inst_valid_i;
      end
    end



endmodule
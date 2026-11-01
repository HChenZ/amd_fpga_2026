`timescale 1ns / 1ps
module if_stage #(
   parameter XLEN = 32
)
( 
    input                       clk,
    input                       rst_n,

    //from ctrl
    input                       stall,
    input       [1:0]           jump_sel,
                   
    //from branch predictor
    input                       pred_taken,   //分支预测跳转发生
    input       [XLEN-1:0]      pred_target,  //分支预测跳转地址

    //from ex stage
    input       [XLEN-1:0]      ex_pc_shift,  //实际分支跳转地址

    //from scr file
    input       [XLEN-1:0]      mtvec_pc,
    input       [XLEN-1:0]      mepc_pc,

    //to imem
    output reg  [XLEN-1:0]      pc
);                        
 

 //jump_sel信号选择，包括pc+4；分支跳转 ； Trap ; Mset
 parameter PC_PLUS_4 = 2'b00; 
 parameter BRANCH = 2'b01; 
 parameter TRAP = 2'b10; 
 parameter MSET = 2'b11;  

always @(posedge clk or negedge rst_n) 
begin 
    if(!rst_n)
        pc  <= 32'h1000_0000;
    else
    begin 
        if(jump_sel == TRAP)
          pc <= mtvec_pc;
        else if(jump_sel == BRANCH) 
          pc <= ex_pc_shift; 
        else if(jump_sel == MSET)
          pc <= mepc_pc;
        else if(stall)
          pc <= pc; 
        else if(pred_taken)
          pc <= pred_target;
        else
          pc <= pc + 4;        
    end 
end 
 


endmodule
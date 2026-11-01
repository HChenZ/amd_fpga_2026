`timescale 1ns / 1ps
module regfile#(
    parameter XLEN = 32
)(
    input                   clk,
    input                   rst_n,

    //from id stage
    input      [4:0]        w_reg_addr,
    input      [4:0]        r_reg_addr1,
    input      [4:0]        r_reg_addr2,
    input      [XLEN-1:0]   w_reg_data,
    input                   w_reg_en,

    //to id stage
    output reg [XLEN-1:0]   reg_rs1,
    output reg [XLEN-1:0]   reg_rs2

);

(* ram_style = "distributed" *)    reg [XLEN-1:0] registers [0:31];

    // =========================================================================
    // 寄存器堆写逻辑(同步写)
    // =========================================================================    
    integer i;
    always @(posedge clk)
    begin
      if(w_reg_en && w_reg_addr != 5'h0) 
        registers[w_reg_addr] <= w_reg_data;
    end


    // =========================================================================
    // 寄存器堆读逻辑(异步读)
    // ========================================================================= 

    //rs1
    always @(*)
    begin
      if(r_reg_addr1 == 5'h0)
        reg_rs1 = {XLEN{1'b0}}; 
      else if(w_reg_en && (r_reg_addr1 == w_reg_addr))
        reg_rs1 = w_reg_data;
      else
        reg_rs1 = registers[r_reg_addr1];   
    end

    //rs2
    always @(*)
    begin
      if(r_reg_addr2 == 5'h0)
        reg_rs2 = {XLEN{1'b0}}; 
      else if(w_reg_en && (r_reg_addr2 == w_reg_addr))
        reg_rs2 = w_reg_data;
      else
        reg_rs2 = registers[r_reg_addr2];   
    end


endmodule
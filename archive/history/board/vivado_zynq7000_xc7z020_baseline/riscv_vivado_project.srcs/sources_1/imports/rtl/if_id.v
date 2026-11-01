`timescale 1ns / 1ps
module if_id #(
   parameter XLEN = 32)
(

    input                   clk,
    input                   rst_n,

    //from imem (mem端口A输出，冯诺依曼结构，永远是正确指令)
    input       [31:0]      imem_inst_i,

    //from predictor
    input                   pred_taken_i,
    input       [XLEN-1:0]  pred_target_i,

    //from ctrl
    input                   flush,
    input                   stall,

    //from if_stage
    input       [XLEN-1:0]  pc,

    //to ctrl
 (* max_fanout = 10 *)    output reg  [4:0]       rs1_addr,
 (* max_fanout = 10 *)    output reg  [4:0]       rs2_addr,
    output                  rs1_en,
    output                  rs2_en,

    output reg  [31:0]      if_inst_o,
    //to ex
    output reg              pred_taken_o,
    output reg  [XLEN-1:0]  pred_target_o,
    output reg  [XLEN-1:0]  if_pc_o,
(* max_fanout = 14 *)    output      [6:0]       opcode,

    output reg              inst_valid
);


    //提前译码opcode防止高扇出
    assign opcode = if_inst_o[6:0];

    reg         flush_reg;
    reg         stall_reg;
    reg [31:0]  stall_inst_reg;

    wire [4:0] rs1_imem = imem_inst_i[19:15];
    wire [4:0] rs2_imem = imem_inst_i[24:20];

    always @(*)
    begin
      if(!rst_n || flush_reg)
      begin
        if_inst_o = 32'h00000013;
        rs1_addr = 5'h0;
        rs2_addr = 5'h0;
      end
      else if(stall_reg)
      begin
        if_inst_o = stall_inst_reg;
        rs1_addr = stall_inst_reg[19:15];
        rs2_addr = stall_inst_reg[24:20];
      end
      else
      begin
        if_inst_o = imem_inst_i;
        rs1_addr = rs1_imem;
        rs2_addr = rs2_imem;
      end
    end

    // =========================================================================
    // 除了inst信号外的信号寄存之后传给下一级
    // =========================================================================
    always @(posedge clk or negedge rst_n)
    begin
      if(~rst_n)
      begin
        if_pc_o <= {XLEN{1'b0}};
        pred_taken_o <= 1'b0;
        pred_target_o <= {XLEN{1'b0}};
        flush_reg <= 1'b0;
        stall_reg <= 1'b0;
        stall_inst_reg <= 32'h00000013;
        inst_valid <= 0;
      end
      else if(flush)
      begin
        if_pc_o <=  {XLEN{1'b0}};
        pred_taken_o <= 1'b0;
        pred_target_o <= {XLEN{1'b0}};
        flush_reg <= 1'b1;
        stall_reg <= 1'b0;
        inst_valid <= 0;
      end
      else if(~stall)
      begin
        if_pc_o <=  pc;
        pred_taken_o <= pred_taken_i;
        pred_target_o <= pred_target_i;
        flush_reg <= 1'b0;
        stall_reg <= 1'b0;
        inst_valid <= 1;
      end
      else
      begin
        flush_reg <= 1'b0;
        stall_reg <= 1'b1;
        stall_inst_reg <= if_inst_o;
        inst_valid <= 0;
      end
    end

    // 此处属于时序优化:将原本id_stage中的逻辑前移到本模块，用于送给ctrl模块做流水线控制判断
    wire [6:0] oc  = if_inst_o[6:0];
    wire [2:0] f3  = if_inst_o[14:12];
    assign rs1_en = (oc == 7'b0111011) || (oc == 7'b0011011) ||
                    (oc == 7'b0110011) || (oc == 7'b0010011) ||
                    (oc == 7'b0000011) || (oc == 7'b0100011) ||
                    (oc == 7'b1100011) || (oc == 7'b1100111) ||
                    (oc == 7'b1110011 && (f3 == 3'b001 || f3 == 3'b010 || f3 == 3'b011));

    assign rs2_en = (oc == 7'b0111011) || (oc == 7'b0110011) ||
                    (oc == 7'b0100011) || (oc == 7'b1100011);

endmodule

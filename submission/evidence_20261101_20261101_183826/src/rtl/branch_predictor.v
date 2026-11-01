`timescale 1ns / 1ps
(* dont_touch = "true" *)module predictor #(
    parameter XLEN = 32,
    parameter INDEX_WIDTH = 6 // 64 项表 (2^6)
)(
    input               clk,
    input               rst_n,

    // ================= IF 阶段：预测接口 =================
    input   [XLEN-1:0]  pc_if,           // 当前正在取指的 PC
    output              pred_taken,      // 预测是否跳转？(1:跳, 0:不跳)
    output  [XLEN-1:0]  pred_target,     // 预测跳去哪里？

    // ================= EX 阶段：更新接口 (裁判) =================
    input               update_en,       // 是否有分支指令到达了 EX 阶段？
    input   [XLEN-1:0]  pc_ex,           // 到达 EX 阶段的这条分支指令的 PC
    input               actual_taken,    // 实际是否跳了？
    input   [XLEN-1:0]  actual_target    // 实际跳去哪里了？
);

    // 计算 Tag 的位宽 (XLEN - 2位对齐 - Index位宽)
    localparam TAG_WIDTH = XLEN - 2 - INDEX_WIDTH;
    localparam DEPTH     = (1<<INDEX_WIDTH);

     // 定义存储表 (64 项)
    // Tag / BTB 表：用 Distributed RAM 存储
    // 2-bit 状态: 00(强不跳), 01(弱不跳), 10(弱跳), 11(强跳)
    (* ram_style = "distributed" *) reg [TAG_WIDTH-1:0] tag_table [0:DEPTH-1];
    (* ram_style = "distributed" *) reg [XLEN-1:0]      btb_table [0:DEPTH-1];
    reg [1:0] bht_table [0:DEPTH-1];

    // Valid 表：打包寄存器，便于整体 reset
    reg [DEPTH-1:0] valid_table;

    // 截取 PC 的中间几位作为 Index (因为指令是 4 字节对齐，最低 2 位永远是 0)
    wire [INDEX_WIDTH-1:0] read_idx  = pc_if [INDEX_WIDTH+1 : 2];
    wire [TAG_WIDTH-1:0]   read_tag  = pc_if [XLEN-1 : INDEX_WIDTH+2];

    wire [INDEX_WIDTH-1:0] write_idx = pc_ex [INDEX_WIDTH+1 : 2];
    wire [TAG_WIDTH-1:0]   write_tag = pc_ex [XLEN-1 : INDEX_WIDTH+2];

    wire tag_match = (tag_table[read_idx] == read_tag);

    // ---------------------------------------------------------
    // 预测逻辑 (组合逻辑，0 延迟给 IF 阶段用)
    // ---------------------------------------------------------
    assign pred_taken  = valid_table[read_idx] && tag_match && (bht_table[read_idx] >= 2'b10);
    assign pred_target = btb_table[read_idx];

    // ---------------------------------------------------------
    // tag_table / btb_table 写入逻辑
    // ---------------------------------------------------------
    always @(posedge clk)
    begin
        if (update_en)
        begin
            tag_table[write_idx] <= write_tag;
            if (actual_taken)
                btb_table[write_idx] <= actual_target;
        end
    end

    // ---------------------------------------------------------
    // bht_table 更新：饱和计数器逻辑
    // ---------------------------------------------------------
    integer i;
    always @(posedge clk or negedge rst_n)
    begin
        if (!rst_n)
        begin
            for (i = 0; i < DEPTH; i = i + 1)
                bht_table[i] <= 2'b01; // 默认弱不跳 (Weakly Not Taken)
        end
        else if (update_en)
        begin
            case (bht_table[write_idx])
                2'b00: bht_table[write_idx] <= actual_taken ? 2'b01 : 2'b00;
                2'b01: bht_table[write_idx] <= actual_taken ? 2'b10 : 2'b00;
                2'b10: bht_table[write_idx] <= actual_taken ? 2'b11 : 2'b01;
                2'b11: bht_table[write_idx] <= actual_taken ? 2'b11 : 2'b10;
            endcase
        end
    end

    // ---------------------------------------------------------
    // valid_table 复位逻辑
    // ---------------------------------------------------------
    always @(posedge clk or negedge rst_n)
    begin
        if (!rst_n)
            valid_table <= {DEPTH{1'b0}};
        else if (update_en)
            valid_table[write_idx] <= 1'b1;
    end

endmodule

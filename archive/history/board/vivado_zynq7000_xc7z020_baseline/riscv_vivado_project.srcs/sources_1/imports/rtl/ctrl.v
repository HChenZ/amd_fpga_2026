`timescale 1ns / 1ps
module stall_ctrl(
    //from id stage
    input   [4:0]       rs1_addr,
    input   [4:0]       rs2_addr,   
    input               rs1_en,
    input               rs2_en,

    //from id_ex
    input   [4:0]       id_ex_reg_addr,
    input               id_ex_mem_r_en,

    //from ex_mem
    input   [4:0]       ex_mem_mem_reg_addr,
    input               ex_mem_mem_r_en,

    //from ex stage
    input               jump_en,
    input               jump_trap_en,
    input               jump_trap_out,
    input               ex_stall_req,

    //中断请求
    input               inter_req,

    //from icache
    input               icache_stall,

    //from dcache
    input               dcache_stall,
    input               dmem_axi_stall_req,

    //fence.i pause
    input               fence_i_stall,


    //to icache
    output              icache_flush,

    // 5-bit 流水线控制：stall/flush[4:0] = {IF, IF/ID, ID/EX, EX/MEM, MEM/WB}
    output  reg [4:0]   stall,
    output  reg [4:0]   flush,

    //to if stage
    output  reg [1:0]   jump_sel,

    output              stall_ld,
    output              stall_md,
    output              flush_br
);

    // =========================================================================
    // 冒险检测 (Hazard Detection)
    // =========================================================================   
    // 计算内存读有效，并过滤掉 x0 寄存器
    wire mem_rd_valid_1st = id_ex_mem_r_en  && (id_ex_reg_addr != 5'h0);
    wire mem_rd_valid_2st = ex_mem_mem_r_en && (ex_mem_mem_reg_addr != 5'h0);

    wire rs1_hit_1st = mem_rd_valid_1st && (id_ex_reg_addr == rs1_addr);
    wire rs2_hit_1st = mem_rd_valid_1st && (id_ex_reg_addr == rs2_addr);
    
    wire rs1_hit_2st = mem_rd_valid_2st && (ex_mem_mem_reg_addr == rs1_addr);
    wire rs2_hit_2st = mem_rd_valid_2st && (ex_mem_mem_reg_addr == rs2_addr);

    // EX 直驱 RAM：load 在 EX 阶段提前访问内存，数据提前一拍到达 mem_wb，无需额外停顿
    wire early_rs1_hazard = rs1_hit_1st;
    wire early_rs2_hazard = rs2_hit_1st;


    wire load_use_rs1 = rs1_en && early_rs1_hazard;
    wire load_use_rs2 = rs2_en && early_rs2_hazard;

    assign stall_ld = load_use_rs1 || load_use_rs2;
    assign stall_md = ex_stall_req;
    assign flush_br = jump_en;

    // =========================================================================
    // I-Cache 重定向信号（组合，用于中止填充）
    // =========================================================================
    assign icache_flush = jump_en || jump_trap_en || jump_trap_out || inter_req;

    // =========================================================================
    // 流水线冲刷控制逻辑（单点决策，5 位信号统一控制五级流水线）
    // =========================================================================
    always @(*)
    begin
        stall      = 5'b00000;
        flush      = 5'b00000;
        jump_sel   = 2'b00;

        if (inter_req || jump_trap_en)
        begin
            flush[3:1] = 3'b111;   // IF/ID, ID/EX, EX/MEM
            jump_sel   = 2'b10;
        end
        else if (jump_trap_out)
        begin
            flush[3:1] = 3'b111;   // IF/ID, ID/EX, EX/MEM
            jump_sel   = 2'b11;
        end
        else if (dcache_stall)
        begin
            stall = 5'b11111;      // 全流水线停顿
        end
        else if (dmem_axi_stall_req)
        begin
            stall = 5'b11111;      // store wait: hold the whole pipeline
        end
        else if (ex_stall_req)
        begin
            // 多周期指令：暂停前端，冲刷 EX/MEM（该拍 EX 结果无效）
            stall[4:2] = 3'b111;   // IF, IF/ID, ID/EX
            flush[1]   = 1'b1;     // EX/MEM
        end
        else if (jump_en)
        begin
            flush[3:2] = 2'b11;    // IF/ID, ID/EX
            jump_sel   = 2'b01;
        end
        else if (load_use_rs1 || load_use_rs2)
        begin
            // Load-Use 惩罚：ID/EX 插气泡，暂停前端取指
            flush[2]   = 1'b1;     // ID/EX
            stall[4:3] = 2'b11;    // IF, IF/ID
        end
        else if (icache_stall || fence_i_stall)
        begin
            // I-Cache Miss：冲刷 IF/ID 排空错误路径指令，暂停 PC，后端自然排空
            stall[4:3] = 2'b11;    // IF, IF/ID
            flush[2]   = 1'b1;     // ID/EX
        end

    end

endmodule

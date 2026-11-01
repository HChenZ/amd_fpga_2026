`timescale 1ns / 1ps
//=============================================================================
// tb_dcache_trace.v —— dcache 差分激励（对照 vs TIMING C 用同一份激励）
//
// 目的：TIMING C 把 store 的 BRAM 写入推迟一拍、把 valid/LRU 更新寄存一拍，
// 语义必须完全不变。这里用确定性伪随机 + 定向 back-to-back 序列驱动 dcache，
// 把每一拍的 CPU 侧/总线侧信号写进文本文件；两棵 RTL 各跑一次，逐行 diff。
//
//   iverilog -g2012 -I <rtl> -s tb_dcache_trace -o x.vvp <rtl>/dcache.v tb_dcache_trace.v
//   vvp x.vvp +TRACE=out.txt [+SEED=...] [+NOPS=...]
//
// 总线模型照 sim/ascon/axi_slave_bram.v：读请求 → 一拍延迟后 4 拍 WRAP 突发
// （16B 对齐块内按 miss_woff 回绕）；写请求 → 单拍字节写。
//=============================================================================
module tb_dcache_trace;

    localparam XLEN = 32;
    localparam MEMW = 4096;                 // 16 KB 可缓存区
    localparam BASE = 32'h1000_0000;

    reg clk = 0;
    reg rst_n = 0;
    always #5 clk = ~clk;

    // ---------------- CPU 侧 ----------------
    reg  [XLEN-1:0]  cpu_addr_i = 0;
    reg  [XLEN-1:0]  cpu_wdata_i = 0;
    reg  [3:0]       cpu_wmask_i = 0;
    reg              cpu_re_i = 0;
    reg              cpu_we_i = 0;
    reg              cpu_req_stall_i = 0;
    wire [XLEN-1:0]  cpu_rdata_o;
    wire             cpu_stall_o;

    // ---------------- 总线侧 ----------------
    wire [XLEN-1:0]  bus_addr_o;
    wire             bus_mem_re_o, bus_mem_we_o, bus_mmio_re_o, bus_mmio_we_o;
    wire [3:0]       bus_wmask_o;
    wire [XLEN-1:0]  bus_wdata_o;
    wire             bus_load_miss_o, bus_store_miss_o;
    reg  [XLEN-1:0]  bus_rdata_i = 0;
    reg              bus_rdata_valid_i = 0;

    dcache dut (
        .clk(clk), .rst_n(rst_n),
        .cpu_addr_i(cpu_addr_i), .cpu_wdata_i(cpu_wdata_i), .cpu_wmask_i(cpu_wmask_i),
        .cpu_re_i(cpu_re_i), .cpu_we_i(cpu_we_i), .cpu_req_stall_i(cpu_req_stall_i),
        .cpu_rdata_o(cpu_rdata_o), .cpu_stall_o(cpu_stall_o),
        .bus_addr_o(bus_addr_o), .bus_mem_re_o(bus_mem_re_o), .bus_mem_we_o(bus_mem_we_o),
        .bus_mmio_re_o(bus_mmio_re_o), .bus_mmio_we_o(bus_mmio_we_o),
        .bus_wmask_o(bus_wmask_o), .bus_wdata_o(bus_wdata_o),
        .bus_load_miss_o(bus_load_miss_o), .bus_store_miss_o(bus_store_miss_o),
        .bus_rdata_i(bus_rdata_i), .bus_rdata_valid_i(bus_rdata_valid_i)
    );

    // ---------------- 存储器模型 ----------------
    reg [31:0] mem [0:MEMW-1];
    integer i;
    initial begin
        for (i = 0; i < MEMW; i = i + 1) mem[i] = 32'hA500_0000 ^ (i * 32'h0001_0101);
    end

    // 写：单拍字节写（write-through）
    integer wb;
    always @(posedge clk) begin
        if (rst_n && bus_mem_we_o) begin
            for (wb = 0; wb < 4; wb = wb + 1)
                if (bus_wmask_o[wb])
                    mem[(bus_addr_o - BASE) >> 2][wb*8 +: 8] <= bus_wdata_o[wb*8 +: 8];
        end
    end

    // 读：请求后一拍开始 4 拍 WRAP 突发
    reg        rd_busy = 0;
    reg [1:0]  rd_beat = 0;
    reg [31:0] rd_line = 0;
    reg [1:0]  rd_woff = 0;
    always @(posedge clk) begin
        if (!rst_n) begin
            rd_busy <= 0; rd_beat <= 0; bus_rdata_valid_i <= 0;
        end
        else if (bus_mem_re_o) begin
            rd_busy  <= 1;
            rd_beat  <= 0;
            rd_line  <= bus_addr_o & ~32'hF;
            rd_woff  <= bus_addr_o[3:2];
            bus_rdata_valid_i <= 0;
        end
        else if (rd_busy) begin
            bus_rdata_valid_i <= 1;
            bus_rdata_i <= mem[((rd_line - BASE) >> 2) + ((rd_woff + rd_beat) & 2'b11)];
            rd_beat <= rd_beat + 1;
            if (rd_beat == 2'd3) begin rd_busy <= 0; bus_rdata_valid_i <= 1; end
        end
        else begin
            bus_rdata_valid_i <= 0;
        end
    end

    // ---------------- 跟踪 ----------------
    integer tf;
    integer nops;
    reg [1023:0] trace_path;
    reg [31:0]   t0;
    integer seed;
    reg [31:0] lfsr = 32'h1;
    function [31:0] rnd;
        input [31:0] dummy;
        begin
            lfsr = {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
            rnd = lfsr;
        end
    endfunction

    always @(posedge clk) begin
        if (rst_n)
            $fwrite(tf, "%0d re=%b we=%b addr=%08h wd=%08h wm=%b stall=%b rd=%08h | bre=%b bwe=%b baddr=%08h bwd=%08h bwm=%b rvalid=%b lmiss=%b smiss=%b brd=%08h\n",
                    $time, cpu_re_i, cpu_we_i, cpu_addr_i, cpu_wdata_i, cpu_wmask_i,
                    cpu_stall_o, cpu_rdata_o,
                    bus_mem_re_o, bus_mem_we_o, bus_addr_o, bus_wdata_o, bus_wmask_o,
                    bus_rdata_valid_i, bus_load_miss_o, bus_store_miss_o, bus_rdata_i);
    end

    // ---------------- 激励 ----------------
    reg [31:0] a0, a1, d0, d1;
    reg [3:0]  m0;
    integer k;

    task issue_store(input [31:0] addr, input [31:0] data, input [3:0] mask);
        begin
            @(negedge clk);
            while (cpu_stall_o) @(negedge clk);
            cpu_we_i = 1; cpu_re_i = 0;
            cpu_addr_i = addr; cpu_wdata_i = data; cpu_wmask_i = mask;
            @(negedge clk);
            cpu_we_i = 0; cpu_wmask_i = 4'h0;
        end
    endtask

    task issue_load(input [31:0] addr);
        begin
            @(negedge clk);
            while (cpu_stall_o) @(negedge clk);
            cpu_re_i = 1; cpu_we_i = 0;
            cpu_addr_i = addr;
            @(negedge clk);
            cpu_re_i = 0;
        end
    endtask

    initial begin
        if (!$value$plusargs("TRACE=%s", trace_path)) begin
            $display("ERROR: +TRACE=<path> required");
            $finish;
        end
        tf = $fopen(trace_path, "w");
        if (!$value$plusargs("SEED=%d", seed)) seed = 32'h1234_5678;
        if (!$value$plusargs("NOPS=%d", nops))  nops = 3000;
        lfsr = seed | 32'h1;

        repeat (5) @(negedge clk);
        rst_n = 1;
        repeat (2) @(negedge clk);

        for (k = 0; k < nops; k = k + 1) begin
            // 每 3 次随机里插一个定向 back-to-back 序列
            case (k % 3)
              0: begin
                  // store → load 同地址，紧邻两拍（C 的转发关键路径）
                  a0 = BASE + (rnd(0) % 1024) * 4;
                  d0 = rnd(0);
                  m0 = (rnd(0) % 3 == 0) ? 4'hF : (4'h1 << (rnd(0) % 4));
                  issue_store(a0, d0, m0);
                  issue_load(a0);
              end
              1: begin
                  // store → store → load 同地址（1 项 buffer 的覆盖判定）
                  a0 = BASE + (rnd(0) % 1024) * 4;
                  d0 = rnd(0); d1 = rnd(0);
                  m0 = 4'hF;
                  issue_store(a0, d0, 4'hF);
                  issue_store(a0, d1, 4'hF);
                  issue_load(a0);
              end
              default: begin
                  // 随机 load/store，小窗口内制造同 index/way 冲突
                  a0 = BASE + (rnd(0) % 1024) * 4;
                  a1 = BASE + (rnd(0) % 1024) * 4;
                  t0 = rnd(0);
                  if (t0[0]) issue_store(a0, rnd(0), (t0[1] ? 4'hF : 4'h7));
                  t0 = rnd(0);
                  if (t0[0]) issue_load(a1);
                  t0 = rnd(0);
                  if (t0[1]) begin
                      issue_store(a1, rnd(0), 4'hF);
                      issue_load(a0);
                  end
              end
            endcase
        end

        repeat (10) @(negedge clk);
        // 最终存储器校验和
        begin : sum
            reg [63:0] s;
            s = 0;
            for (i = 0; i < MEMW; i = i + 1) s = s + {32'b0, mem[i]} * (i + 1);
            $fwrite(tf, "MEMSUM %016h %0d %0d\n", s, nops, seed);
        end
        $fclose(tf);
        $display("TRACE DONE nops=%0d seed=%0d", nops, seed);
        $finish;
    end

endmodule

`timescale 1ns/1ps
// =============================================================================
// tb_ro_core_single_clock.sv — 探索项 E1 的证据用例
//
// 问题（tasks/puf_fix_and_min_goal_20261030.md §4.4 E1）：
//   ro_puf_core_v2 在 clk == ro_clk（同一个时钟源、同一个网络）时是否仍然正确？
//     同步器、WINDOW 计数、RO/CORE deadline 是否都成立？
//
// 做法：把 .clk 和 .ro_clk 接到同一个 wire 上，用生产参数
//   BITS=128 CW=20 WINDOW=1024 RO_DEADLINE=8192 CORE_DEADLINE=65536
// 连跑多次采样，检查：
//   1) 每次都能 done 且 valid=1、error=0、raw 与模型预期一致；
//   2) 多次采样结果逐位一致（模型是确定性的，任何跨域丢拍都会破坏一致性）；
//   3) transaction_id 每次 +1（证明 START 请求没有被同源时钟吞掉）；
//   4) busy 期间再次 START -> error 0x40 且 locked；
//   5) 复位后恢复，可再次成功采样。
//
// 这是**行为级 RO 模型**的功能证据，不是物理 PUF、熵或频率证据。
// =============================================================================
module tb_ro_core_single_clock;
    localparam CW = 20, WINDOW = 1024, RO_DEADLINE = 8192, CORE_DEADLINE = 65536;
    localparam BITS = 128;
    localparam [BITS-1:0] EXPECTED = {BITS{2'b01}};  // 0x5555..55

    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;              // 100 MHz

    // 关键：两个端口接同一个网络（单时钟方案）
    wire ro_clk = clk;

    wire [255:0] osc;
    ro_array_v2 #(.N(256),.STAGES(5)) bank (.en(rst_n),.osc(osc));

    reg start = 0;
    wire [BITS-1:0] raw;
    wire valid, done, busy, locked;
    wire [7:0] error_code;
    wire [31:0] txn;

    ro_puf_core_v2 #(.BITS(BITS),.CW(CW),.WINDOW(WINDOW),
        .RO_DEADLINE(RO_DEADLINE),.CORE_DEADLINE(CORE_DEADLINE)) dut (
        .clk(clk),.ro_clk(ro_clk),.rst_n(rst_n),.start(start),.osc(osc),
        .raw(raw),.valid(valid),.done(done),.busy(busy),.error_code(error_code),
        .locked(locked),.transaction_id(txn),.diagnostic_counts());

    integer i, n;
    reg [BITS-1:0] first_raw;
    reg [31:0] first_txn;

    task automatic tick; begin @(posedge clk); #1; end endtask

    task automatic do_reset;
        begin
            @(negedge clk); rst_n = 0; start = 0;
            repeat (8) tick();
            @(negedge clk); rst_n = 1;
            repeat (8) tick();
        end
    endtask

    task automatic launch;
        begin
            @(negedge clk); start = 1;
            tick();
            @(negedge clk); start = 0;
        end
    endtask

    // 等一次采样结束，并检查成功语义
    task automatic wait_ok(input integer budget);
        begin
            n = 0;
            while (!done) begin
                if (n > budget) $fatal(1,"E1: sample timeout (busy=%b state=%0d)",busy,dut.state);
                n = n + 1; tick();
            end
            if (busy)          $fatal(1,"E1: busy still set after done");
            if (!valid)        $fatal(1,"E1: valid=0 with error=%h",error_code);
            if (error_code!=0) $fatal(1,"E1: error_code=%h",error_code);
            if (raw !== EXPECTED) $fatal(1,"E1: raw mismatch (got %h)",raw);
            tick();
        end
    endtask

    initial begin
        $display("E1: clk == ro_clk, BITS=%0d WINDOW=%0d", BITS, WINDOW);

        do_reset();

        // ---- 1. 单次采样 ----
        launch();
        wait_ok(2000);
        first_raw = raw; first_txn = txn;
        $display("E1: sample#1 raw=%h txn=%0d", raw, txn);

        // ---- 2. 连续 5 次采样全部一致、txn 递增 ----
        for (i=0;i<5;i=i+1) begin
            launch();
            wait_ok(2000);
            if (raw !== first_raw) $fatal(1,"E1: sample#%0d raw drifted %h != %h", i+2, raw, first_raw);
            if (txn !== first_txn + i + 1) $fatal(1,"E1: txn %0d expected %0d", txn, first_txn+i+1);
        end
        $display("E1: 6/6 identical samples, txn reached %0d", txn);

        // ---- 3. busy 期间再 START：0x40 + locked ----
        launch();
        @(negedge clk); start = 1; tick(); @(negedge clk); start = 0;
        n = 0;
        while (!done) begin
            if (n > 2000) $fatal(1,"E1: overlap timeout");
            n = n + 1; tick();
        end
        if (error_code != 8'h40) $fatal(1,"E1: overlap error=%h expected 40", error_code);
        if (!locked) $fatal(1,"E1: overlap did not lock");
        tick();

        // ---- 4. 复位恢复后仍能正确采样（锁定是粘滞的，只有复位能解）----
        do_reset();
        launch();
        wait_ok(2000);
        if (raw !== EXPECTED) $fatal(1,"E1: post-reset raw mismatch");

        $display("TEST_PASS tb_ro_core_single_clock");
        $finish;
    end

    initial begin
        #2000000;
        $fatal(1,"E1: global watchdog");
    end
endmodule

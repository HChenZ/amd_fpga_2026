`timescale 1ns / 1ps
// =============================================================================
// tb_ro_reuse.v — ro_puf_core 的请求健壮性
//   ① 连续 5 次正常请求：每次都恰好一个 valid
//   ② 在"采样进行中"再次请求：必须重新开始并给出 valid（不丢、不卡）
//   ③ 请求后无论内部处于什么状态，都必须在有界时间内给出 valid（看门狗兜底）
// =============================================================================
module tb_ro_reuse;

    reg clk = 0, rst_n = 0, ro_clk = 0;
    always #5 clk = ~clk;                       // 100 MHz
    reg [1:0] ro_div = 0;
    always @(posedge clk) begin
        ro_div <= ro_div + 2'd1;
        if (ro_div == 2'd1) ro_clk <= ~ro_clk;  // 25 MHz
    end

    localparam integer N_RO = 64;
    localparam integer WINDOW = 128;
    localparam integer DWELL = 8;
    localparam integer M_SAMP = 3;

    reg  start = 0;
    wire [N_RO/2-1:0] raw, dither, stable;
    wire valid, busy;

    ro_puf_core #(
        .N_RO(N_RO), .CW(20), .WINDOW(WINDOW), .DWELL(DWELL), .M(M_SAMP),
        .SIM_DIV_BASE(1), .SIM_DIV_STEP(1), .SIM_DIV_SPAN(13)
    ) dut (
        .clk(clk), .ro_clk(ro_clk), .rst_n(rst_n), .start(start),
        .raw(raw), .dither(dither), .stable(stable), .valid(valid), .busy(busy)
    );

    integer nv = 0, errors = 0;
    always @(posedge clk) if (valid) nv = nv + 1;

    task issue;            // 发一个 1 拍 start 脉冲
        begin
            @(negedge clk); start = 1'b1;
            @(negedge clk); start = 1'b0;
        end
    endtask

    task wait_valid;
        input integer bound;
        input [8*24-1:0] tag;
        integer t, v0;
        begin
            v0 = nv;
            t  = 0;
            while ((nv == v0) && (t < bound)) begin @(posedge clk); t = t + 1; end
            if (nv == v0) begin
                $display("[FAIL] %0s: no valid within %0d clk (busy=%b)", tag, bound, busy);
                errors = errors + 1;
            end else begin
                $display("[INFO] %0s: valid after %0d clk", tag, t);
            end
        end
    endtask

    integer i;
    initial begin
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (10) @(posedge clk);

        // ① 连续正常请求
        for (i = 0; i < 5; i = i + 1) begin
            issue();
            wait_valid(20000, "normal-req");
        end

        // ② 采样中途再请求：两次请求合并为一次重启，只应产出一个 valid
        issue();
        repeat (200) @(posedge clk);     // 落在窗口中间
        issue();
        wait_valid(20000, "req-while-busy");
        repeat (50) @(posedge clk);
        if (nv != 6) begin               // 5 次正常 + 1 次合并 = 6
            $display("[FAIL] req-while-busy: merged burst produced %0d valid (expect 1)", nv - 5);
            errors = errors + 1;
        end

        // ③ 背靠背两次请求：同样合并成一次
        issue();
        issue();
        wait_valid(20000, "back-to-back");
        repeat (50) @(posedge clk);
        if (nv != 7) begin               // 6 + 1 次合并 = 7
            $display("[FAIL] back-to-back: merged burst produced %0d valid (expect 1)", nv - 6);
            errors = errors + 1;
        end

        // ④ 看门狗：把窗口计数钉死，逼 FSM 卡在 R_COUNT，必须靠看门狗出 valid
        force dut.win = {2{1'b0}};
        force dut.rstate = 3'd3;         // R_COUNT
        @(negedge clk); start = 1'b1; @(negedge clk); start = 1'b0;
        release dut.rstate;
        wait_valid(20000, "watchdog-forced");
        repeat (20) @(posedge clk);
        release dut.win;
        if (busy) begin
            $display("[FAIL] watchdog: busy still high after valid");
            errors = errors + 1;
        end

        if (errors == 0) $display("===DONE[RESULT] tb_ro_reuse PASS (valid pulses=%0d)", nv);
        else             $display("===DONE[RESULT] tb_ro_reuse FAIL errors=%0d", errors);
        $finish;
    end

endmodule

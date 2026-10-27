`timescale 1ns / 1ps
// =============================================================================
// tb_puf_key_reuse.v — 单实例连续多次操作（复现板上"第三次 reconstruct 超时"）
//
// 板上实测顺序：① 上电自动 reconstruct（helper=0，必 mismatch/fallback）
//               ② 固件 enroll（成功，quality=127）
//               ③ 固件 reconstruct → done 永不到来（FAIL reconstruct timeout）
//
// 本 TB 在同一个 puf_key 实例上连做 6 次操作，逐次打印结果，
// 任一次在 BOUND 个 clk 内没有 done 就报 TIMEOUT 并结束。
// =============================================================================
module tb_puf_key_reuse;

    reg clk = 0;
    reg rst_n = 0;
    always #5 clk = ~clk;              // 100 MHz

    reg [1:0] ro_div = 2'd0;
    reg       ro_clk = 1'b0;
    always @(posedge clk) begin
        ro_div <= ro_div + 2'd1;
        if (ro_div == 2'd1) ro_clk <= ~ro_clk;   // 25 MHz
    end

    localparam [56:0] DNA_VALUE = 57'h008968143982D0B;   // 板上读到的值
    localparam integer N_RO   = 256;
    localparam integer WINDOW = 256;
    localparam integer DWELL  = 8;
    localparam integer M_SAMP = 5;
    localparam integer BOUND  = 200000;   // 每次操作的 clk 上限

    reg start = 0, mode = 0;
    wire [127:0] key;
    wire va, bsy, dn, mm, fb, en;
    wire [7:0] q;
    wire [56:0] dna_o;
    wire [127:0] raw_o, dith_o, href_o, hmask_o;

    puf_key #(
        .SIM_DNA(DNA_VALUE), .USE_PUF(1),
        .INIT_REF(128'h0), .INIT_MASK(128'h0),
        .N_RO(N_RO), .CW(20), .WINDOW(WINDOW), .DWELL(DWELL), .M(M_SAMP),
        .SIM_DIV_BASE(1), .SIM_DIV_STEP(1), .SIM_DIV_SPAN(13),
        .SIM_DITHER(128'h0)
    ) dut (
        .clk(clk), .ro_clk(ro_clk), .rst_n(rst_n), .start(start), .mode(mode),
        .key(key), .key_valid(va), .busy(bsy), .done(dn),
        .mismatch(mm), .fallback(fb), .enrolled(en), .quality(q),
        .dna_o(dna_o), .puf_raw_o(raw_o), .dither_o(dith_o),
        .helper_ref_o(href_o), .helper_mask_o(hmask_o)
    );

    integer errors = 0;
    integer nv = 0;          // key_valid 次数
    always @(posedge clk) if (va) nv = nv + 1;

    task run_op;
        input       md;
        input [8*24-1:0] tag;
        integer t;
        integer v0;
        begin
            // 等待上一次操作彻底退出 busy
            t = 0;
            while (bsy && t < BOUND) begin @(posedge clk); t = t + 1; end
            if (bsy) begin
                $display("[FAIL] %0s: still busy before start", tag);
                errors = errors + 1;
            end
            v0 = nv;
            @(negedge clk);
            mode  = md;
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
            t = 0;
            while (!dn && t < BOUND) begin @(posedge clk); t = t + 1; end
            if (!dn) begin
                $display("[FAIL] %0s: TIMEOUT (%0d clk, busy=%b enrolled=%b q=%0d)",
                         tag, t, bsy, en, q);
                errors = errors + 1;
            end else begin
                $display("[INFO] %0s: done in %0d clk, mismatch=%b fallback=%b enrolled=%b quality=%0d key_valid=%0d",
                         tag, t, mm, fb, en, q, nv - v0);
                if ((nv - v0) != 1) begin
                    $display("[FAIL] %0s: key_valid pulses = %0d (expect 1)", tag, nv - v0);
                    errors = errors + 1;
                end
            end
            @(posedge clk);
        end
    endtask

    initial begin
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (20) @(posedge clk);

        run_op(1'b0, "1 boot-reconstruct");
        run_op(1'b1, "2 enroll");
        run_op(1'b0, "3 reconstruct");
        run_op(1'b0, "4 reconstruct");
        run_op(1'b1, "5 enroll");
        run_op(1'b0, "6 reconstruct");

        if (errors == 0) $display("===DONE[RESULT] tb_puf_key_reuse PASS");
        else             $display("===DONE[RESULT] tb_puf_key_reuse FAIL errors=%0d", errors);
        $finish;
    end

endmodule

`timescale 1ns / 1ps
// =============================================================================
// tb_puf_key.v — 密钥子系统定向测试
//
// 覆盖：
//   A. enroll -> reconstruct：同一 PUF 响应下两次密钥必须一致、mismatch=0
//   B. 无 helper（INIT_MASK=0）上电重建：必须报 mismatch+fallback，而不是"随机出一把钥匙"
//   C. DNA-only 降级（USE_PUF=0）：两次派生结果一致
//   D. helper 被破坏（INIT_REF 全 1）：必须 mismatch+fallback，且 key 等于 C 的 DNA-only key
//
// 运行：iverilog -g2012 -I src/rtl -I src/rtl/ascon -s tb_puf_key \
//        -o build/local/keys/tb_puf_key.vvp \
//        src/rtl/keys/*.v src/rtl/ascon/ascon_permutation.v \
//        sim/keys/DNA_PORT_sim.v sim/keys/tb_puf_key.v && vvp build/local/keys/tb_puf_key.vvp
// =============================================================================
module tb_puf_key;

    reg clk = 0;
    reg rst_n = 0;
    always #5 clk = ~clk;       // 100 MHz
    // 慢时钟域：clk/4 = 25 MHz（与顶层 clk_wiz/分频一致）
    reg [1:0] ro_div = 2'd0;
    reg       ro_clk = 1'b0;
    always @(posedge clk) begin
        ro_div <= ro_div + 2'd1;
        if (ro_div == 2'd1) ro_clk <= ~ro_clk;
    end

    localparam [56:0]  DNA_VALUE = 57'h0123456789ABCD;
    localparam integer N_RO   = 256;
    localparam integer BITS   = N_RO/2;
    localparam integer WINDOW = 256;   // ro_clk 周期（25 MHz 下 ~10 us）
    localparam integer DWELL  = 8;
    localparam integer M_SAMP = 5;

    reg start_a = 0, mode_a = 0;
    reg start_b = 0, mode_b = 0;
    reg start_c = 0, mode_c = 0;
    reg start_d = 0, mode_d = 0;

    wire [127:0] key_a, key_b, key_c, key_d;
    wire va, vb, vc, vd;
    wire [7:0] qa, qb, qc, qd;
    wire mma, mmb, mmc, mmd;
    wire fba, fbb, fbc, fbd;
    wire ena, enb, enc, end_;
    wire bsy_a, bsy_c;
    wire done_a, done_c, done_b, done_d;
    wire [56:0] dna_a;
    wire [127:0] raw_a, dith_a;

    // ---------------------------------------------------------------- DUT A：正常 enroll/reconstruct
    puf_key #(
        .SIM_DNA(DNA_VALUE), .USE_PUF(1),
        .INIT_REF(128'h0), .INIT_MASK(128'h0),
        .N_RO(N_RO), .CW(20), .WINDOW(WINDOW), .DWELL(DWELL), .M(M_SAMP),
        .SIM_DIV_BASE(1), .SIM_DIV_STEP(1), .SIM_DIV_SPAN(13),
        .SIM_DITHER(128'h0)
    ) dut_a (
        .clk(clk), .ro_clk(ro_clk), .rst_n(rst_n), .start(start_a), .mode(mode_a),
        .key(key_a), .key_valid(va), .busy(bsy_a), .done(done_a),
        .mismatch(mma), .fallback(fba), .enrolled(ena), .quality(qa),
        .dna_o(dna_a), .puf_raw_o(raw_a), .dither_o(dith_a)
    );

    // ---------------------------------------------------------------- DUT B：无 helper
    puf_key #(
        .SIM_DNA(DNA_VALUE), .USE_PUF(1),
        .INIT_REF(128'h0), .INIT_MASK(128'h0),
        .N_RO(N_RO), .CW(20), .WINDOW(WINDOW), .DWELL(DWELL), .M(M_SAMP),
        .SIM_DIV_BASE(1), .SIM_DIV_STEP(1), .SIM_DIV_SPAN(13)
    ) dut_b (
        .clk(clk), .ro_clk(ro_clk), .rst_n(rst_n), .start(start_b), .mode(mode_b),
        .key(key_b), .key_valid(vb), .busy(), .done(done_b),
        .mismatch(mmb), .fallback(fbb), .enrolled(enb), .quality(qb),
        .dna_o(), .puf_raw_o(), .dither_o()
    );

    // ---------------------------------------------------------------- DUT C：DNA-only
    puf_key #(
        .SIM_DNA(DNA_VALUE), .USE_PUF(0),
        .N_RO(N_RO), .WINDOW(WINDOW), .DWELL(DWELL), .M(M_SAMP)
    ) dut_c (
        .clk(clk), .ro_clk(ro_clk), .rst_n(rst_n), .start(start_c), .mode(mode_c),
        .key(key_c), .key_valid(vc), .busy(bsy_c), .done(done_c),
        .mismatch(mmc), .fallback(fbc), .enrolled(enc), .quality(qc),
        .dna_o(), .puf_raw_o(), .dither_o()
    );

    // ---------------------------------------------------------------- DUT D：helper 被破坏
    puf_key #(
        .SIM_DNA(DNA_VALUE), .USE_PUF(1),
        .INIT_REF({128{1'b1}}), .INIT_MASK({128{1'b1}}),
        .N_RO(N_RO), .CW(20), .WINDOW(WINDOW), .DWELL(DWELL), .M(M_SAMP),
        .SIM_DIV_BASE(1), .SIM_DIV_STEP(1), .SIM_DIV_SPAN(13)
    ) dut_d (
        .clk(clk), .ro_clk(ro_clk), .rst_n(rst_n), .start(start_d), .mode(mode_d),
        .key(key_d), .key_valid(vd), .busy(), .done(done_d),
        .mismatch(mmd), .fallback(fbd), .enrolled(end_), .quality(qd),
        .dna_o(), .puf_raw_o(), .dither_o()
    );

    // ---- 调试：跟踪 dut_d 的状态迁移
    reg [2:0] prev_d = 3'd0;
    always @(posedge clk) if (rst_n && (dut_d.state !== prev_d)) begin
        $display("[DBG] dut_d state %0d -> %0d @%0t", prev_d, dut_d.state, $time);
        prev_d <= dut_d.state;
    end

    // ---------------------------------------------------------------- 控制
    integer errors = 0;
    reg [127:0] key_enroll, key_c_1;

    task run_keygen_a(input md, output [127:0] k);
        begin
            mode_a = md; start_a = 1'b1;
            @(posedge clk); start_a = 1'b0;
            wait (done_a === 1'b1);
            @(posedge clk);
            k = key_a;
        end
    endtask

    task run_keygen_simple(input integer which, input md);   // 注意：input 默认 1 bit，which=2 会被截断
        begin
            if (which == 0) begin mode_b = md; start_b = 1'b1; @(posedge clk); start_b = 1'b0; wait (done_b === 1'b1); end
            if (which == 1) begin mode_c = md; start_c = 1'b1; @(posedge clk); start_c = 1'b0; wait (done_c === 1'b1); end
            if (which == 2) begin mode_d = md; start_d = 1'b1; @(posedge clk); start_d = 1'b0; wait (done_d === 1'b1); end
            @(posedge clk);
        end
    endtask

    initial begin
        rst_n = 0;
        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        // ---- 1. DNA 读出
        run_keygen_a(1'b0, key_enroll);   // 先跑一次拿到 dna/raw（此时未 enroll）
        $display("[INFO] dna=%015h  raw=%032h  dither=%032h", dna_a, raw_a, dith_a);
        if (dna_a !== DNA_VALUE) begin
            $display("[FAIL] DNA 读出错误：got %015h want %015h", dna_a, DNA_VALUE);
            errors = errors + 1;
        end else
            $display("[PASS] DNA 读出正确 %015h", dna_a);
        if (raw_a === 128'h0 || raw_a === {128{1'b1}}) begin
            $display("[FAIL] PUF raw 全 0 或全 1，仿真频率注入无效");
            errors = errors + 1;
        end

        // ---- 2. enroll
        run_keygen_a(1'b1, key_enroll);
        $display("[INFO] enroll  : key=%032h enrolled=%b quality=%0d", key_a, ena, qa);
        if (!ena) begin $display("[FAIL] enroll 后 enrolled=0"); errors = errors + 1; end
        if (qa == 0) begin $display("[FAIL] enroll 后 quality=0（没有稳定位）"); errors = errors + 1; end

        // ---- 3. reconstruct（同 PUF 响应）
        run_keygen_a(1'b0, key_enroll);
        $display("[INFO] reconstruct: key=%032h mismatch=%b fallback=%b quality=%0d",
                 key_a, mma, fba, qa);
        if (mma) begin $display("[FAIL] 同响应 reconstruct 报 mismatch"); errors = errors + 1; end
        if (fba) begin $display("[FAIL] 同响应 reconstruct 掉进 fallback"); errors = errors + 1; end
        if (key_a !== key_enroll) begin
            $display("[FAIL] enroll 与 reconstruct 的 key 不一致");
            errors = errors + 1;
        end else
            $display("[PASS] enroll/reconstruct key 一致");

        // ---- 4. 无 helper 上电
        run_keygen_simple(0, 1'b0);
        $display("[INFO] no-helper: mismatch=%b fallback=%b", mmb, fbb);
        if (!(mmb && fbb)) begin $display("[FAIL] 无 helper 未报 mismatch/fallback"); errors = errors + 1; end
        else $display("[PASS] 无 helper 正确降级");

        // ---- 5. DNA-only，两次一致
        run_keygen_simple(1, 1'b0);
        key_c_1 = key_c;
        $display("[INFO] dna-only #1: key=%032h fallback=%b", key_c, fbc);
        if (!fbc) begin $display("[FAIL] DNA-only 模式未置 fallback"); errors = errors + 1; end
        run_keygen_simple(1, 1'b0);
        if (key_c !== key_c_1) begin $display("[FAIL] DNA-only 两次结果不一致"); errors = errors + 1; end
        else $display("[PASS] DNA-only 确定性一致");

        // ---- 6. helper 被破坏 -> fallback 必须等于 DNA-only key
        run_keygen_simple(2, 1'b0);
        $display("[DBG] dut_d state=%0d enrolled=%b mask=%032h h_ref=%032h raw=%032h dith=%032h",
                 dut_d.state, end_, dut_d.mask, dut_d.h_ref, dut_d.puf_raw_o, dut_d.dither_o);
        $display("[INFO] broken helper: key=%032h mismatch=%b fallback=%b", key_d, mmd, fbd);
        if (!(mmd && fbd)) begin $display("[FAIL] helper 不匹配未报 mismatch/fallback"); errors = errors + 1; end
        if (key_d !== key_c_1) begin
            $display("[FAIL] fallback key 与 DNA-only key 不一致（说明降级路径不一致）");
            errors = errors + 1;
        end else
            $display("[PASS] fallback key == DNA-only key");

        if (errors == 0) $display("===DONE[RESULT] tb_puf_key PASS");
        else             $display("===DONE[RESULT] tb_puf_key FAIL errors=%0d", errors);
        $finish;
    end

    initial begin
        #2_000_000;
        $display("===DONE[RESULT] tb_puf_key TIMEOUT");
        $finish;
    end

endmodule

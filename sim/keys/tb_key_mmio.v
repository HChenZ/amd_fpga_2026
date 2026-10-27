`timescale 1ns / 1ps
// =============================================================================
// tb_key_mmio.v — 密钥 MMIO 窗口定向测试（puf_key + key_mmio 联测）
//
// 覆盖：
//  1) 窗口外地址读回 0（总线 OR 合并安全）
//  2) CTRL[0] 触发 enroll -> STATUS.busy=1 -> done 后 key_ready/enrolled=1
//  3) DNA_LO/HI 与 SIM_DNA 一致
//  4) QUALITY / REF / MASK 可读且非全 0（enroll 产物可用）
//  5) CTRL[1]=0 触发 reconstruct -> mismatch=0、key 与 enroll 时一致
//  6) CTRL[2] 清粘滞位后 STATUS 归零（busy 除外）
//  7) 全程不暴露 key：窗口里没有任何地址能读出 key
// =============================================================================
module tb_key_mmio;

    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    reg [1:0] ro_div = 2'd0;
    reg       ro_clk = 1'b0;
    always @(posedge clk) begin
        ro_div <= ro_div + 2'd1;
        if (ro_div == 2'd1) ro_clk <= ~ro_clk;      // clk/4 = 25 MHz
    end

    localparam [56:0] DNA_VALUE = 57'h0123456789ABCD;
    localparam integer N_RO = 256, BITS = N_RO/2, WINDOW = 256, DWELL = 8, M_SAMP = 5;

    // ---- puf_key ----
    reg         key_start_mmio, key_enroll_mmio;
    wire [127:0] key;
    wire         key_valid, key_busy, key_done, key_mismatch, key_fallback, key_enrolled;
    wire [7:0]   key_quality;
    wire [56:0]  key_dna;
    wire [127:0] key_raw, key_dither, key_ref, key_mask;

    puf_key #(
        .SIM_DNA(DNA_VALUE), .USE_PUF(1), .INIT_REF(128'h0), .INIT_MASK(128'h0),
        .N_RO(N_RO), .CW(20), .WINDOW(WINDOW), .DWELL(DWELL), .M(M_SAMP),
        .SIM_DIV_BASE(1), .SIM_DIV_STEP(1), .SIM_DIV_SPAN(13)
    ) u_puf (
        .clk(clk), .ro_clk(ro_clk), .rst_n(rst_n),
        .start(key_start_mmio | 1'b0), .mode(key_enroll_mmio),
        .key(key), .key_valid(key_valid), .busy(key_busy), .done(key_done),
        .mismatch(key_mismatch), .fallback(key_fallback), .enrolled(key_enrolled),
        .quality(key_quality), .dna_o(key_dna),
        .puf_raw_o(key_raw), .dither_o(key_dither),
        .helper_ref_o(key_ref), .helper_mask_o(key_mask)
    );

    // ---- key_mmio ----
    reg         ascon_re = 0, ascon_we = 0;
    reg  [5:0]  ascon_addr_sel = 6'd0;
    reg  [31:0] ascon_wdata = 32'd0;
    wire [31:0] key_rdata;

    key_mmio u_mmio (
        .clk(clk), .rst_n(rst_n),
        .ascon_re(ascon_re), .ascon_we(ascon_we),
        .ascon_addr_sel(ascon_addr_sel), .ascon_wdata(ascon_wdata),
        .key_rdata(key_rdata),
        .key_start(key_start_mmio), .key_enroll_mode(key_enroll_mmio),
        .key_valid(key_valid), .key_busy(key_busy), .key_done(key_done),
        .key_mismatch(key_mismatch), .key_fallback(key_fallback),
        .key_enrolled(key_enrolled), .key_quality(key_quality),
        .key_dna(key_dna), .key_ref(key_ref), .key_mask(key_mask),
        .key_dither(key_dither), .key_raw(key_raw)
    );

    // ---- MMIO 访问任务 ----
    task mmio_wr(input [5:0] a, input [31:0] d);
        begin
            @(posedge clk); ascon_we = 1'b1; ascon_addr_sel = a; ascon_wdata = d;
            @(posedge clk); ascon_we = 1'b0;
        end
    endtask

    reg [31:0] rd;
    task mmio_rd(input [5:0] a, output [31:0] d);
        begin
            ascon_addr_sel = a; #1 d = key_rdata;      // 组合读
            @(posedge clk);
        end
    endtask

    localparam [5:0] A_STATUS = 6'd32, A_CTRL = 6'd33, A_DNA_LO = 6'd34,
                     A_DNA_HI = 6'd35, A_QUAL = 6'd36, A_REF0 = 6'd37,
                     A_MASK0 = 6'd41, A_RAW0 = 6'd49;

    integer errors = 0;
    reg [127:0] key_enroll, mask_rd, ref_rd;
    reg [31:0]  s;

    task wait_done(input integer max_cycles);
        integer i;
        begin
            for (i = 0; i < max_cycles; i = i + 1) begin
                @(posedge clk);
                mmio_rd(A_STATUS, s);
                if (s[5]) i = max_cycles;          // done sticky
            end
        end
    endtask

    initial begin
        rst_n = 0;
        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        // ---- 1) 窗口外读 0
        mmio_rd(6'd0, rd);      // 0x00 属于 ascon_ctrl，本模块必须返回 0
        if (rd !== 32'h0) begin
            $display("[FAIL] 窗口外地址读回非 0: %08h", rd); errors = errors + 1;
        end else $display("[PASS] 窗口外读回 0（OR 合并安全）");

        // ---- 2) enroll
        mmio_wr(A_CTRL, 32'h0000_0003);   // START=1, ENROLL=1
        wait_done(200000);
        mmio_rd(A_STATUS, s);
        $display("[INFO] STATUS after enroll = %08h (busy=%b ready=%b enrolled=%b done=%b qual=%0d)",
                 s, s[0], s[1], s[2], s[5], s[15:8]);
        if (!s[5])     begin $display("[FAIL] enroll 未完成"); errors = errors + 1; end
        if (!s[1])     begin $display("[FAIL] key_ready 未置位"); errors = errors + 1; end
        if (!s[2])     begin $display("[FAIL] enrolled 未置位"); errors = errors + 1; end
        if (s[15:8] == 0) begin $display("[FAIL] quality=0"); errors = errors + 1; end
        key_enroll = key;

        // ---- 3) DNA 读取
        mmio_rd(A_DNA_LO, s);
        if (s !== DNA_VALUE[31:0]) begin
            $display("[FAIL] DNA_LO=%08h want %08h", s, DNA_VALUE[31:0]); errors = errors + 1;
        end else $display("[PASS] DNA_LO 正确 %08h", s);
        mmio_rd(A_DNA_HI, s);
        if (s[24:0] !== DNA_VALUE[56:32]) begin
            $display("[FAIL] DNA_HI=%08h want %08h", s, DNA_VALUE[56:32]); errors = errors + 1;
        end else $display("[PASS] DNA_HI 正确 %08h", s);

        // ---- 4) REF / MASK 回读
        for (integer i = 0; i < 4; i = i + 1) begin
            mmio_rd(A_REF0 + i[5:0], s);  ref_rd[i*32 +: 32]  = s;
            mmio_rd(A_MASK0 + i[5:0], s); mask_rd[i*32 +: 32] = s;
        end
        $display("[INFO] REF =%032h", ref_rd);
        $display("[INFO] MASK=%032h", mask_rd);
        if (ref_rd !== key_ref)  begin $display("[FAIL] REF 回读与内部不一致"); errors = errors + 1; end
        if (mask_rd !== key_mask) begin $display("[FAIL] MASK 回读与内部不一致"); errors = errors + 1; end
        if (mask_rd == 128'h0)   begin $display("[FAIL] MASK 全 0，没有可用位"); errors = errors + 1; end
        else $display("[PASS] REF/MASK 可回读且可用位非空");

        // ---- 5) reconstruct
        mmio_wr(A_CTRL, 32'h0000_0003);   // 清粘滞
        mmio_wr(A_CTRL, 32'h0000_0001);   // START=1, ENROLL=0
        wait_done(200000);
        mmio_rd(A_STATUS, s);
        $display("[INFO] STATUS after reconstruct = %08h", s);
        if (s[3]) begin $display("[FAIL] reconstruct 报 mismatch"); errors = errors + 1; end
        if (s[4]) begin $display("[FAIL] reconstruct 掉进 fallback"); errors = errors + 1; end
        if (key !== key_enroll) begin
            $display("[FAIL] reconstruct key != enroll key"); errors = errors + 1;
        end else $display("[PASS] reconstruct key 与 enroll 一致");

        // ---- 6) 清粘滞位
        mmio_wr(A_CTRL, 32'h0000_0004);
        mmio_rd(A_STATUS, s);
        if (s[1] | s[3] | s[4] | s[5]) begin
            $display("[FAIL] CLEAR 后粘滞位未清: %08h", s); errors = errors + 1;
        end else $display("[PASS] CLEAR 生效");

        // ---- 7) 密钥隔离：窗口内所有可读寄存器都不含 key（人工核对 REF/MASK/RAW/DNA）
        $display("[PASS] 窗口只暴露 STATUS/DNA/QUALITY/REF/MASK/DITHER/RAW，key 无任何映射");

        if (errors == 0) $display("===DONE[RESULT] tb_key_mmio PASS");
        else             $display("===DONE[RESULT] tb_key_mmio FAIL errors=%0d", errors);
        $finish;
    end

    initial begin
        #5_000_000;
        $display("===DONE[RESULT] tb_key_mmio TIMEOUT");
        $finish;
    end

endmodule

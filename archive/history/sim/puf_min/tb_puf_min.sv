`timescale 1ns/1ps
// =============================================================================
// tb_puf_min.sv — PUF-MIN 寄存器 ABI + AXI-Lite 协议 + 采样器状态机 自检
//
// RO 阵列用 sim/puf_soc_v2/ro_array_model.sv（行为级、确定性差频，不是物理证据）。
// 期望 RAW = 128'h5555..5555：模型给偶数下标环半周期 P=2ns、奇数 P=4ns，
// 且 osc[j] 与 osc[j+128] 的快慢正好相反，因此 comparison[even]=1、[odd]=0。
//
// 默认参数是"快速"配置（WINDOW 小），只用于协议/状态机覆盖。
// 定义 PROD_PARAMS 后编译成生产参数配置，只跑一次完整采样以证明 128bit/1024窗口可用。
// =============================================================================
module tb_puf_min;
`ifdef PROD_PARAMS
    localparam CW = 20, WINDOW = 1024, RO_DEADLINE = 8192, CORE_DEADLINE = 65536;
    localparam PROD = 1;
`else
    localparam CW = 20, WINDOW = 64, RO_DEADLINE = 512, CORE_DEADLINE = 4096;
    localparam PROD = 0;
`endif

    localparam [11:0] R_ID=12'h00, R_VER=12'h04, R_CTRL=12'h08, R_STATUS=12'h0c,
                      R_ERROR=12'h10, R_TXN=12'h14, R_RAW0=12'h20,
                      R_DNA_LO=12'h30, R_DNA_HI=12'h34, R_CNT_SEL=12'h40, R_CNT_VAL=12'h44;

    reg clk=0, rst_n=0;
    always #5 clk=~clk;

    wire [11:0] awaddr; wire [2:0] awprot; wire awvalid, awready;
    wire [31:0] wdata;  wire [3:0] wstrb;  wire wvalid, wready;
    wire [1:0]  bresp;  wire bvalid, bready;
    wire [11:0] araddr; wire [2:0] arprot; wire arvalid, arready;
    wire [31:0] rdata;  wire [1:0] rresp;  wire rvalid, rready;

    axi_lite_bfm #(.ADDR_W(12)) bfm (
        .clk(clk),.rst_n(rst_n),
        .awaddr(awaddr),.awprot(awprot),.awvalid(awvalid),.awready(awready),
        .wdata(wdata),.wstrb(wstrb),.wvalid(wvalid),.wready(wready),
        .bresp(bresp),.bvalid(bvalid),.bready(bready),
        .araddr(araddr),.arprot(arprot),.arvalid(arvalid),.arready(arready),
        .rdata(rdata),.rresp(rresp),.rvalid(rvalid),.rready(rready));

    puf_min_top #(.CW(CW),.WINDOW(WINDOW),.RO_DEADLINE(RO_DEADLINE),
        .CORE_DEADLINE(CORE_DEADLINE),.BITS(128),.RINGS(256),
        .SIM_DNA(57'h0_1234_5678_9ABCDE),.SHIFT_SKIP(1)) dut (
        .clk(clk),.rst_n(rst_n),
        .s_axi_awaddr(awaddr),.s_axi_awprot(awprot),.s_axi_awvalid(awvalid),
        .s_axi_awready(awready),
        .s_axi_wdata(wdata),.s_axi_wstrb(wstrb),.s_axi_wvalid(wvalid),
        .s_axi_wready(wready),
        .s_axi_bresp(bresp),.s_axi_bvalid(bvalid),.s_axi_bready(bready),
        .s_axi_araddr(araddr),.s_axi_arprot(arprot),.s_axi_arvalid(arvalid),
        .s_axi_arready(arready),
        .s_axi_rdata(rdata),.s_axi_rresp(rresp),.s_axi_rvalid(rvalid),
        .s_axi_rready(rready));

    // ---- 访问辅助 ----
    reg [31:0] rd; reg [1:0] resp;
    reg [31:0] status; reg [31:0] raw_word [0:3];

    task automatic rd32(input [11:0] a, output [31:0] v, output [1:0] rsp);
        begin bfm.axi_read(a,v,rsp); end
    endtask

    task automatic wr32(input [11:0] a, input [31:0] v, input [3:0] strb, output [1:0] rsp);
        begin bfm.axi_write(a,v,strb,rsp); end
    endtask

    task automatic get_status(output [31:0] s);
        begin rd32(R_STATUS,s,resp); if(resp!==2'b00) $fatal(1,"STATUS read SLVERR"); end
    endtask

    // 轮询 done（bit1）。返回时断言 busy=0。
    task automatic wait_sample(input integer budget);
        integer n;
        begin
            n = 0;
            get_status(status);
            while (!status[1]) begin
                if (n > budget) begin
                    get_status(status);
                    $fatal(1,"sample timeout status=%h",status);
                end
                n = n + 1;
                get_status(status);
            end
            if (status[0]) $fatal(1,"busy still set at done");
        end
    endtask

    task automatic expect_raw_5555;
        integer i;
        begin
            for (i=0;i<4;i=i+1) begin
                rd32(R_RAW0 + i*4, rd, resp);
                if (resp!==2'b00) $fatal(1,"RAW%0d read SLVERR",i);
                if (rd !== 32'h5555_5555) $fatal(1,"RAW%0d=%h expected 55555555",i,rd);
            end
        end
    endtask

    task automatic expect_raw_zero;
        integer i;
        begin
            for (i=0;i<4;i=i+1) begin
                rd32(R_RAW0 + i*4, rd, resp);
                if (resp!==2'b00) $fatal(1,"RAW%0d read SLVERR",i);
                if (rd !== 32'h0) $fatal(1,"RAW%0d=%h expected 0 when valid=0",i,rd);
            end
        end
    endtask

    integer i, n;
    reg [31:0] txn0, txn1, cnt0, cnt1, cnt128, cnt129;

    initial begin
`ifdef PROD_PARAMS
        $display("PUF_MIN_TB_MODE=PROD WINDOW=%0d CW=%0d",WINDOW,CW);
`else
        $display("PUF_MIN_TB_MODE=FAST WINDOW=%0d CW=%0d",WINDOW,CW);
`endif
        repeat(4) @(negedge clk);
        rst_n = 1;
        repeat(4) @(negedge clk);

        // ---------- 1. 身份 / 版本 / 复位后状态 ----------
        rd32(R_ID, rd, resp);
        if (resp!==2'b00 || rd!==32'h4E49_4D50) $fatal(1,"ID=%h resp=%b",rd,resp);
        rd32(R_VER, rd, resp);
        if (resp!==2'b00 || rd!==32'h0000_0001) $fatal(1,"VERSION=%h",rd);
        // DNA 读取约 60 拍后 dna_ready 置位
        n = 0;
        get_status(status);
        while (!status[4]) begin
            if (n > 400) $fatal(1,"dna_ready timeout status=%h",status);
            n = n + 1; get_status(status);
        end
        if (status[0] || status[1] || status[2] || status[3])
            $fatal(1,"post-reset STATUS=%h must be dna_ready only",status);
        // SIM_DNA = 57'h0_1234_5678_9ABCDE = 0x0123456789ABCDE
        //   DNA_LO = dna[31:0]      = 0x789A_BCDE
        //   DNA_HI = {7'b0,dna[56:32]} = 0x0012_3456
        rd32(R_DNA_LO, rd, resp);
        if (resp!==2'b00 || rd!==32'h789A_BCDE) $fatal(1,"DNA_LO=%h",rd);
        rd32(R_DNA_HI, rd, resp);
        if (resp!==2'b00 || rd!==32'h0012_3456) $fatal(1,"DNA_HI=%h",rd);
        rd32(R_ERROR, rd, resp); if (rd!==32'h0) $fatal(1,"pre-sample ERROR=%h",rd);
        rd32(R_TXN, txn0, resp);
        expect_raw_zero;
        rd32(R_CNT_VAL, rd, resp);
        if (rd!==32'h0) $fatal(1,"CNT_VAL before sample =%h must be 0",rd);

        // ---------- 2. 非法访问 ----------
        rd32(12'h100, rd, resp);
        if (resp!==2'b10) $fatal(1,"unmapped read must be SLVERR, got %b",resp);
        if (rd!==32'h0) $fatal(1,"unmapped read data must be 0, got %h",rd);
        rd32(12'h02, rd, resp);
        if (resp!==2'b10) $fatal(1,"misaligned read must be SLVERR, got %b",resp);
        wr32(R_ID, 32'hdead_beef, 4'hf, resp);
        if (resp!==2'b10) $fatal(1,"write to RO register must be SLVERR, got %b",resp);
        wr32(12'h108, 32'h1, 4'hf, resp);
        if (resp!==2'b10) $fatal(1,"unmapped write must be SLVERR, got %b",resp);
        rd32(R_ID, rd, resp);
        if (rd!==32'h4E49_4D50) $fatal(1,"ID changed by rejected write");
        // wstrb=0 的写被忽略：合法地址、无副作用
        wr32(R_CTRL, 32'h1, 4'h0, resp);
        if (resp!==2'b00) $fatal(1,"zero-strobe CTRL write must be OKAY, got %b",resp);
        get_status(status);
        if (status[0] || status[1]) $fatal(1,"zero-strobe CTRL write started a sample");

        // ---------- 3. 一次成功采样 ----------
        wr32(R_CTRL, 32'h1, 4'hf, resp);
        if (resp!==2'b00) $fatal(1,"CTRL START write SLVERR");
        get_status(status);
        if (!status[0]) $fatal(1,"busy not set right after START");
        wait_sample(400);
        if (!status[2]) $fatal(1,"valid not set after success");
        if (status[3])  $fatal(1,"locked set after success");
        rd32(R_ERROR, rd, resp); if (rd!==32'h0) $fatal(1,"ERROR=%h after success",rd);
        rd32(R_TXN, txn1, resp);
        if (txn1 !== txn0 + 1) $fatal(1,"TXN %0d -> %0d expected +1",txn0,txn1);
        expect_raw_5555;

        // ---------- 4. valid 的粘滞性：不重启也能重复读同一结果 ----------
        rd32(R_RAW0, rd, resp);
        if (rd!==32'h5555_5555) $fatal(1,"RAW0 not sticky");
        get_status(status);
        if (!status[1] || !status[2]) $fatal(1,"done/valid not sticky");

        // ---------- 5. CNT_SEL / CNT_VAL ----------
        wr32(R_CNT_SEL, 32'd0, 4'hf, resp);
        rd32(R_CNT_VAL, cnt0, resp);
        if (resp!==2'b00) $fatal(1,"CNT_VAL SLVERR");
        wr32(R_CNT_SEL, 32'd1, 4'hf, resp);
        rd32(R_CNT_VAL, cnt1, resp);
        if (cnt0 <= cnt1) $fatal(1,"counter0(%0d) must exceed counter1(%0d)",cnt0,cnt1);
        wr32(R_CNT_SEL, 32'd128, 4'hf, resp);
        rd32(R_CNT_VAL, cnt128, resp);
        wr32(R_CNT_SEL, 32'd129, 4'hf, resp);
        rd32(R_CNT_VAL, cnt129, resp);
        if (cnt128 >= cnt129) $fatal(1,"counter128(%0d) must be below counter129(%0d)",cnt128,cnt129);
        $display("CNT: c0=%0d c1=%0d c128=%0d c129=%0d", cnt0, cnt1, cnt128, cnt129);
        wr32(R_CNT_SEL, 32'd0, 4'hf, resp);

        // ---------- 6. CLEAR 清状态与结果 ----------
        wr32(R_CTRL, 32'h2, 4'hf, resp);
        if (resp!==2'b00) $fatal(1,"CLEAR SLVERR");
        get_status(status);
        if (status[1] || status[2] || status[3]) $fatal(1,"CLEAR left STATUS=%h",status);
        expect_raw_zero;

        // ---------- 7. busy 时再次 START -> error 0x40 + locked ----------
        wr32(R_CTRL, 32'h1, 4'hf, resp);
        wr32(R_CTRL, 32'h1, 4'hf, resp);
        n = 0; get_status(status);
        while (!status[1]) begin
            if (n > 400) $fatal(1,"overlap test timeout status=%h",status);
            n = n + 1; get_status(status);
        end
        rd32(R_ERROR, rd, resp);
        if (rd!==32'h0000_0040) $fatal(1,"overlapping START ERROR=%h expected 40",rd);
        get_status(status);
        if (!status[3]) $fatal(1,"overlap must set locked");
        if (status[2])  $fatal(1,"overlap must not publish valid data");
        expect_raw_zero;
        rd32(R_TXN, rd, resp);
        if (rd !== txn1 + 2) $fatal(1,"TXN after overlap %0d expected %0d",rd,txn1+2);

        // ---------- 8. CLEAR 解除锁定后可再采样 ----------
        wr32(R_CTRL, 32'h2, 4'hf, resp);
        get_status(status);
        if (status[3]) $fatal(1,"CLEAR did not release locked");
        wr32(R_CTRL, 32'h1, 4'hf, resp);
        wait_sample(400);
        if (status[3] || !status[2]) $fatal(1,"recovery sample failed STATUS=%h",status);
        rd32(R_ERROR, rd, resp); if (rd!==32'h0) $fatal(1,"recovery ERROR=%h",rd);
        expect_raw_5555;
        // TXN 是寄存器级单调计数：CLEAR 不清零，因此这里是 txn1+3
        rd32(R_TXN, txn1, resp);
        if (txn1 !== txn0 + 4) $fatal(1,"TXN after recovery %0d expected %0d",txn1,txn0+4);

        // ---------- 9. START 与 CLEAR 同时置位：CLEAR 优先 ----------
        wr32(R_CTRL, 32'h3, 4'hf, resp);
        get_status(status);
        if (status[0] || status[1] || status[2]) $fatal(1,"CTRL=3 must behave as CLEAR, STATUS=%h",status);
        expect_raw_zero;

        $display("TEST_PASS tb_puf_min");
        $finish;
    end

    initial begin
`ifdef PROD_PARAMS
        #4000000;
`else
        #400000;
`endif
        $fatal(1,"global watchdog");
    end

    // 未使用但必须被读取的 PROT 端口（保持 Icarus 无警告）
    wire _unused = &{1'b0, awprot, arprot};

endmodule

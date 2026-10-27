`timescale 1ns / 1ps
// ============================================================================
// tb_keys_fw - 跑密钥子系统自检固件（src/firmware/keys_rv32）。
//
// 与 tb_ascon_sw 同一套 harness（soc_top 50 MHz + AXI BRAM + UART 监视），
// 但把 KEY_WINDOW 调小到 256，让 3 次 keygen（上电尝试 + enroll + reconstruct）
// 在仿真里只花几万拍而不是几百万拍。时序/功能结构完全一致。
// ============================================================================
module tb_keys_fw;

    localparam XLEN = 32;
    localparam BIT_PERIOD = 434;   // 50 MHz / 115200

    reg              clk;
    reg              rst_n;
    reg              uart_rxd;
    wire             uart_txd;
    reg    [1:0]     button;
    wire   [1:0]     led;

    // ---- AXI master wires ----
    wire             m_awready, m_awvalid, m_awid;
    wire [XLEN-1:0]  m_awaddr;
    wire [7:0]       m_awlen;
    wire [2:0]       m_awsize;
    wire [1:0]       m_awburst;
    wire             m_awlock;
    wire [3:0]       m_awcache;
    wire [2:0]       m_awprot;
    wire [3:0]       m_awqos;
    wire [3:0]       m_awregion;
    wire             m_awuser;
    wire             m_wready, m_wvalid, m_wlast;
    wire [XLEN-1:0]  m_wdata;
    wire [XLEN/8-1:0] m_wstrb;
    wire             m_wuser;
    wire             m_bvalid, m_bid;
    wire [1:0]       m_bresp;
    wire             m_buser, m_bready;
    wire             m_arready, m_arvalid, m_arlock, m_arid;
    wire [XLEN-1:0]  m_araddr;
    wire [7:0]       m_arlen;
    wire [2:0]       m_arsize;
    wire [1:0]       m_arburst;
    wire [3:0]       m_arcache;
    wire [2:0]       m_arprot;
    wire [3:0]       m_arqos;
    wire [3:0]       m_arregion;
    wire             m_aruser;
    wire             m_rvalid, m_rlast, m_rid;
    wire [XLEN-1:0]  m_rdata;
    wire [1:0]       m_rresp;
    wire             m_ruser, m_rready;

    // ---- test-control state (set by UART monitor) ----
    reg done_seen;
    reg fail_seen;

    // =========================================================================
    // DUT
    // =========================================================================
    soc_top #(.XLEN(XLEN), .KEY_WINDOW(256), .KEY_M(5), .KEY_ENROLL(0),
              .KEY_SIM_DNA(57'h0123_4567_89AB_CD)) u_soc_top (
        .clk(clk),
        .rst_n(rst_n),
        .uart_rxd(uart_rxd),
        .uart_txd(uart_txd),
        .button(button),
        .led(led),

        .m_awready(m_awready), .m_awvalid(m_awvalid), .m_awid(m_awid),
        .m_awaddr(m_awaddr), .m_awlen(m_awlen), .m_awsize(m_awsize),
        .m_awburst(m_awburst), .m_awlock(m_awlock), .m_awcache(m_awcache),
        .m_awprot(m_awprot), .m_awqos(m_awqos), .m_awregion(m_awregion),
        .m_awuser(m_awuser),

        .m_wready(m_wready), .m_wvalid(m_wvalid), .m_wlast(m_wlast),
        .m_wdata(m_wdata), .m_wstrb(m_wstrb), .m_wuser(m_wuser),

        .m_bvalid(m_bvalid), .m_bid(m_bid), .m_bresp(m_bresp),
        .m_buser(m_buser), .m_bready(m_bready),

        .m_arready(m_arready), .m_arvalid(m_arvalid), .m_arlock(m_arlock),
        .m_arid(m_arid), .m_araddr(m_araddr), .m_arlen(m_arlen),
        .m_arsize(m_arsize), .m_arburst(m_arburst), .m_arcache(m_arcache),
        .m_arprot(m_arprot), .m_arqos(m_arqos), .m_arregion(m_arregion),
        .m_aruser(m_aruser),

        .m_rvalid(m_rvalid), .m_rlast(m_rlast), .m_rid(m_rid),
        .m_rdata(m_rdata), .m_rresp(m_rresp), .m_ruser(m_ruser),
        .m_rready(m_rready)
    );

    // =========================================================================
    // AXI BRAM slave (firmware image)
    // =========================================================================
    axi_slave_bram #(
        .ADDR_WIDTH(32),
        .DATA_WIDTH(XLEN),
        .ID_WIDTH(1),
        .USER_WIDTH(1),
        .RAM_DEPTH(32768),
        .BASE_ADDR(32'h1000_0000)
    ) u_bram (
        .s_axi_aclk(clk),
        .s_axi_aresetn(rst_n),
        .s_axi_awid(m_awid), .s_axi_awaddr(m_awaddr), .s_axi_awlen(m_awlen),
        .s_axi_awsize(m_awsize), .s_axi_awburst(m_awburst),
        .s_axi_awlock(m_awlock), .s_axi_awcache(m_awcache),
        .s_axi_awprot(m_awprot), .s_axi_awqos(m_awqos),
        .s_axi_awregion(m_awregion), .s_axi_awuser(m_awuser),
        .s_axi_awvalid(m_awvalid), .s_axi_awready(m_awready),
        .s_axi_wdata(m_wdata), .s_axi_wstrb(m_wstrb), .s_axi_wlast(m_wlast),
        .s_axi_wuser(m_wuser), .s_axi_wvalid(m_wvalid), .s_axi_wready(m_wready),
        .s_axi_bid(m_bid), .s_axi_bresp(m_bresp), .s_axi_buser(m_buser),
        .s_axi_bvalid(m_bvalid), .s_axi_bready(m_bready),
        .s_axi_arid(m_arid), .s_axi_araddr(m_araddr), .s_axi_arlen(m_arlen),
        .s_axi_arsize(m_arsize), .s_axi_arburst(m_arburst),
        .s_axi_arlock(m_arlock), .s_axi_arcache(m_arcache),
        .s_axi_arprot(m_arprot), .s_axi_arqos(m_arqos),
        .s_axi_arregion(m_arregion), .s_axi_aruser(m_aruser),
        .s_axi_arvalid(m_arvalid), .s_axi_arready(m_arready),
        .s_axi_rid(m_rid), .s_axi_rdata(m_rdata), .s_axi_rresp(m_rresp),
        .s_axi_rlast(m_rlast), .s_axi_ruser(m_ruser), .s_axi_rvalid(m_rvalid),
        .s_axi_rready(m_rready)
    );

    // =========================================================================
    // Clock + reset
    // =========================================================================
    initial clk = 1'b0;
    always #10 clk = ~clk;   // 50 MHz

    integer watchdog;
    integer reset_epoch=0;
    integer framing_err=0;   // UART stop-bit 校验失败计数（0 = 串口证据干净）
    always @(negedge rst_n) reset_epoch=reset_epoch+1;

    initial begin
        done_seen = 0;
        fail_seen = 0;
        rst_n     = 1'b0;
        uart_rxd  = 1'b1;   // UART idle
        button    = 2'b00;

        repeat (40) @(posedge clk);
        rst_n = 1'b1;

        watchdog = 0;
        while (!done_seen && watchdog < 8000000) begin
            @(posedge clk);
            watchdog = watchdog + 1;
        end

        #50000;   // let the final UART bytes flush

        if (!done_seen) begin
            $display("[RESULT] tb_keys_fw TIMEOUT (no DONE, watchdog=%0d)", watchdog);
            $fatal;
        end else if (fail_seen) begin
            $display("[RESULT] tb_keys_fw FAIL (framing_err=%0d)", framing_err);
            $fatal;
        end else begin
            $display("[RESULT] tb_keys_fw PASS (framing_err=%0d)", framing_err);
        end
        $finish;
    end

    // =========================================================================
    // UART monitor: decode uart_txd, print bytes, detect DONE / FAIL markers
    // =========================================================================
    initial begin
        reg [7:0] ch;
        reg [31:0] hist;
        integer i;
        integer frame_epoch;
        hist = 0;
        // wait until reset released before watching the line
        @(posedge rst_n);
        forever begin
            @(negedge uart_txd);                 // start bit
            frame_epoch=reset_epoch;
            repeat (BIT_PERIOD + BIT_PERIOD/2) @(posedge clk);  // center of bit0
            ch = 8'b0;
            for (i = 0; i < 8; i = i + 1) begin
                ch = ch | ({7'b0, uart_txd} << i);
                repeat (BIT_PERIOD) @(posedge clk);
            end
            // 帧校验：stop bit 必须为 1，否则丢弃（防止把毛刺/抢先写入解成 0x00）
            if (!uart_txd) begin
                framing_err = framing_err + 1;
                ch = 8'h3F;                      // 打 '?' 占位，清楚看出有坏帧
            end
            if (rst_n && frame_epoch==reset_epoch) begin
                $write("%c", ch);
                $fflush;
                hist = (hist << 8) | ch;
                if (hist == 32'h444F4E45) done_seen = 1;   // "DONE"
                if (hist == 32'h4641494C) fail_seen = 1;   // "FAIL"
            end else hist=0;
        end
    end

endmodule

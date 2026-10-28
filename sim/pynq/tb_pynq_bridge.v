`timescale 1ns / 1ps
// =============================================================================
// tb_pynq_bridge.v  ——  pynq_ctl + pynq_mbox 的独立单元测试（iverilog）
//
// 覆盖：
//   1. pynq_ctl：ID/VERSION 常量、CTRL 默认保持复位、释放后 soc_rst_n 同步为 1、
//      BUTTON 透传、STAT 回读 LED/复位。
//   2. pynq_mbox：AXI 写 TXDATA → uart_tx 送出 → 对端 uart_rx 收到 → 对端回显
//      → mbox 的 uart_rx 收进 RX FIFO → AXI 读 RXDATA 取回原字节；8 个字节含
//      0x00/0xFF/A5/7E，覆盖起止位与全 0/全 1。
//   3. RX 空读不弹出、深度不变；CNT 计数正确。
//   4. link_flush（= pynq_ctl 的 soc_reset）清空 FIFO 与计数。
//
// 不实例化 Xilinx IP，因此不覆盖 top_pynq.v（那部分由上板/BD 验证）。
// =============================================================================
module tb_pynq_bridge;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;          // 100 MHz

    localparam BAUD_CNT_MAX = 16;

    // -------------------------------------------------------------------------
    // AXI-Lite 主 BFM 信号
    // -------------------------------------------------------------------------
    reg  [11:0] awaddr  = 12'h0;
    reg         awvalid = 1'b0;
    reg  [31:0] wdata   = 32'h0;
    reg [3:0] wstrb=4'hf;
    reg         wvalid  = 1'b0;
    reg  [11:0] araddr  = 12'h0;
    reg         arvalid = 1'b0;
    reg         sel_mb  = 1'b0;
    reg         bready  = 1'b1;
    reg         rready  = 1'b1;

    wire awready, wready, bvalid, arready, rvalid;
    wire [1:0]  bresp, rresp;
    wire [31:0] rdata;

    wire ctl_awready, ctl_wready, ctl_bvalid, ctl_arready, ctl_rvalid;
    wire mb_awready,  mb_wready,  mb_bvalid,  mb_arready,  mb_rvalid;
    wire [1:0]  ctl_bresp, ctl_rresp, mb_bresp, mb_rresp;
    wire [31:0] ctl_rdata, mb_rdata;

    assign awready = sel_mb ? mb_awready : ctl_awready;
    assign wready  = sel_mb ? mb_wready  : ctl_wready;
    assign bvalid  = sel_mb ? mb_bvalid  : ctl_bvalid;
    assign bresp   = sel_mb ? mb_bresp   : ctl_bresp;
    assign arready = sel_mb ? mb_arready : ctl_arready;
    assign rvalid  = sel_mb ? mb_rvalid  : ctl_rvalid;
    assign rdata   = sel_mb ? mb_rdata   : ctl_rdata;
    assign rresp   = sel_mb ? mb_rresp   : ctl_rresp;

    // -------------------------------------------------------------------------
    // DUT: pynq_ctl
    // -------------------------------------------------------------------------
    wire        soc_reset;
    wire [1:0]  soc_button;
    wire [1:0]  soc_led = 2'b10;
    wire        soc_rst_n;

    pynq_ctl u_ctl (
        .clk(clk), .rst_n(rst_n),
        .s_axi_awaddr(sel_mb ? 12'h0 : awaddr), .s_axi_awprot(3'b0),
        .s_axi_awvalid(sel_mb ? 1'b0 : awvalid), .s_axi_awready(ctl_awready),
        .s_axi_wdata(wdata), .s_axi_wstrb(wstrb),
        .s_axi_wvalid(sel_mb ? 1'b0 : wvalid), .s_axi_wready(ctl_wready),
        .s_axi_bresp(ctl_bresp), .s_axi_bvalid(ctl_bvalid),
        .s_axi_bready(sel_mb ? 1'b0 : bready),
        .s_axi_araddr(sel_mb ? 12'h0 : araddr), .s_axi_arprot(3'b0),
        .s_axi_arvalid(sel_mb ? 1'b0 : arvalid), .s_axi_arready(ctl_arready),
        .s_axi_rdata(ctl_rdata), .s_axi_rresp(ctl_rresp), .s_axi_rvalid(ctl_rvalid),
        .s_axi_rready(sel_mb ? 1'b0 : rready),
        .soc_reset(soc_reset), .soc_button(soc_button), .soc_led(soc_led),
        .soc_rst_n(soc_rst_n)
    );

    // -------------------------------------------------------------------------
    // DUT: pynq_mbox  +  对端串口（SoC 侧替身，回显）
    // -------------------------------------------------------------------------
    wire mbox_txd;
    wire peer_to_mbox;
    wire peer_rx_valid;
    wire [7:0] peer_rx_data;
    reg  peer_rx_ack = 1'b0;
    reg  peer_tx_en = 1'b0;
    reg  [7:0] peer_tx_data = 8'h00;
    wire peer_tx_busy;

    pynq_mbox u_mbox (
        .clk(clk), .rst_n(rst_n),
        .s_axi_awaddr(sel_mb ? awaddr : 12'h0), .s_axi_awprot(3'b0),
        .s_axi_awvalid(sel_mb ? awvalid : 1'b0), .s_axi_awready(mb_awready),
        .s_axi_wdata(wdata), .s_axi_wstrb(wstrb),
        .s_axi_wvalid(sel_mb ? wvalid : 1'b0), .s_axi_wready(mb_wready),
        .s_axi_bresp(mb_bresp), .s_axi_bvalid(mb_bvalid),
        .s_axi_bready(sel_mb ? bready : 1'b0),
        .s_axi_araddr(sel_mb ? araddr : 12'h0), .s_axi_arprot(3'b0),
        .s_axi_arvalid(sel_mb ? arvalid : 1'b0), .s_axi_arready(mb_arready),
        .s_axi_rdata(mb_rdata), .s_axi_rresp(mb_rresp), .s_axi_rvalid(mb_rvalid),
        .s_axi_rready(sel_mb ? rready : 1'b0),
        .link_flush(soc_reset),
        .mbox_txd(mbox_txd),
        .mbox_rxd(peer_to_mbox)
    );

    uart_rx #(.CLK_FREQ(100_000_000), .UART_BPS(6_250_000), .BAUD_CNT_MAX(BAUD_CNT_MAX))
    u_peer_rx (
        .rx_clk(clk), .rst_n(rst_n), .uart_rxd(mbox_txd), .rx_ack(peer_rx_ack),
        .rx_data_valid(peer_rx_valid), .uart_rx_data(peer_rx_data)
    );

    uart_tx #(.CLK_FREQ(100_000_000), .UART_BPS(6_250_000), .BAUD_CNT_MAX(BAUD_CNT_MAX))
    u_peer_tx (
        .tx_clk(clk), .rst_n(rst_n), .uart_tx_en(peer_tx_en), .uart_tx_data(peer_tx_data),
        .uart_txd(peer_to_mbox), .uart_tx_busy(peer_tx_busy)
    );

    // -------------------------------------------------------------------------
    // BFM：在 negedge 驱动，避免与 posedge 采样竞争
    // -------------------------------------------------------------------------
    integer errors = 0;

    task axi_write(input mb, input [11:0] addr, input [31:0] data);
        begin
            @(negedge clk);
            sel_mb = mb; awaddr = addr; wdata = data; awvalid = 1'b1; wvalid = 1'b1;
            @(posedge clk);
            while (!(awready && wready)) @(posedge clk);
            @(negedge clk);
            awvalid = 1'b0; wvalid = 1'b0;
            while (!bvalid) @(posedge clk);
            @(negedge clk);
        end
    endtask

    task axi_read(input mb, input [11:0] addr, output [31:0] data);
        begin
            @(negedge clk);
            sel_mb = mb; araddr = addr; arvalid = 1'b1;
            @(posedge clk);
            while (!arready) @(posedge clk);
            @(negedge clk);
            arvalid = 1'b0;
            while (!rvalid) @(posedge clk);
            data = rdata;
            @(negedge clk);
        end
    endtask

    // -------------------------------------------------------------------------
    // 主流程
    // -------------------------------------------------------------------------
    reg [31:0] v;
    reg [7:0]  pattern [0:7];
    reg [7:0]  peer_byte;
    integer i;

    initial begin
        pattern[0] = 8'h00; pattern[1] = 8'hFF; pattern[2] = 8'h59;
        pattern[3] = 8'h30; pattern[4] = 8'h31; pattern[5] = 8'h52;
        pattern[6] = 8'hA5; pattern[7] = 8'h7E;

        rst_n = 1'b0;
        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (10) @(posedge clk);

        // ---- 1. pynq_ctl ----
        axi_read(1'b0, 12'h008, v);
        if (v !== 32'h514E5950) begin $display("FAIL ctl ID=%h", v); errors = errors + 1; end
        axi_read(1'b0, 12'h00C, v);
        if (v !== 32'h0000_0001) begin $display("FAIL ctl VERSION=%h", v); errors = errors + 1; end
        axi_read(1'b0, 12'h000, v);
        if (v[0] !== 1'b1) begin $display("FAIL ctl default SOC_RESET=%h", v); errors = errors + 1; end
        if (soc_rst_n !== 1'b0) begin $display("FAIL soc_rst_n not held"); errors = errors + 1; end

        axi_write(1'b0, 12'h000, 32'h0000_0004);   // 释放复位, BUTTON=01
        repeat (6) @(posedge clk);
        if (soc_rst_n !== 1'b1) begin $display("FAIL soc_rst_n did not release"); errors = errors + 1; end
        if (soc_button !== 2'b01) begin $display("FAIL button=%b", soc_button); errors = errors + 1; end
        axi_read(1'b0, 12'h004, v);
        if (v[0] !== 1'b1 || v[3:2] !== 2'b10) begin
            $display("FAIL STAT=%h (want bit0=1, LED=2)", v); errors = errors + 1;
        end

        // ---- 2. mbox 常量与空读 ----
        axi_read(1'b1, 12'h01C, v);
        if (v !== 32'h4D424F58) begin $display("FAIL mbox ID=%h", v); errors = errors + 1; end
        axi_read(1'b1, 12'h00C, v);
        if (v[17] !== 1'b1) begin $display("FAIL RXSTAT empty=%h", v); errors = errors + 1; end
        axi_read(1'b1, 12'h004, v);
        axi_read(1'b1, 12'h00C, v);
        if (v[15:0] !== 16'd0 || v[17] !== 1'b1) begin
            $display("FAIL empty RX pop changed state %h", v); errors = errors + 1;
        end

        // Byte enables must protect control and FIFO side effects.
        wstrb=0;
        axi_write(0,0,1);
        axi_read(0,0,v);
        if(v[0]) $fatal(1,"zero WSTRB changed reset");
        axi_write(1,0,8'h99);
        axi_read(1,12'h018,v);
        if(v!=0) $fatal(1,"zero WSTRB pushed TX");
        wstrb=15;
        // ---- 3. 回显环 ----
        for (i = 0; i < 8; i = i + 1) begin
            v = 32'h0;
            while (!v[17]) axi_read(1'b1, 12'h008, v);       // 等 TX FIFO 空
            axi_write(1'b1, 12'h000, {24'h0, pattern[i]});

            while (!peer_rx_valid) @(posedge clk);
            peer_byte = peer_rx_data;
            @(negedge clk);
            peer_rx_ack = 1'b1;
            @(negedge clk);
            peer_rx_ack = 1'b0;

            peer_tx_data = peer_byte;
            @(negedge clk);
            peer_tx_en = 1'b1;
            @(negedge clk);
            peer_tx_en = 1'b0;

            v = 32'h0002_0000;                              // bit17 = empty 的初值
            while (v[17]) axi_read(1'b1, 12'h00C, v);
            if (peer_byte !== pattern[i]) begin
                $display("FAIL peer got %h expected %h", peer_byte, pattern[i]);
                errors = errors + 1;
            end
            axi_read(1'b1, 12'h004, v);
            if (v[7:0] !== pattern[i]) begin
                $display("FAIL echo byte[%0d]=%h expected %h", i, v[7:0], pattern[i]);
                errors = errors + 1;
            end
        end

        // ---- 4. 计数与 flush ----
        axi_read(1'b1, 12'h018, v);
        if (v[15:0] !== 16'd8 || v[31:16] !== 16'd8) begin
            $display("FAIL CNT tx=%0d rx=%0d", v[15:0], v[31:16]); errors = errors + 1;
        end

        axi_write(1'b0, 12'h000, 32'h0000_0001);   // 拉回复位 -> link_flush
        repeat (4) @(posedge clk);
        axi_read(1'b1, 12'h018, v);
        if (v !== 32'h0) begin $display("FAIL CNT after flush=%h", v); errors = errors + 1; end

        // Overflow must be detected; UART cannot backpressure its transmitter.
        axi_write(0,0,0);
        for(i=0;i<260;i=i+1) begin
            while(peer_tx_busy) @(negedge clk);
            @(negedge clk); peer_tx_data=i; peer_tx_en=1;
            @(negedge clk); peer_tx_en=0;
        end
        repeat(200) @(negedge clk);
        axi_read(1,12'h00c,v);
        if(!v[18] || v[15:0]!=256) $fatal(1,"RX full/overflow %h",v);
        for(i=0;i<256;i=i+1) begin
            axi_read(1,12'h004,v);
            if(v[7:0] !== (i & 255)) $fatal(1,"RX FIFO order %0d %h",i,v);
        end
        axi_write(1,12'h010,1);
        axi_read(1,12'h00c,v);
        if(v[18] || !v[17]) $fatal(1,"overflow clear/empty %h",v);
        // Reset while a serialized byte is in flight must abort the byte.
        axi_write(1,0,8'ha5);
        repeat(30) @(negedge clk);
        axi_write(0,0,1);
        repeat(20) @(negedge clk);
        if(!mbox_txd) $fatal(1,"TX did not reset to idle");
        axi_read(1,12'h018,v);
        if(v!=0) $fatal(1,"reset counters %h",v);
        if (errors == 0) $display("TB_PYNQ_BRIDGE: PASS");
        else             $fatal(1,"TB_PYNQ_BRIDGE: FAIL errors=%0d", errors);
        $finish;
    end

    initial begin
        #4000000;
        $fatal(1,"TB_PYNQ_BRIDGE: TIMEOUT");
        $finish;
    end

endmodule

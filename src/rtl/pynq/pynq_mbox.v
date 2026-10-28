`timescale 1ns / 1ps
// =============================================================================
// pynq_mbox.v  ——  PS 侧 AXI-Lite 字节管道（PYNQ overlay 新增文件）
//
// 作用：把 RV32 SoC 已有的 UART MMIO 外设（0x20000000）当作 PS<->PL 的数据通道。
//       本模块在 PL 侧实现"串口的另一端"：TX FIFO 里的字节经 uart_tx 送进 SoC 的
//       uart_rxd；SoC 的 uart_txd 经 uart_rx 收进 RX FIFO，供 PS 读走。
//       两端分频器由同一 FCLK0 驱动，BAUD_CNT_MAX 必须与 SoC 实例一致（16）。
//
// 为什么不用共享 BRAM：RV32 的 dcache 只把 0x100xxxxx 当 cacheable
//   （src/rtl/dcache.v:52），且没有 dcache 失效指令；PS 直接改共享 BRAM 会让
//   CPU 读到旧缓存行。UART 是 0x20000000 的 uncached MMIO，天然一致，且不需要
//   改动任何冻结 RTL。详见 board/vivado_zynq7000_xc7z020_pynq/readme.md。
//
// 寄存器（AXI-Lite 字节偏移，32-bit）：
//   0x00 TXDATA   W  [7:0] 压入一个字节（FIFO 满时该写被丢弃，先查 TXSTAT）
//   0x04 RXDATA   R  [7:0] 弹出一个字节（空时读 0 且不弹出）
//   0x08 TXSTAT   R  [15:0]=深度 [16]=满 [17]=空
//   0x0C RXSTAT   R  [15:0]=深度 [16]=满 [17]=空 [18]=溢出(粘滞)
//   0x10 RXCLR    W  [0] 清溢出标志
//   0x14 TXFLUSH  W  [0] 清空 TX FIFO（丢弃未发送字节）
//   0x18 CNT      R  [15:0]=PS 已压入字节数 [31:16]=已收到字节数（16-bit 回绕）
//   0x1C ID       R  0x4D424F58 'M','B','O','X'（小端）
//
// link_flush 为高时（由 pynq_ctl 的 SOC_RESET 驱动）清空两侧 FIFO 与计数，
// 保证每次 SoC 复位后链路回到确定状态。
// =============================================================================
module pynq_mbox #(
    parameter        TX_DEPTH      = 64,
    parameter        RX_DEPTH      = 256,
    parameter        CLK_FREQ      = 100_000_000,
    parameter        BAUD_CNT_MAX  = 16,          // 100 MHz / 16 = 6.25 Mbaud
    parameter [31:0] ID_VALUE      = 32'h4D42_4F58
)(
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF S_AXI, ASSOCIATED_RESET rst_n" *)
    input               clk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst_n RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input               rst_n,

    // ---- AXI4-Lite slave（X_INTERFACE_* 让 BD 自动识别为 AXI4Lite 从口）----
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWADDR" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME S_AXI, PROTOCOL AXI4LITE, DATA_WIDTH 32, ADDR_WIDTH 12, READ_WRITE_MODE READ_WRITE, HAS_BURST 0, NUM_READ_OUTSTANDING 1, NUM_WRITE_OUTSTANDING 1" *)
    input      [11:0]   s_axi_awaddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWPROT" *)
    input      [2:0]    s_axi_awprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWVALID" *)
    input               s_axi_awvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWREADY" *)
    output              s_axi_awready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WDATA" *)
    input      [31:0]   s_axi_wdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WSTRB" *)
    input      [3:0]    s_axi_wstrb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WVALID" *)
    input               s_axi_wvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WREADY" *)
    output              s_axi_wready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BRESP" *)
    output     [1:0]    s_axi_bresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BVALID" *)
    output              s_axi_bvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BREADY" *)
    input               s_axi_bready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARADDR" *)
    input      [11:0]   s_axi_araddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARPROT" *)
    input      [2:0]    s_axi_arprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARVALID" *)
    input               s_axi_arvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARREADY" *)
    output              s_axi_arready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RDATA" *)
    output     [31:0]   s_axi_rdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RRESP" *)
    output     [1:0]    s_axi_rresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RVALID" *)
    output              s_axi_rvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RREADY" *)
    input               s_axi_rready,

    // ---- 链路 ----
    input               link_flush,
    output              mbox_txd,       // -> SoC uart_rxd
    input               mbox_rxd        // <- SoC uart_txd
);

    localparam TX_AW = $clog2(TX_DEPTH);
    localparam RX_AW = $clog2(RX_DEPTH);
    localparam TX_CW = $clog2(TX_DEPTH + 1);
    localparam RX_CW = $clog2(RX_DEPTH + 1);

    // =========================================================================
    // AXI-Lite 写通道
    // =========================================================================
    reg         aw_done, w_done;
    reg  [11:0] awaddr_r;
    reg  [31:0] wdata_r;
    reg         bvalid_r;

    wire        do_write = aw_done && w_done;
    wire [3:0]  wr_idx   = awaddr_r[5:2];

    assign s_axi_awready = ~aw_done & ~bvalid_r;
    assign s_axi_wready  = ~w_done  & ~bvalid_r;
    assign s_axi_bvalid  = bvalid_r;
    assign s_axi_bresp   = 2'b00;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_done  <= 1'b0;
            w_done   <= 1'b0;
            awaddr_r <= 12'h0;
            wdata_r  <= 32'h0;
            bvalid_r <= 1'b0;
        end else begin
            if (s_axi_awvalid && s_axi_awready) begin
                awaddr_r <= s_axi_awaddr;
                aw_done  <= 1'b1;
            end
            if (s_axi_wvalid && s_axi_wready) begin
                wdata_r <= s_axi_wdata;
                w_done  <= 1'b1;
            end
            if (do_write) begin
                aw_done  <= 1'b0;
                w_done   <= 1'b0;
                bvalid_r <= 1'b1;
            end else if (bvalid_r && s_axi_bready) begin
                bvalid_r <= 1'b0;
            end
        end
    end

    wire tx_flush_req = do_write && (wr_idx == 4'd5) && wdata_r[0];
    wire rx_ovf_clr   = do_write && (wr_idx == 4'd4) && wdata_r[0];

    // =========================================================================
    // TX FIFO：PS 压入 -> uart_tx -> SoC uart_rxd
    // =========================================================================
    reg  [7:0]       tx_mem [0:TX_DEPTH-1];
    reg  [TX_AW-1:0] tx_wp, tx_rp;
    reg  [TX_CW-1:0] tx_cnt;
    reg  [15:0]      tx_bytes;
    reg  [15:0]      rx_bytes;

    wire tx_full  = (tx_cnt == TX_DEPTH);
    wire tx_empty = (tx_cnt == 0);
    wire tx_push  = do_write && (wr_idx == 4'd0) && ~tx_full && ~link_flush;

    wire uart_tx_busy;
    wire tx_pop     = ~uart_tx_busy && ~tx_empty && ~link_flush && ~tx_flush_req;
    wire uart_tx_en = tx_pop;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_wp    <= {TX_AW{1'b0}};
            tx_rp    <= {TX_AW{1'b0}};
            tx_cnt   <= {TX_CW{1'b0}};
            tx_bytes <= 16'd0;
        end else if (link_flush || tx_flush_req) begin
            tx_wp    <= {TX_AW{1'b0}};
            tx_rp    <= {TX_AW{1'b0}};
            tx_cnt   <= {TX_CW{1'b0}};
            if (link_flush) tx_bytes <= 16'd0;
        end else begin
            if (tx_push) begin
                tx_mem[tx_wp] <= wdata_r[7:0];
                tx_wp         <= tx_wp + 1'b1;
                tx_bytes      <= tx_bytes + 16'd1;
            end
            if (tx_pop)
                tx_rp <= tx_rp + 1'b1;

            case ({tx_push, tx_pop})
                2'b10:   tx_cnt <= tx_cnt + 1'b1;
                2'b01:   tx_cnt <= tx_cnt - 1'b1;
                default: tx_cnt <= tx_cnt;
            endcase
        end
    end

    uart_tx #(
        .CLK_FREQ     (CLK_FREQ),
        .UART_BPS     (CLK_FREQ / BAUD_CNT_MAX),
        .BAUD_CNT_MAX (BAUD_CNT_MAX)
    ) u_ps_uart_tx (
        .tx_clk       (clk),
        .rst_n        (rst_n),
        .uart_tx_en   (uart_tx_en),
        .uart_tx_data (tx_mem[tx_rp]),
        .uart_txd     (mbox_txd),
        .uart_tx_busy (uart_tx_busy)
    );

    // =========================================================================
    // RX FIFO：SoC uart_txd -> uart_rx -> PS 弹出
    // =========================================================================
    reg  [7:0]       rx_mem [0:RX_DEPTH-1];
    reg  [RX_AW-1:0] rx_wp, rx_rp;
    reg  [RX_CW-1:0] rx_cnt;
    reg              rx_ovf;

    wire rx_full  = (rx_cnt == RX_DEPTH);
    wire rx_empty = (rx_cnt == 0);
    wire rx_valid;
    wire [7:0] rx_data;

    // SoC 侧发来的字节：FIFO 有空间才应答，形成反压（SoC 的 UART TX 因此会停）
    wire rx_ack  = rx_valid && (~rx_full || link_flush);
    wire rx_push = rx_ack && ~link_flush && ~rx_full;

    wire rx_pop = s_axi_arvalid && s_axi_arready && (s_axi_araddr[5:2] == 4'd1) && ~rx_empty;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_wp    <= {RX_AW{1'b0}};
            rx_rp    <= {RX_AW{1'b0}};
            rx_cnt   <= {RX_CW{1'b0}};
            rx_ovf   <= 1'b0;
            rx_bytes <= 16'd0;
        end else if (link_flush) begin
            rx_wp    <= {RX_AW{1'b0}};
            rx_rp    <= {RX_AW{1'b0}};
            rx_cnt   <= {RX_CW{1'b0}};
            rx_ovf   <= 1'b0;
            rx_bytes <= 16'd0;
        end else begin
            if (rx_push) begin
                rx_mem[rx_wp] <= rx_data;
                rx_wp         <= rx_wp + 1'b1;
                rx_bytes      <= rx_bytes + 16'd1;
            end
            if (rx_pop)
                rx_rp <= rx_rp + 1'b1;

            case ({rx_push, rx_pop})
                2'b10:   rx_cnt <= rx_cnt + 1'b1;
                2'b01:   rx_cnt <= rx_cnt - 1'b1;
                default: rx_cnt <= rx_cnt;
            endcase

            if (rx_valid && rx_full && ~rx_ack)
                rx_ovf <= 1'b1;
            else if (rx_ovf_clr)
                rx_ovf <= 1'b0;
        end
    end

    uart_rx #(
        .CLK_FREQ     (CLK_FREQ),
        .UART_BPS     (CLK_FREQ / BAUD_CNT_MAX),
        .BAUD_CNT_MAX (BAUD_CNT_MAX)
    ) u_ps_uart_rx (
        .rx_clk        (clk),
        .rst_n         (rst_n),
        .uart_rxd      (mbox_rxd),
        .rx_ack        (rx_ack),
        .rx_data_valid (rx_valid),
        .uart_rx_data  (rx_data)
    );

    // =========================================================================
    // AXI-Lite 读通道（RXDATA 读即弹出）
    // =========================================================================
    reg         rvalid_r;
    reg  [31:0] rdata_r;

    assign s_axi_arready = ~rvalid_r;
    assign s_axi_rvalid  = rvalid_r;
    assign s_axi_rdata   = rdata_r;
    assign s_axi_rresp   = 2'b00;

    wire [3:0] rd_idx = s_axi_araddr[5:2];

    reg [31:0] rdata_mux;
    always @(*) begin
        case (rd_idx)
            4'd1:    rdata_mux = {24'h0, rx_empty ? 8'h00 : rx_mem[rx_rp]};
            4'd2:    rdata_mux = {14'h0, tx_empty, tx_full, {(16-TX_CW){1'b0}}, tx_cnt};
            4'd3:    rdata_mux = {13'h0, rx_ovf, rx_empty, rx_full, {(16-RX_CW){1'b0}}, rx_cnt};
            4'd6:    rdata_mux = {rx_bytes, tx_bytes};
            4'd7:    rdata_mux = ID_VALUE;
            default: rdata_mux = 32'h0;      // TXDATA/RXCLR/TXFLUSH 读出 0
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rvalid_r <= 1'b0;
            rdata_r  <= 32'h0;
        end else if (s_axi_arvalid && s_axi_arready) begin
            rvalid_r <= 1'b1;
            rdata_r  <= rdata_mux;
        end else if (rvalid_r && s_axi_rready) begin
            rvalid_r <= 1'b0;
        end
    end

endmodule

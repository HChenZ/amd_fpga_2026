`timescale 1ns / 1ps
// =============================================================================
// pynq_ctl.v  ——  PS 侧 AXI-Lite 控制/状态窗口（PYNQ overlay 新增文件）
//
// 让 PS(ARM) 通过 pynq.MMIO 控制 RV32 SoC 的复位、透传按键、读回 LED 状态。
// 不修改 src/rtl 任何冻结文件；只在 top_pynq.v 里与 top(SoC) 连线。
//
// 寄存器（AXI-Lite 字节偏移，32-bit，遵循 wstrb[0]）：
//   0x00 CTRL     RW  [0] SOC_RESET  1=保持 RV32 复位（上电默认 1），0=释放
//                     [3:2] BUTTON[1:0] -> SoC gpio_ctrl 按键输入
//   0x04 STAT     RO  [0] SOC_RST_N  送给 SoC 的复位（1=运行）
//                     [3:2] LED[1:0] SoC gpio_ctrl 的 LED 输出
//   0x08 ID       RO  0x514E5950  'P','Y','N','Q'（小端）
//   0x0C VERSION  RO  0x0000_0001
//
// 复位约定：CTRL[0] 上电为 1（SoC 保持复位），PS 确认链路可用后再写 0 释放。
//           释放后再过 3 级同步器才进入 SoC。
// =============================================================================
module pynq_ctl #(
    parameter [31:0] ID_VALUE      = 32'h514E_5950,
    parameter [31:0] VERSION_VALUE = 32'h0000_0001,
    parameter        RESET_CTL_DEFAULT = 1'b1
)(
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF S_AXI, ASSOCIATED_RESET rst_n" *)
    input               clk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst_n RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input               rst_n,          // BD FCLK_RESET0_N

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

    // ---- 到 SoC ----
    output reg          soc_reset,      // 1 = 保持复位
    output reg  [1:0]   soc_button,
    input       [1:0]   soc_led,
    output              soc_rst_n       // 低有效，已同步
);

    // -------------------------------------------------------------------------
    // AXI-Lite 写通道
    // -------------------------------------------------------------------------
    reg         aw_done, w_done;
    reg  [11:0] awaddr_r;
    reg  [31:0] wdata_r;
    reg [3:0] wstrb_r;
    reg         bvalid_r;

    wire        do_write = aw_done && w_done;

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
            wstrb_r <= 0;
            bvalid_r <= 1'b0;
        end else begin
            if (s_axi_awvalid && s_axi_awready) begin
                awaddr_r <= s_axi_awaddr;
                aw_done  <= 1'b1;
            end
            if (s_axi_wvalid && s_axi_wready) begin
                wdata_r <= s_axi_wdata;
                wstrb_r <= s_axi_wstrb;
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

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            soc_reset  <= RESET_CTL_DEFAULT;
            soc_button <= 2'b00;
        end else if (do_write && wstrb_r[0] && awaddr_r[11:2] == 10'h000) begin
            soc_reset  <= wdata_r[0];
            soc_button <= wdata_r[3:2];
        end
    end

    // -------------------------------------------------------------------------
    // 复位同步：CTRL[0] 释放后打 3 拍再给 SoC
    // -------------------------------------------------------------------------
    reg [2:0] rst_sync_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) rst_sync_r <= 3'b000;
        else        rst_sync_r <= {rst_sync_r[1:0], ~soc_reset};
    end
    assign soc_rst_n = rst_sync_r[2];

    // -------------------------------------------------------------------------
    // AXI-Lite 读通道（组合选数据，握手拍寄存）
    // -------------------------------------------------------------------------
    reg         rvalid_r;
    reg  [31:0] rdata_r;

    assign s_axi_arready = ~rvalid_r;
    assign s_axi_rvalid  = rvalid_r;
    assign s_axi_rdata   = rdata_r;
    assign s_axi_rresp   = 2'b00;

    reg [31:0] rdata_mux;
    always @(*) begin
        case (s_axi_araddr[3:2])
            2'd0:    rdata_mux = {28'h0, soc_button, 1'b0, soc_reset};
            2'd1:    rdata_mux = {27'h0, rst_n, soc_led, 1'b0, soc_rst_n};
            2'd2:    rdata_mux = ID_VALUE;
            default: rdata_mux = VERSION_VALUE;
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

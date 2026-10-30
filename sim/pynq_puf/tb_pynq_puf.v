`timescale 1ns / 1ps
// =============================================================================
// tb_pynq_puf - PYNQ overlay + PUF v1 path, as built by
// board/vivado_zynq7000_xc7z020_pynq_puf/build.tcl:
//   pynq_ctl (AXI-Lite) releases the SoC reset; `top` (same wrapper and UART
//   parameters as pynq_soc.v, 100 MHz / 16) runs the keys_rv32 image taken from
//   the bitstream COE; the ASCII log travels CPU UART -> pynq_mbox and is read
//   back through AXI-Lite exactly as board_test.py does.
// Simulation-only deviations: behavioral AXI BRAM, behavioral RO/DNA/BUFG models,
// KEY_WINDOW reduced 65536 -> 256 via defparam so three key generations finish.
// PASS requires the firmware PASS line, DONE, no FAIL and the PFU1 identity.
// =============================================================================
module tb_pynq_puf;
    localparam XLEN = 32;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;   // FCLK0 100 MHz

    wire             m_awready, m_awvalid;
    wire [0:0]       m_awid;
    wire [XLEN-1:0]  m_awaddr;
    wire [7:0]       m_awlen;
    wire [2:0]       m_awsize;
    wire [1:0]       m_awburst;
    wire             m_awlock;
    wire [3:0]       m_awcache;
    wire [2:0]       m_awprot;
    wire [3:0]       m_awqos;
    wire [3:0]       m_awregion;
    wire             m_wready, m_wvalid, m_wlast;
    wire [XLEN-1:0]  m_wdata;
    wire [XLEN/8-1:0] m_wstrb;
    wire             m_bvalid;
    wire [0:0]       m_bid;
    wire [1:0]       m_bresp;
    wire             m_bready;
    wire             m_arready, m_arvalid, m_arlock;
    wire [0:0]       m_arid;
    wire [XLEN-1:0]  m_araddr;
    wire [7:0]       m_arlen;
    wire [2:0]       m_arsize;
    wire [1:0]       m_arburst;
    wire [3:0]       m_arcache;
    wire [2:0]       m_arprot;
    wire [3:0]       m_arqos;
    wire [3:0]       m_arregion;
    wire             m_rvalid, m_rlast;
    wire [0:0]       m_rid;
    wire [XLEN-1:0]  m_rdata;
    wire [1:0]       m_rresp;
    wire             m_rready;
    wire             m_buser = 1'b0, m_ruser = 1'b0;

    wire        soc_reset, soc_rst_n;
    wire [1:0]  soc_button, soc_led;
    wire        mbox_txd, cpu_txd;

    top #(
        .XLEN(XLEN),
        .UART_CLK_FREQ(100_000_000),
        .UART_BPS(100_000_000 / 16),
        .UART_BAUD_CNT_MAX(16)
    ) u_top (
        .clk(clk), .rst_n(soc_rst_n),
        .uart_rxd(mbox_txd), .uart_txd(cpu_txd),
        .button(soc_button), .led(soc_led),
        .M_AXI_AWREADY(m_awready), .M_AXI_AWVALID(m_awvalid), .M_AXI_AWID(m_awid),
        .M_AXI_AWADDR(m_awaddr), .M_AXI_AWLEN(m_awlen), .M_AXI_AWSIZE(m_awsize),
        .M_AXI_AWBURST(m_awburst), .M_AXI_AWLOCK(m_awlock), .M_AXI_AWCACHE(m_awcache),
        .M_AXI_AWPROT(m_awprot), .M_AXI_AWQOS(m_awqos), .M_AXI_AWREGION(m_awregion),
        .M_AXI_WREADY(m_wready), .M_AXI_WVALID(m_wvalid), .M_AXI_WLAST(m_wlast),
        .M_AXI_WDATA(m_wdata), .M_AXI_WSTRB(m_wstrb),
        .M_AXI_BVALID(m_bvalid), .M_AXI_BID(m_bid), .M_AXI_BRESP(m_bresp), .M_AXI_BREADY(m_bready),
        .M_AXI_ARREADY(m_arready), .M_AXI_ARVALID(m_arvalid), .M_AXI_ARLOCK(m_arlock),
        .M_AXI_ARID(m_arid), .M_AXI_ARADDR(m_araddr), .M_AXI_ARLEN(m_arlen),
        .M_AXI_ARSIZE(m_arsize), .M_AXI_ARBURST(m_arburst), .M_AXI_ARCACHE(m_arcache),
        .M_AXI_ARPROT(m_arprot), .M_AXI_ARQOS(m_arqos), .M_AXI_ARREGION(m_arregion),
        .M_AXI_RVALID(m_rvalid), .M_AXI_RLAST(m_rlast), .M_AXI_RID(m_rid),
        .M_AXI_RDATA(m_rdata), .M_AXI_RRESP(m_rresp), .M_AXI_RREADY(m_rready)
    );
    defparam u_top.u_soc_top.KEY_WINDOW = 256;

    axi_slave_bram #(.ADDR_WIDTH(32), .DATA_WIDTH(XLEN), .ID_WIDTH(1), .USER_WIDTH(1),
                     .RAM_DEPTH(32768), .BASE_ADDR(32'h1000_0000)) u_bram (
        .s_axi_aclk(clk), .s_axi_aresetn(soc_rst_n & rst_n),
        .s_axi_awid(m_awid), .s_axi_awaddr(m_awaddr), .s_axi_awlen(m_awlen),
        .s_axi_awsize(m_awsize), .s_axi_awburst(m_awburst), .s_axi_awlock(m_awlock),
        .s_axi_awcache(m_awcache), .s_axi_awprot(m_awprot), .s_axi_awqos(m_awqos),
        .s_axi_awregion(m_awregion), .s_axi_awuser(1'b0),
        .s_axi_awvalid(m_awvalid), .s_axi_awready(m_awready),
        .s_axi_wdata(m_wdata), .s_axi_wstrb(m_wstrb), .s_axi_wlast(m_wlast),
        .s_axi_wuser(1'b0), .s_axi_wvalid(m_wvalid), .s_axi_wready(m_wready),
        .s_axi_bid(m_bid), .s_axi_bresp(m_bresp), .s_axi_buser(),
        .s_axi_bvalid(m_bvalid), .s_axi_bready(m_bready),
        .s_axi_arid(m_arid), .s_axi_araddr(m_araddr), .s_axi_arlen(m_arlen),
        .s_axi_arsize(m_arsize), .s_axi_arburst(m_arburst), .s_axi_arlock(m_arlock),
        .s_axi_arcache(m_arcache), .s_axi_arprot(m_arprot), .s_axi_arqos(m_arqos),
        .s_axi_arregion(m_arregion), .s_axi_aruser(1'b0),
        .s_axi_arvalid(m_arvalid), .s_axi_arready(m_arready),
        .s_axi_rid(m_rid), .s_axi_rdata(m_rdata), .s_axi_rresp(m_rresp),
        .s_axi_rlast(m_rlast), .s_axi_ruser(), .s_axi_rvalid(m_rvalid), .s_axi_rready(m_rready)
    );

    // ---------------- AXI-Lite master shared by pynq_ctl / pynq_mbox ----------------
    reg  [11:0] awaddr = 0, araddr = 0;
    reg  [31:0] wdata = 0;
    reg         awvalid = 0, wvalid = 0, arvalid = 0, sel_mb = 0;
    wire        ctl_awready, ctl_wready, ctl_bvalid, ctl_arready, ctl_rvalid;
    wire        mb_awready, mb_wready, mb_bvalid, mb_arready, mb_rvalid;
    wire [1:0]  ctl_bresp, ctl_rresp, mb_bresp, mb_rresp;
    wire [31:0] ctl_rdata, mb_rdata;
    wire awready = sel_mb ? mb_awready : ctl_awready;
    wire wready  = sel_mb ? mb_wready  : ctl_wready;
    wire bvalid  = sel_mb ? mb_bvalid  : ctl_bvalid;
    wire arready = sel_mb ? mb_arready : ctl_arready;
    wire rvalid  = sel_mb ? mb_rvalid  : ctl_rvalid;
    wire [31:0] rdata = sel_mb ? mb_rdata : ctl_rdata;

    pynq_ctl #(.ID_VALUE(32'h3155_4650), .VERSION_VALUE(32'h1)) u_ctl (
        .clk(clk), .rst_n(rst_n),
        .s_axi_awaddr(sel_mb ? 12'h0 : awaddr), .s_axi_awprot(3'b0),
        .s_axi_awvalid(sel_mb ? 1'b0 : awvalid), .s_axi_awready(ctl_awready),
        .s_axi_wdata(wdata), .s_axi_wstrb(4'hF),
        .s_axi_wvalid(sel_mb ? 1'b0 : wvalid), .s_axi_wready(ctl_wready),
        .s_axi_bresp(ctl_bresp), .s_axi_bvalid(ctl_bvalid), .s_axi_bready(!sel_mb),
        .s_axi_araddr(sel_mb ? 12'h0 : araddr), .s_axi_arprot(3'b0),
        .s_axi_arvalid(sel_mb ? 1'b0 : arvalid), .s_axi_arready(ctl_arready),
        .s_axi_rdata(ctl_rdata), .s_axi_rresp(ctl_rresp), .s_axi_rvalid(ctl_rvalid),
        .s_axi_rready(!sel_mb),
        .soc_reset(soc_reset), .soc_button(soc_button), .soc_led(soc_led), .soc_rst_n(soc_rst_n)
    );

    pynq_mbox u_mbox (
        .clk(clk), .rst_n(rst_n),
        .s_axi_awaddr(sel_mb ? awaddr : 12'h0), .s_axi_awprot(3'b0),
        .s_axi_awvalid(sel_mb ? awvalid : 1'b0), .s_axi_awready(mb_awready),
        .s_axi_wdata(wdata), .s_axi_wstrb(4'hF),
        .s_axi_wvalid(sel_mb ? wvalid : 1'b0), .s_axi_wready(mb_wready),
        .s_axi_bresp(mb_bresp), .s_axi_bvalid(mb_bvalid), .s_axi_bready(sel_mb),
        .s_axi_araddr(sel_mb ? araddr : 12'h0), .s_axi_arprot(3'b0),
        .s_axi_arvalid(sel_mb ? arvalid : 1'b0), .s_axi_arready(mb_arready),
        .s_axi_rdata(mb_rdata), .s_axi_rresp(mb_rresp), .s_axi_rvalid(mb_rvalid),
        .s_axi_rready(sel_mb),
        .link_flush(soc_reset), .mbox_txd(mbox_txd), .mbox_rxd(cpu_txd)
    );

    task axi_write(input mb, input [11:0] addr, input [31:0] data);
        begin
            @(negedge clk); sel_mb = mb; awaddr = addr; wdata = data; awvalid = 1; wvalid = 1;
            @(posedge clk); while (!(awready && wready)) @(posedge clk);
            @(negedge clk); awvalid = 0; wvalid = 0;
            while (!bvalid) @(posedge clk);
            @(negedge clk);
        end
    endtask

    task axi_read(input mb, input [11:0] addr, output [31:0] data);
        begin
            @(negedge clk); sel_mb = mb; araddr = addr; arvalid = 1;
            @(posedge clk); while (!arready) @(posedge clk);
            @(negedge clk); arvalid = 0;
            while (!rvalid) @(posedge clk);
            data = rdata;
            @(negedge clk);
        end
    endtask

    reg [31:0] v;
    reg [8*64-1:0] tail;    // last 64 received characters
    integer nbytes;
    reg pass_seen, done_seen, fail_seen;
    initial begin
        tail = 0; nbytes = 0; pass_seen = 0; done_seen = 0; fail_seen = 0;
        repeat (20) @(posedge clk);
        rst_n = 1;
        repeat (10) @(posedge clk);
        axi_read(0, 12'h008, v);
        if (v !== 32'h3155_4650) $fatal(1, "control ID %h", v);
        axi_read(1, 12'h01c, v);
        if (v !== 32'h4D42_4F58) $fatal(1, "mailbox ID %h", v);
        axi_read(0, 12'h000, v);
        if (!v[0] || soc_rst_n) $fatal(1, "SoC not held in reset by default");
        axi_write(0, 12'h000, 0);           // release CPU, as board_test.py does
        while (!done_seen) begin
            axi_read(1, 12'h00c, v);
            if (v[18]) $fatal(1, "mailbox RX overflow");
            if (v[15:0] != 0) begin
                axi_read(1, 12'h004, v);
                $write("%c", v[7:0]); $fflush;
                nbytes = nbytes + 1;
                tail = {tail[8*63-1:0], v[7:0]};
                if (tail[8*4-1:0] == "FAIL") fail_seen = 1;
                if (tail[8*4-1:0] == "DONE") done_seen = 1;
                // keys_rv32 ends its final failure branch with a bare "FAIL" line and no DONE
                if (tail[8*7-1:0] == {8'h0A, "FAIL", 8'h0D, 8'h0A}) done_seen = 1;
                if (tail[8*47-1:0] == "PASS key subsystem: enroll + reconstruct stable") pass_seen = 1;
            end
        end
        if (fail_seen || !pass_seen) $fatal(1, "TB_PYNQ_PUF: FAIL (pass=%0d fail=%0d bytes=%0d)", pass_seen, fail_seen, nbytes);
        axi_read(0, 12'h004, v);
        $display("\nTB_PYNQ_PUF: PASS bytes=%0d ctl_stat=%h t=%0t", nbytes, v, $time);
        $finish;
    end

    initial begin
        #200_000_000;   // 200 ms simulated watchdog
        $fatal(1, "TB_PYNQ_PUF: TIMEOUT");
    end
endmodule

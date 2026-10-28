`timescale 1ns / 1ps
// ============================================================================
// tb_ascon_sw - run the Ascon-AEAD128 software image on the RISC-V softcore.
//
// soc_top (50 MHz) + behavioral AXI4 BRAM slave (holds the firmware) + a UART
// monitor that decodes uart_txd and detects the "DONE"/"FAIL" markers the
// firmware prints. Exit code 0 only when DONE was seen and no FAIL occurred.
// ============================================================================
module tb_pynq_svc;

    localparam XLEN = 32;
    localparam BIT_PERIOD = 434;   // 50 MHz / 115200

    
    
    wire uart_rxd = mbox_txd;
    wire             uart_txd;
    wire [1:0] button = soc_button;
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
    soc_top #(.XLEN(XLEN), .UART_BAUD_CNT_MAX(16)) u_soc_top (
        .clk(clk),
        .rst_n(soc_rst_n),
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
        .s_axi_aresetn(soc_rst_n),
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
    wire [1:0] soc_led = led;
    wire        soc_rst_n;

    pynq_ctl u_ctl (
        .clk(clk), .rst_n(rst_n),
        .s_axi_awaddr(sel_mb ? 12'h0 : awaddr), .s_axi_awprot(3'b0),
        .s_axi_awvalid(sel_mb ? 1'b0 : awvalid), .s_axi_awready(ctl_awready),
        .s_axi_wdata(wdata), .s_axi_wstrb(4'hF),
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
        .s_axi_wdata(wdata), .s_axi_wstrb(4'hF),
        .s_axi_wvalid(sel_mb ? wvalid : 1'b0), .s_axi_wready(mb_wready),
        .s_axi_bresp(mb_bresp), .s_axi_bvalid(mb_bvalid),
        .s_axi_bready(sel_mb ? bready : 1'b0),
        .s_axi_araddr(sel_mb ? araddr : 12'h0), .s_axi_arprot(3'b0),
        .s_axi_arvalid(sel_mb ? arvalid : 1'b0), .s_axi_arready(mb_arready),
        .s_axi_rdata(mb_rdata), .s_axi_rresp(mb_rresp), .s_axi_rvalid(mb_rvalid),
        .s_axi_rready(sel_mb ? rready : 1'b0),
        .link_flush(soc_reset),
        .mbox_txd(mbox_txd),
        .mbox_rxd(uart_txd)
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


    reg [7:0] req[0:65535], expected[0:65535];
    integer sizes[0:1023], counts[0:1023];
    integer n, i, j, pos=0, ep=0, sz, total;
    reg [63:0] cycle_value;
    reg [31:0] value;
    reg [31:0] magic;
    reg [7:0] ch;
    task getbyte(output [7:0] c);
      begin
        value=0;
        while(value[15:0]==0) axi_read(1,12'h00c,value);
        if(value[18]) $fatal(1,"RX overflow");
        axi_read(1,12'h004,value); c=value[7:0];
      end
    endtask
    task service;
      begin
        magic=0;
        while(magic!=32'h59303153) begin getbyte(ch); magic=(magic<<8)|ch; end
        for(j=4;j<64;j=j+1) begin
          getbyte(ch);
          if(j==28 && ch!=7) $fatal(1,"real firmware boot KAT failed mask=%h",ch);
        end
      end
    endtask
    initial begin
      $readmemh("build/local/pynq_final/requests.hex",req);
      $readmemh("build/local/pynq_final/expected.hex",expected);
      $readmemh("build/local/pynq_final/sizes.hex",sizes);
      $readmemh("build/local/pynq_final/counts.hex",counts);
      repeat(10) @(negedge clk); rst_n=1;
      axi_write(0,0,0); service();
      for(n=0;n<37;n=n+1) begin
        for(i=0;i<sizes[n];i=i+1) begin
          value=32'h10000;
          while(value[16]) axi_read(1,12'h008,value);
          axi_write(1,0,req[pos]); pos=pos+1;
        end
        if(n==0) service();
        else begin
          cycle_value=0;
          for(i=0;i<counts[n];i=i+1) begin
            getbyte(ch);
            if(i>=40 && i<48) cycle_value=cycle_value | ({56'd0,ch} << ((i-40)*8));
            if(i<40 || i>=48) begin
              if(ch!==expected[ep+i]) $fatal(1,"response %0d byte %0d got %h expected %h",n,i,ch,expected[ep+i]);
            end
          end
          if(expected[ep+6][0] && cycle_value==0) $fatal(1,"missing mcycle delta");
          ep=ep+counts[n];
          $display("request %0d PASS (real RV32 firmware/AXI-Lite/UART)",n);
        end
      end
      // Abort a partial request, reset CPU/bridge, then perform a fresh handshake.
      axi_write(1,0,8'h59); axi_write(1,0,8'h30);
      repeat(400) @(negedge clk);
      axi_write(0,0,1); repeat(20) @(negedge clk);
      axi_read(1,12'h018,value); if(value!=0) $fatal(1,"reset left bytes");
      axi_write(0,0,0); service();
      for(i=0;i<20;i=i+1) axi_write(1,0,req[i]);
      service();
      $display("RESET_DURING_FRAME PASS");
      $display("PYNQ_SVC_COSIM PASS"); $finish;
    end
    initial begin
      repeat(10) begin
        repeat(100000) @(posedge clk);
        $display("progress pc=%h reset=%b txbytes=%d rxbytes=%d step=%d", u_soc_top.u_cpu_core.pc,soc_rst_n,u_mbox.tx_bytes,u_mbox.rx_bytes,n); $fflush;
      end
    end
    initial begin repeat(30000000) @(posedge clk); $fatal(1,"service watchdog"); end
endmodule

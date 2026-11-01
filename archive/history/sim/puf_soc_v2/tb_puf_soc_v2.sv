`timescale 1ns/1ps
module tb_puf_soc_v2 #(parameter DIAGNOSTIC=0);
    reg clk=0, ro_clk=0, rst_n=0;
    always #5 clk=~clk;
    always #20 ro_clk=~ro_clk;
    wire tx;
    wire [1:0] led;
`ifdef PUF_VENDOR_BRAM
`define PUF_SOC socwrapper.u_soc_axi_top.u_soc_top
    pynq_puf_soc_v2 #(.DIAGNOSTIC(DIAGNOSTIC)) socwrapper(
        .clk(clk),.ro_clk(ro_clk),.rst_n(rst_n),.soc_rst_n(rst_n),
        .uart_rxd(1'b1),.uart_txd(tx),.button(2'b0),.led(led));
`else
`define PUF_SOC soc
    wire awready,awvalid,awid,wready,wvalid,wlast,bvalid,bid,bready;
    wire arready,arvalid,arid,rvalid,rlast,rid,rready;
    wire [31:0] awaddr,wdata,araddr,rdata;
    wire [7:0] awlen,arlen;
    wire [2:0] awsize,arsize;
    wire [1:0] awburst,arburst,bresp,rresp;
    wire [3:0] wstrb;
    soc_top_puf_v2 #(.DIAGNOSTIC(DIAGNOSTIC),.UART_BAUD_CNT_MAX(16)) soc(
        .clk(clk),.ro_clk(ro_clk),.rst_n(rst_n),.uart_rxd(1'b1),.uart_txd(tx),.button(2'b0),.led(led),
        .m_awready(awready),.m_awvalid(awvalid),.m_awid(awid),.m_awaddr(awaddr),
        .m_awlen(awlen),.m_awsize(awsize),.m_awburst(awburst),
        .m_wready(wready),.m_wvalid(wvalid),.m_wlast(wlast),.m_wdata(wdata),.m_wstrb(wstrb),
        .m_bvalid(bvalid),.m_bid(bid),.m_bresp(bresp),.m_buser(1'b0),.m_bready(bready),
        .m_arready(arready),.m_arvalid(arvalid),.m_arid(arid),.m_araddr(araddr),
        .m_arlen(arlen),.m_arsize(arsize),.m_arburst(arburst),
        .m_rvalid(rvalid),.m_rlast(rlast),.m_rid(rid),.m_rdata(rdata),.m_rresp(rresp),.m_ruser(1'b0),.m_rready(rready));
    axi_slave_bram #(.ADDR_WIDTH(32),.DATA_WIDTH(32),.ID_WIDTH(1),.USER_WIDTH(1),
        .RAM_DEPTH(32768),.BASE_ADDR(32'h10000000)) mem(
        .s_axi_aclk(clk),.s_axi_aresetn(rst_n),
        .s_axi_awid(awid),.s_axi_awaddr(awaddr),.s_axi_awlen(awlen),.s_axi_awsize(awsize),
        .s_axi_awburst(awburst),.s_axi_awlock(1'b0),.s_axi_awcache(4'b0),.s_axi_awprot(3'b0),
        .s_axi_awqos(4'b0),.s_axi_awregion(4'b0),.s_axi_awuser(1'b0),
        .s_axi_awvalid(awvalid),.s_axi_awready(awready),
        .s_axi_wdata(wdata),.s_axi_wstrb(wstrb),.s_axi_wlast(wlast),.s_axi_wuser(1'b0),
        .s_axi_wvalid(wvalid),.s_axi_wready(wready),
        .s_axi_bid(bid),.s_axi_bresp(bresp),.s_axi_buser(),.s_axi_bvalid(bvalid),.s_axi_bready(bready),
        .s_axi_arid(arid),.s_axi_araddr(araddr),.s_axi_arlen(arlen),.s_axi_arsize(arsize),
        .s_axi_arburst(arburst),.s_axi_arlock(1'b0),.s_axi_arcache(4'b0),.s_axi_arprot(3'b0),
        .s_axi_arqos(4'b0),.s_axi_arregion(4'b0),.s_axi_aruser(1'b0),
        .s_axi_arvalid(arvalid),.s_axi_arready(arready),
        .s_axi_rid(rid),.s_axi_rdata(rdata),.s_axi_rresp(rresp),.s_axi_rlast(rlast),
        .s_axi_ruser(),.s_axi_rvalid(rvalid),.s_axi_rready(rready));
`endif
    // Actual board UART mailbox, drained by an AXI-Lite PS master model.
    reg rx_valid=0;
    reg [7:0] rx_byte=0;
    reg [11:0] mb_araddr=0;
    reg mb_arvalid=0,mb_rready=0;
    wire mb_arready,mb_rvalid;
    wire [31:0] mb_rdata;
    wire [1:0] mb_rresp;
    pynq_mbox mailbox(.clk(clk),.rst_n(rst_n),.link_flush(!rst_n),
        .mbox_rxd(tx),.mbox_txd(),
        .s_axi_awaddr(12'b0),.s_axi_awprot(3'b0),.s_axi_awvalid(1'b0),.s_axi_awready(),
        .s_axi_wdata(32'b0),.s_axi_wstrb(4'b0),.s_axi_wvalid(1'b0),.s_axi_wready(),
        .s_axi_bresp(),.s_axi_bvalid(),.s_axi_bready(1'b1),
        .s_axi_araddr(mb_araddr),.s_axi_arprot(3'b0),.s_axi_arvalid(mb_arvalid),.s_axi_arready(mb_arready),
        .s_axi_rdata(mb_rdata),.s_axi_rresp(mb_rresp),.s_axi_rvalid(mb_rvalid),.s_axi_rready(mb_rready));
    task mb_read(input [11:0] a,output [31:0] value);
        begin
            @(negedge clk); mb_araddr=a; mb_arvalid=1;
            @(posedge clk); while(!mb_arready) @(posedge clk);
            @(negedge clk); mb_arvalid=0;
            while(!mb_rvalid) @(negedge clk);
            value=mb_rdata;
            if(mb_rresp!=0) $fatal(1,"mailbox AXI read error");
            // Exercise PS response backpressure and verify registered hold.
            repeat(3) begin @(negedge clk); if(!mb_rvalid || mb_rdata!==value) $fatal(1,"mailbox response unstable"); end
            mb_rready=1; @(negedge clk); mb_rready=0;
        end
    endtask
    reg [31:0] mb_status,mb_data;
    initial begin
        wait(rst_n);
        mb_read('h1c,mb_data); if(mb_data!=32'h4d424f58) $fatal(1,"mailbox identity");
        forever begin
            mb_read('h0c,mb_status);
            if(mb_status[18]) $fatal(1,"mailbox overflow");
            if(mb_status[15:0]!=0) begin
                mb_read(4,mb_data); rx_byte=mb_data[7:0]; rx_valid=1;
                @(negedge clk); rx_valid=0;
            end
        end
    end
    reg [127:0] history=0;
    integer commands=0, cycles=0, reads=0;
    reg [31:0] expected_rdata;
    reg previous_read=0;
    always @(posedge clk) if(rst_n) begin
        cycles=cycles+1;
        if(`PUF_SOC.u_cpu_core.trap_en) $fatal(1,"CPU trap %h",`PUF_SOC.u_cpu_core.trap_cause);
        if(`PUF_SOC.puf_bus_fault) $fatal(1,"PUF bus fault");
        if(`PUF_SOC.dma_we && `PUF_SOC.dma_addr==4) commands=commands+1;
        if(previous_read && `PUF_SOC.dma_rdata !== expected_rdata) $fatal(1,"registered PUF response mismatch");
        previous_read=`PUF_SOC.dma_re;
        if(`PUF_SOC.dma_re) begin reads=reads+1; expected_rdata=`PUF_SOC.puf_rdata; end
        if(rx_valid) begin
            $write("%c",rx_byte); history={history[119:0],rx_byte};
            if(history[31:0]==32'h4641494c) $fatal(1,"firmware FAIL");
            if(history=="PUF_V2_TEST_PASS") begin
                if(commands!=(DIAGNOSTIC?14:11) || `PUF_SOC.u_puf.peripheral.kv) $fatal(1,"incomplete command contract %0d",commands);
                $display("\nTEST_PASS tb_puf_soc_v2 diagnostic=%0d commands=%0d reads=%0d cycles=%0d core=100MHz management=25MHz",DIAGNOSTIC,commands,reads,cycles);
                $finish;
            end
        end
    end
    initial begin repeat(20) @(negedge clk); rst_n=1; end
    initial begin #20000000; $fatal(1,"20ms SoC watchdog"); end
`undef PUF_SOC
endmodule
module tb_puf_soc_diag_v2;
    tb_puf_soc_v2 #(.DIAGNOSTIC(1)) test();
endmodule

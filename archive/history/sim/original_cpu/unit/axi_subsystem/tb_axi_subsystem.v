`timescale 1ns / 1ps

module tb_axi_subsystem;
    localparam XLEN = 32;
    localparam RAM_DEPTH = 256;

    reg              clk;
    reg              rst_n;

    reg              cache_re;
    reg              cache_we;
    reg  [XLEN-1:0]  cache_addr;
    reg  [XLEN-1:0]  cache_waddr;
    reg  [XLEN-1:0]  cache_wdata;
    reg  [XLEN/8-1:0] cache_wmask;
    reg  [2:0]       cache_arsize;
    reg              cache_rid;
    reg              cache_valid;
    wire             cache_ready;
    wire [XLEN-1:0]  cache_rdata;
    wire             cache_rdata_valid;
    wire             cache_rdata_last;
    wire             cache_rid_o;
    wire             write_full;
    wire             write_empty;
    wire             write_done_pulse;

    wire             axi_cpu_re;
    wire             axi_cpu_we;
    wire [XLEN-1:0]  axi_cpu_wdata;
    wire [XLEN-1:0]  axi_cpu_raddr;
    wire [XLEN-1:0]  axi_cpu_waddr;
    wire [XLEN/8-1:0] axi_cpu_wmask;
    wire             axi_cpu_wid;
    wire             axi_cpu_rid_req;
    wire             axi_cpu_rid_resp;
    wire [1:0]       axi_cpu_arburst;
    wire [2:0]       axi_cpu_arsize;
    wire [7:0]       axi_cpu_arlen;
    wire [1:0]       axi_cpu_awburst;
    wire [2:0]       axi_cpu_awsize;
    wire [7:0]       axi_cpu_awlen;
    wire             axi_cpu_wdata_valid;
    wire             axi_cpu_rdata_ready;
    wire             axi_cpu_wdata_ready;
    wire             axi_cpu_rdata_valid;
    wire [XLEN-1:0]  axi_cpu_rdata;
    wire [1:0]       axi_resp;
    wire             axi_resp_en;

    wire             m_awready;
    wire             m_awvalid;
    wire             m_awid;
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
    wire             m_wready;
    wire             m_wvalid;
    wire             m_wlast;
    wire [XLEN-1:0]  m_wdata;
    wire [XLEN/8-1:0] m_wstrb;
    wire             m_wuser;
    wire             m_bvalid;
    wire             m_bid;
    wire [1:0]       m_bresp;
    wire             m_buser;
    wire             m_bready;
    wire             m_arready;
    wire             m_arvalid;
    wire             m_arlock;
    wire             m_arid;
    wire [XLEN-1:0]  m_araddr;
    wire [7:0]       m_arlen;
    wire [2:0]       m_arsize;
    wire [1:0]       m_arburst;
    wire [3:0]       m_arcache;
    wire [2:0]       m_arprot;
    wire [3:0]       m_arqos;
    wire [3:0]       m_arregion;
    wire             m_aruser;
    wire             m_rvalid;
    wire             m_rlast;
    wire             m_rid;
    wire [XLEN-1:0]  m_rdata;
    wire [1:0]       m_rresp;
    wire             m_ruser;
    wire             m_rready;

    integer errors;

    cpu_axi_bridge #(.XLEN(XLEN)) u_bridge (
        .clk(clk),
        .rst_n(rst_n),
        .cache_re(cache_re),
        .cache_we(cache_we),
        .cache_addr(cache_addr),
        .cache_waddr(cache_waddr),
        .cache_wdata(cache_wdata),
        .cache_wmask(cache_wmask),
        .cache_arsize(cache_arsize),
        .cache_rid(cache_rid),
        .cache_valid(cache_valid),
        .cache_ready(cache_ready),
        .cache_rdata(cache_rdata),
        .cache_rdata_valid(cache_rdata_valid),
        .cache_rdata_last(cache_rdata_last),
        .cache_rid_o(cache_rid_o),
        .write_full(write_full),
        .write_empty(write_empty),
        .cpu_wdata_ready(axi_cpu_wdata_ready),
        .cpu_rdata_valid(axi_cpu_rdata_valid),
        .cpu_rdata(axi_cpu_rdata),
        .cpu_rid_i(axi_cpu_rid_resp),
        .resp(axi_resp),
        .resp_en(axi_resp_en),
        .cpu_re(axi_cpu_re),
        .cpu_we(axi_cpu_we),
        .cpu_wdata(axi_cpu_wdata),
        .cpu_raddr(axi_cpu_raddr),
        .cpu_waddr(axi_cpu_waddr),
        .cpu_wmask(axi_cpu_wmask),
        .cpu_wid(axi_cpu_wid),
        .cpu_rid(axi_cpu_rid_req),
        .cpu_arburst(axi_cpu_arburst),
        .cpu_arsize(axi_cpu_arsize),
        .cpu_arlen(axi_cpu_arlen),
        .cpu_awburst(axi_cpu_awburst),
        .cpu_awsize(axi_cpu_awsize),
        .cpu_awlen(axi_cpu_awlen),
        .cpu_wdata_valid(axi_cpu_wdata_valid),
        .cpu_rdata_ready(axi_cpu_rdata_ready),
        .rd_ready(),
        .write_done_pulse(write_done_pulse)
    );

    axi_master #(.XLEN(XLEN)) u_axi_master (
        .m_aclk(clk),
        .m_arst_n(rst_n),
        .m_awready(m_awready),
        .m_awvalid(m_awvalid),
        .m_awid(m_awid),
        .m_awaddr(m_awaddr),
        .m_awlen(m_awlen),
        .m_awsize(m_awsize),
        .m_awburst(m_awburst),
        .m_awlock(m_awlock),
        .m_awcache(m_awcache),
        .m_awprot(m_awprot),
        .m_awqos(m_awqos),
        .m_awregion(m_awregion),
        .m_awuser(m_awuser),
        .m_wready(m_wready),
        .m_wvalid(m_wvalid),
        .m_wlast(m_wlast),
        .m_wdata(m_wdata),
        .m_wstrb(m_wstrb),
        .m_wuser(m_wuser),
        .m_bvalid(m_bvalid),
        .m_bid(m_bid),
        .m_bresp(m_bresp),
        .m_buser(m_buser),
        .m_bready(m_bready),
        .m_arready(m_arready),
        .m_arvalid(m_arvalid),
        .m_arlock(m_arlock),
        .m_arid(m_arid),
        .m_araddr(m_araddr),
        .m_arlen(m_arlen),
        .m_arsize(m_arsize),
        .m_arburst(m_arburst),
        .m_arcache(m_arcache),
        .m_arprot(m_arprot),
        .m_arqos(m_arqos),
        .m_arregion(m_arregion),
        .m_aruser(m_aruser),
        .m_rvalid(m_rvalid),
        .m_rlast(m_rlast),
        .m_rid(m_rid),
        .m_rdata(m_rdata),
        .m_rresp(m_rresp),
        .m_ruser(m_ruser),
        .m_rready(m_rready),
        .cpu_re(axi_cpu_re),
        .cpu_we(axi_cpu_we),
        .cpu_wdata(axi_cpu_wdata),
        .cpu_raddr(axi_cpu_raddr),
        .cpu_waddr(axi_cpu_waddr),
        .cpu_wmask(axi_cpu_wmask),
        .cpu_wid(axi_cpu_wid),
        .cpu_rid(axi_cpu_rid_req),
        .cpu_arburst(axi_cpu_arburst),
        .cpu_arsize(axi_cpu_arsize),
        .cpu_arlen(axi_cpu_arlen),
        .cpu_awburst(axi_cpu_awburst),
        .cpu_awsize(axi_cpu_awsize),
        .cpu_awlen(axi_cpu_awlen),
        .cpu_wdata_valid(axi_cpu_wdata_valid),
        .cpu_rdata_ready(axi_cpu_rdata_ready),
        .cpu_rid_o(axi_cpu_rid_resp),
        .cpu_wdata_ready(axi_cpu_wdata_ready),
        .cpu_rdata_valid(axi_cpu_rdata_valid),
        .cpu_rdata(axi_cpu_rdata),
        .resp(axi_resp),
        .resp_en(axi_resp_en)
    );

    axi_slave_bram #(
        .ADDR_WIDTH(32),
        .DATA_WIDTH(XLEN),
        .ID_WIDTH(1),
        .USER_WIDTH(1),
        .RAM_DEPTH(RAM_DEPTH),
        .BASE_ADDR(32'h1000_0000),
        .INIT_FILE(""),
        .AR_LATENCY(2),
        .AW_LATENCY(1),
        .ARREADY_DELAY(1),
        .AWREADY_DELAY(1)
    ) u_axi_slave_bram (
        .s_axi_aclk(clk),
        .s_axi_aresetn(rst_n),
        .s_axi_awid(m_awid),
        .s_axi_awaddr(m_awaddr),
        .s_axi_awlen(m_awlen),
        .s_axi_awsize(m_awsize),
        .s_axi_awburst(m_awburst),
        .s_axi_awlock(m_awlock),
        .s_axi_awcache(m_awcache),
        .s_axi_awprot(m_awprot),
        .s_axi_awqos(m_awqos),
        .s_axi_awregion(m_awregion),
        .s_axi_awuser(m_awuser),
        .s_axi_awvalid(m_awvalid),
        .s_axi_awready(m_awready),
        .s_axi_wdata(m_wdata),
        .s_axi_wstrb(m_wstrb),
        .s_axi_wlast(m_wlast),
        .s_axi_wuser(m_wuser),
        .s_axi_wvalid(m_wvalid),
        .s_axi_wready(m_wready),
        .s_axi_bid(m_bid),
        .s_axi_bresp(m_bresp),
        .s_axi_buser(m_buser),
        .s_axi_bvalid(m_bvalid),
        .s_axi_bready(m_bready),
        .s_axi_arid(m_arid),
        .s_axi_araddr(m_araddr),
        .s_axi_arlen(m_arlen),
        .s_axi_arsize(m_arsize),
        .s_axi_arburst(m_arburst),
        .s_axi_arlock(m_arlock),
        .s_axi_arcache(m_arcache),
        .s_axi_arprot(m_arprot),
        .s_axi_arqos(m_arqos),
        .s_axi_arregion(m_arregion),
        .s_axi_aruser(m_aruser),
        .s_axi_arvalid(m_arvalid),
        .s_axi_arready(m_arready),
        .s_axi_rid(m_rid),
        .s_axi_rdata(m_rdata),
        .s_axi_rresp(m_rresp),
        .s_axi_rlast(m_rlast),
        .s_axi_ruser(m_ruser),
        .s_axi_rvalid(m_rvalid),
        .s_axi_rready(m_rready)
    );

`ifdef DUMP_FSDB
    initial begin
        $fsdbDumpfile("tb_axi_subsystem.fsdb");
        $fsdbDumpvars(0, tb_axi_subsystem, "+all");
    end
`else
    initial begin
        $dumpfile("tb_axi_subsystem.vcd");
        $dumpvars(0, tb_axi_subsystem);
    end
`endif

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task expect_bit;
        input actual;
        input expected;
        input [255:0] name;
        begin
            if (actual !== expected) begin
                $display("[FAIL] %0s actual=%0b expected=%0b", name, actual, expected);
                errors = errors + 1;
            end else begin
                $display("[PASS] %0s = %0b", name, actual);
            end
        end
    endtask

    task expect_word;
        input [XLEN-1:0] actual;
        input [XLEN-1:0] expected;
        input [255:0] name;
        begin
            if (actual !== expected) begin
                $display("[FAIL] %0s actual=0x%08h expected=0x%08h", name, actual, expected);
                errors = errors + 1;
            end else begin
                $display("[PASS] %0s = 0x%08h", name, actual);
            end
        end
    endtask

    task issue_write;
        input [XLEN-1:0] addr;
        input [XLEN-1:0] data;
        input [XLEN/8-1:0] mask;
        integer timeout;
        begin
            cache_waddr = addr;
            cache_wdata = data;
            cache_wmask = mask;
            cache_we = 1'b1;
            @(posedge clk);
            #1;
            cache_we = 1'b0;

            timeout = 0;
            while (!write_done_pulse && timeout < 80) begin
                @(posedge clk);
                #1;
                timeout = timeout + 1;
            end

            if (!write_done_pulse) begin
                $display("[FAIL] write timeout addr=0x%08h", addr);
                errors = errors + 1;
            end else begin
                $display("[PASS] write completed addr=0x%08h data=0x%08h mask=0x%0h", addr, data, mask);
            end
        end
    endtask

    task issue_read4;
        input [XLEN-1:0] addr;
        input rid;
        input [XLEN-1:0] e0;
        input [XLEN-1:0] e1;
        input [XLEN-1:0] e2;
        input [XLEN-1:0] e3;
        input [255:0] name;
        reg [XLEN-1:0] expected [0:3];
        integer beat;
        integer timeout;
        begin
            expected[0] = e0;
            expected[1] = e1;
            expected[2] = e2;
            expected[3] = e3;
            timeout = 0;
            while (!cache_ready && timeout < 80) begin
                @(posedge clk);
                #1;
                timeout = timeout + 1;
            end
            if (!cache_ready) begin
                $display("[FAIL] %0s bridge not ready before read", name);
                errors = errors + 1;
            end
            cache_addr = addr;
            cache_rid = rid;
            cache_arsize = 3'b010;
            cache_re = 1'b1;
            cache_valid = 1'b1;
            @(posedge clk);
            #1;
            cache_re = 1'b0;
            cache_valid = 1'b0;

            beat = 0;
            timeout = 0;
            while (beat < 4 && timeout < 160) begin
                @(posedge clk);
                #1;
                timeout = timeout + 1;
                if (cache_rdata_valid) begin
                    expect_word(cache_rdata, expected[beat], {name, " data beat"});
                    expect_bit(cache_rid_o, rid, {name, " rid beat"});
                    expect_bit(cache_rdata_last, (beat == 3), {name, " last beat"});
                    beat = beat + 1;
                end
            end

            if (beat != 4) begin
                $display("[FAIL] %0s timed out after %0d beats", name, beat);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        errors = 0;
        rst_n = 1'b0;
        cache_re = 1'b0;
        cache_we = 1'b0;
        cache_addr = 32'h1000_0000;
        cache_waddr = 32'h1000_0000;
        cache_wdata = 32'h0;
        cache_wmask = 4'h0;
        cache_arsize = 3'b010;
        cache_rid = 1'b0;
        cache_valid = 1'b0;

        u_axi_slave_bram.u_ram.mem[0] = 32'h1111_0000;
        u_axi_slave_bram.u_ram.mem[1] = 32'h1111_0001;
        u_axi_slave_bram.u_ram.mem[2] = 32'h1111_0002;
        u_axi_slave_bram.u_ram.mem[3] = 32'h1111_0003;
        u_axi_slave_bram.u_ram.mem[4] = 32'h2222_0000;
        u_axi_slave_bram.u_ram.mem[5] = 32'h2222_0001;
        u_axi_slave_bram.u_ram.mem[6] = 32'h2222_0002;
        u_axi_slave_bram.u_ram.mem[7] = 32'h2222_0003;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (3) @(posedge clk);
        #1;

        issue_read4(32'h1000_0000, 1'b0,
                    32'h1111_0000, 32'h1111_0001,
                    32'h1111_0002, 32'h1111_0003,
                    "icache-id wrap read");

        issue_read4(32'h1000_0008, 1'b1,
                    32'h1111_0002, 32'h1111_0003,
                    32'h1111_0000, 32'h1111_0001,
                    "dcache-id wrap read from word2");

        issue_write(32'h1000_0010, 32'hABCD_5678, 4'b1111);
        issue_read4(32'h1000_0010, 1'b1,
                    32'hABCD_5678, 32'h2222_0001,
                    32'h2222_0002, 32'h2222_0003,
                    "read after full-word write");

        issue_write(32'h1000_0014, 32'hFFFF_00AA, 4'b0011);
        issue_read4(32'h1000_0010, 1'b1,
                    32'hABCD_5678, 32'h2222_00AA,
                    32'h2222_0002, 32'h2222_0003,
                    "read after masked write");

        if (errors == 0) begin
            $display("[RESULT] tb_axi_subsystem PASS");
        end else begin
            $display("[RESULT] tb_axi_subsystem FAIL errors=%0d", errors);
            $fatal(1);
        end
        $finish;
    end
endmodule

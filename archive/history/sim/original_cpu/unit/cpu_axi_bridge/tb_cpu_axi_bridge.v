`timescale 1ns / 1ps

module tb_cpu_axi_bridge;
    localparam XLEN = 32;

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

    reg              cpu_wdata_ready;
    reg              cpu_rdata_valid;
    reg  [XLEN-1:0]  cpu_rdata;
    reg              cpu_rid_i;
    reg  [1:0]       resp;
    reg              resp_en;

    wire             cpu_re;
    wire             cpu_we;
    wire [XLEN-1:0]  cpu_wdata;
    wire [XLEN-1:0]  cpu_raddr;
    wire [XLEN-1:0]  cpu_waddr;
    wire [XLEN/8-1:0] cpu_wmask;
    wire             cpu_wid;
    wire             cpu_rid;
    wire [1:0]       cpu_arburst;
    wire [2:0]       cpu_arsize;
    wire [7:0]       cpu_arlen;
    wire [1:0]       cpu_awburst;
    wire [2:0]       cpu_awsize;
    wire [7:0]       cpu_awlen;
    wire             cpu_wdata_valid;
    wire             cpu_rdata_ready;
    wire             rd_ready;
    wire             write_done_pulse;

    integer errors;

    cpu_axi_bridge #(.XLEN(XLEN)) dut (
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
        .cpu_wdata_ready(cpu_wdata_ready),
        .cpu_rdata_valid(cpu_rdata_valid),
        .cpu_rdata(cpu_rdata),
        .cpu_rid_i(cpu_rid_i),
        .resp(resp),
        .resp_en(resp_en),
        .cpu_re(cpu_re),
        .cpu_we(cpu_we),
        .cpu_wdata(cpu_wdata),
        .cpu_raddr(cpu_raddr),
        .cpu_waddr(cpu_waddr),
        .cpu_wmask(cpu_wmask),
        .cpu_wid(cpu_wid),
        .cpu_rid(cpu_rid),
        .cpu_arburst(cpu_arburst),
        .cpu_arsize(cpu_arsize),
        .cpu_arlen(cpu_arlen),
        .cpu_awburst(cpu_awburst),
        .cpu_awsize(cpu_awsize),
        .cpu_awlen(cpu_awlen),
        .cpu_wdata_valid(cpu_wdata_valid),
        .cpu_rdata_ready(cpu_rdata_ready),
        .rd_ready(rd_ready),
        .write_done_pulse(write_done_pulse)
    );

`ifdef DUMP_FSDB
    initial begin
        $fsdbDumpfile("tb_cpu_axi_bridge.fsdb");
        $fsdbDumpvars(0, tb_cpu_axi_bridge, "+all");
    end
`else
    initial begin
        $dumpfile("tb_cpu_axi_bridge.vcd");
        $dumpvars(0, tb_cpu_axi_bridge);
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

    task start_read;
        input [XLEN-1:0] addr;
        input rid;
        input [2:0] arsize;
        begin
            cache_addr = addr;
            cache_rid = rid;
            cache_arsize = arsize;
            cache_re = 1'b1;
            cache_valid = 1'b1;
            @(posedge clk);
            #1;
            cache_re = 1'b0;
            cache_valid = 1'b0;
        end
    endtask

    task send_rbeat;
        input [XLEN-1:0] data;
        input rid;
        input last_expected;
        input [255:0] name;
        begin
            cpu_rdata = data;
            cpu_rid_i = rid;
            cpu_rdata_valid = 1'b1;
            #1;
            expect_bit(cache_rdata_valid, 1'b1, {name, " cache valid"});
            expect_word(cache_rdata, data, {name, " cache data"});
            expect_bit(cache_rid_o, rid, {name, " returned rid"});
            expect_bit(cache_rdata_last, last_expected, {name, " last"});
            @(posedge clk);
            #1;
            cpu_rdata_valid = 1'b0;
        end
    endtask

    task push_write;
        input [XLEN-1:0] addr;
        input [XLEN-1:0] data;
        input [XLEN/8-1:0] mask;
        begin
            cache_waddr = addr;
            cache_wdata = data;
            cache_wmask = mask;
            cache_we = 1'b1;
            @(posedge clk);
            #1;
            cache_we = 1'b0;
        end
    endtask

    initial begin
        errors = 0;
        rst_n = 1'b0;
        cache_re = 1'b0;
        cache_we = 1'b0;
        cache_addr = 32'h0;
        cache_waddr = 32'h0;
        cache_wdata = 32'h0;
        cache_wmask = 4'h0;
        cache_arsize = 3'b010;
        cache_rid = 1'b0;
        cache_valid = 1'b0;
        cpu_wdata_ready = 1'b0;
        cpu_rdata_valid = 1'b0;
        cpu_rdata = 32'h0;
        cpu_rid_i = 1'b0;
        resp = 2'b00;
        resp_en = 1'b0;

        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);
        #1;

        expect_bit(cache_ready, 1'b1, "ready after reset");
        expect_bit(write_empty, 1'b1, "write fifo empty after reset");

        start_read(32'h1000_0100, 1'b1, 3'b010);
        expect_bit(cpu_re, 1'b1, "cpu read pulse");
        expect_word(cpu_raddr, 32'h1000_0100, "latched read address");
        expect_bit(cpu_rid, 1'b1, "latched read id");
        expect_word({29'h0, cpu_arsize}, 32'h0000_0002, "latched arsize");
        expect_word({24'h0, cpu_arlen}, 32'h0000_0003, "read burst length is four beats");
        expect_bit(cache_ready, 1'b0, "busy during outstanding read");

        @(posedge clk);
        #1;
        send_rbeat(32'hA000_0000, 1'b1, 1'b0, "read beat0");
        send_rbeat(32'hA000_0001, 1'b1, 1'b0, "read beat1");
        send_rbeat(32'hA000_0002, 1'b1, 1'b0, "read beat2");
        send_rbeat(32'hA000_0003, 1'b1, 1'b1, "read beat3");
        @(posedge clk);
        #1;
        expect_bit(cache_ready, 1'b1, "ready after four read beats");

        push_write(32'h1000_0200, 32'hDEAD_BEEF, 4'b1111);
        expect_bit(write_empty, 1'b0, "write fifo receives entry");
        @(posedge clk);
        #1;
        expect_bit(cpu_we, 1'b1, "cpu write request starts");
        expect_bit(cpu_wdata_valid, 1'b1, "cpu write data valid");
        expect_word(cpu_waddr, 32'h1000_0200, "write address forwarded");
        expect_word(cpu_wdata, 32'hDEAD_BEEF, "write data forwarded");
        expect_word({28'h0, cpu_wmask}, 32'h0000_000F, "write mask forwarded");
        expect_bit(cpu_wid, 1'b1, "write id is dcache");

        cpu_wdata_ready = 1'b1;
        @(posedge clk);
        #1;
        cpu_wdata_ready = 1'b0;
        expect_bit(cpu_we, 1'b0, "write request drops after handshake");
        expect_bit(write_empty, 1'b1, "fifo empties after write handshake");

        resp = 2'b00;
        resp_en = 1'b1;
        @(posedge clk);
        #1;
        expect_bit(write_done_pulse, 1'b1, "write_done on response with empty fifo");
        resp_en = 1'b0;

        cpu_wdata_ready = 1'b0;
        push_write(32'h1000_0300, 32'h0000_0000, 4'h1);
        push_write(32'h1000_0304, 32'h0000_0001, 4'h2);
        push_write(32'h1000_0308, 32'h0000_0002, 4'h4);
        push_write(32'h1000_030C, 32'h0000_0003, 4'h8);
        expect_bit(write_full, 1'b1, "write fifo full after four queued writes");
        push_write(32'h1000_0310, 32'hBAD0_0004, 4'hF);
        expect_bit(write_full, 1'b1, "write fifo remains full when overflow write is ignored");

        cpu_wdata_ready = 1'b1;
        @(posedge clk);
        #1;
        cpu_wdata_ready = 1'b0;
        expect_bit(write_full, 1'b0, "write fifo not full after one dequeue");

        if (errors == 0) begin
            $display("[RESULT] tb_cpu_axi_bridge PASS");
        end else begin
            $display("[RESULT] tb_cpu_axi_bridge FAIL errors=%0d", errors);
            $fatal(1);
        end
        $finish;
    end
endmodule

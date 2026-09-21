`timescale 1ns / 1ps

module tb_dcache;
    localparam XLEN = 32;

    reg              clk;
    reg              rst_n;
    reg  [XLEN-1:0]  cpu_addr_i;
    reg  [XLEN-1:0]  cpu_wdata_i;
    reg  [XLEN/8-1:0] cpu_wmask_i;
    reg              cpu_re_i;
    reg              cpu_we_i;
    reg              cpu_req_stall_i;
    wire [XLEN-1:0]  cpu_rdata_o;
    wire             cpu_stall_o;

    wire [XLEN-1:0]  bus_addr_o;
    wire             bus_mem_re_o;
    wire             bus_mem_we_o;
    wire             bus_mmio_re_o;
    wire             bus_mmio_we_o;
    wire [XLEN/8-1:0] bus_wmask_o;
    wire [XLEN-1:0]  bus_wdata_o;
    wire             bus_load_miss_o;
    wire             bus_store_miss_o;
    reg  [XLEN-1:0]  bus_rdata_i;
    reg              bus_rdata_valid_i;

    integer errors;

    dcache #(
        .XLEN(XLEN),
        .DCACHE_SET_SIZE(4),
        .DCACHE_LINE_WORDS(4)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .cpu_addr_i(cpu_addr_i),
        .cpu_wdata_i(cpu_wdata_i),
        .cpu_wmask_i(cpu_wmask_i),
        .cpu_re_i(cpu_re_i),
        .cpu_we_i(cpu_we_i),
        .cpu_req_stall_i(cpu_req_stall_i),
        .cpu_rdata_o(cpu_rdata_o),
        .cpu_stall_o(cpu_stall_o),
        .bus_addr_o(bus_addr_o),
        .bus_mem_re_o(bus_mem_re_o),
        .bus_mem_we_o(bus_mem_we_o),
        .bus_mmio_re_o(bus_mmio_re_o),
        .bus_mmio_we_o(bus_mmio_we_o),
        .bus_wmask_o(bus_wmask_o),
        .bus_wdata_o(bus_wdata_o),
        .bus_load_miss_o(bus_load_miss_o),
        .bus_store_miss_o(bus_store_miss_o),
        .bus_rdata_i(bus_rdata_i),
        .bus_rdata_valid_i(bus_rdata_valid_i)
    );

`ifdef DUMP_FSDB
    initial begin
        $fsdbDumpfile("tb_dcache.fsdb");
        $fsdbDumpvars(0, tb_dcache, "+all");
    end
`else
    initial begin
        $dumpfile("tb_dcache.vcd");
        $dumpvars(0, tb_dcache);
    end
`endif

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task fail_msg;
        input [255:0] name;
        begin
            $display("[FAIL] %0s", name);
            errors = errors + 1;
        end
    endtask

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

    task wait_ready;
        input [255:0] name;
        integer timeout;
        begin
            timeout = 0;
            while (cpu_stall_o && timeout < 30) begin
                @(posedge clk);
                #1;
                timeout = timeout + 1;
            end
            if (cpu_stall_o)
                fail_msg(name);
        end
    endtask

    task drive_fill4;
        input [XLEN-1:0] w0;
        input [XLEN-1:0] w1;
        input [XLEN-1:0] w2;
        input [XLEN-1:0] w3;
        begin
            @(posedge clk);
            #1;
            bus_rdata_i = w0;
            bus_rdata_valid_i = 1'b1;
            @(posedge clk);
            #1;
            bus_rdata_i = w1;
            @(posedge clk);
            #1;
            bus_rdata_i = w2;
            @(posedge clk);
            #1;
            bus_rdata_i = w3;
            @(posedge clk);
            #1;
            bus_rdata_valid_i = 1'b0;
            bus_rdata_i = {XLEN{1'b0}};
        end
    endtask

    task load_miss_and_fill;
        input [XLEN-1:0] addr;
        input [XLEN-1:0] w0;
        input [XLEN-1:0] w1;
        input [XLEN-1:0] w2;
        input [XLEN-1:0] w3;
        input [XLEN-1:0] expected;
        input [255:0] name;
        begin
            cpu_addr_i = addr;
            cpu_re_i = 1'b1;
            cpu_we_i = 1'b0;
            #1;
            @(posedge clk);
            #1;
            expect_bit(cpu_stall_o, 1'b1, {name, " stalls after miss is registered"});
            expect_bit(bus_mem_re_o, 1'b1, {name, " bus load miss"});
            expect_bit(bus_load_miss_o, 1'b1, {name, " load miss pulse"});
            expect_word(bus_addr_o, addr, {name, " miss addr capture"});
            cpu_re_i = 1'b0;
            drive_fill4(w0, w1, w2, w3);
            wait_ready({name, " ready after fill"});
            expect_word(cpu_rdata_o, expected, {name, " fill returns requested word"});
        end
    endtask

    task load_hit;
        input [XLEN-1:0] addr;
        input [XLEN-1:0] expected;
        input [255:0] name;
        begin
            cpu_addr_i = addr;
            cpu_re_i = 1'b1;
            cpu_we_i = 1'b0;
            #1;
            expect_bit(bus_mem_re_o, 1'b0, {name, " no bus load"});
            @(posedge clk);
            #1;
            @(posedge clk);
            #1;
            wait_ready({name, " hit data ready"});
            expect_word(cpu_rdata_o, expected, name);
            @(posedge clk);
            #1;
            cpu_re_i = 1'b0;
        end
    endtask

    task store_access;
        input [XLEN-1:0] addr;
        input [XLEN-1:0] wdata;
        input [XLEN/8-1:0] wmask;
        input expected_store_miss;
        input [255:0] name;
        begin
            cpu_addr_i = addr;
            cpu_wdata_i = wdata;
            cpu_wmask_i = wmask;
            cpu_re_i = 1'b0;
            cpu_we_i = 1'b1;
            #1;
            @(posedge clk);
            #1;
            cpu_we_i = 1'b0;
            expect_bit(bus_mem_we_o, 1'b1, {name, " memory write-through pulse"});
            expect_word(bus_addr_o, addr, {name, " write addr"});
            expect_word(bus_wdata_o, wdata, {name, " write data"});
            expect_word({28'h0, bus_wmask_o}, {28'h0, wmask}, {name, " write mask"});
            expect_bit(bus_store_miss_o, expected_store_miss, {name, " store miss flag"});
        end
    endtask

    initial begin
        errors = 0;
        rst_n = 1'b0;
        cpu_addr_i = 32'h1000_0000;
        cpu_wdata_i = 32'h0;
        cpu_wmask_i = 4'h0;
        cpu_re_i = 1'b0;
        cpu_we_i = 1'b0;
        cpu_req_stall_i = 1'b0;
        bus_rdata_i = 32'h0;
        bus_rdata_valid_i = 1'b0;

        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        #1;

        load_miss_and_fill(32'h1000_0000,
                           32'hAAAA_0000, 32'hAAAA_0001,
                           32'hAAAA_0002, 32'hAAAA_0003,
                           32'hAAAA_0000,
                           "cold cacheable load");

        load_hit(32'h1000_0004, 32'hAAAA_0001, "same line load hit word1");
        load_hit(32'h1000_0008, 32'hAAAA_0002, "same line load hit word2");

        store_access(32'h1000_0004, 32'hCCCC_DD00, 4'b0011, 1'b0, "store hit byte-mask");
        load_hit(32'h1000_0004, 32'hAAAA_DD00, "store hit updates selected bytes");

        store_access(32'h1000_0040, 32'hBBBB_1234, 4'b1111, 1'b1, "store miss reports uncached tag");
        cpu_addr_i = 32'h1000_0040;
        cpu_re_i = 1'b1;
        #1;
        @(posedge clk);
        #1;
        expect_bit(bus_mem_re_o, 1'b1, "store miss target is still a load miss");
        cpu_re_i = 1'b0;
        drive_fill4(32'hEEEE_0000, 32'hEEEE_0001, 32'hEEEE_0002, 32'hEEEE_0003);
        wait_ready("ready after store-miss target refill");
        expect_word(cpu_rdata_o, 32'hEEEE_0000, "refill after store miss returns word0");

        cpu_addr_i = 32'h2000_0000;
        cpu_re_i = 1'b1;
        bus_rdata_i = 32'hFACE_CAFE;
        #1;
        @(posedge clk);
        #1;
        expect_bit(bus_mmio_re_o, 1'b1, "uncached read routes to MMIO");
        cpu_re_i = 1'b0;
        @(posedge clk);
        #1;
        expect_word(cpu_rdata_o, 32'hFACE_CAFE, "uncached read data returned");

        cpu_addr_i = 32'h2001_0004;
        cpu_wdata_i = 32'h1234_ABCD;
        cpu_wmask_i = 4'hF;
        cpu_we_i = 1'b1;
        #1;
        @(posedge clk);
        #1;
        cpu_we_i = 1'b0;
        expect_bit(bus_mmio_we_o, 1'b1, "uncached write routes to MMIO");
        expect_bit(bus_mem_we_o, 1'b0, "uncached write does not assert memory write");

        cpu_req_stall_i = 1'b1;
        cpu_addr_i = 32'h1000_0080;
        cpu_re_i = 1'b1;
        #1;
        expect_bit(bus_mem_re_o, 1'b0, "pipeline stall suppresses new dcache request");
        cpu_req_stall_i = 1'b0;
        cpu_re_i = 1'b0;

        if (errors == 0) begin
            $display("[RESULT] tb_dcache PASS");
        end else begin
            $display("[RESULT] tb_dcache FAIL errors=%0d", errors);
            $fatal(1);
        end
        $finish;
    end
endmodule

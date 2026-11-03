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

    // Drive on falling edges; sample registered DUT outputs after NBA (#1).
    // A single-cycle request is the handshake: this interface has no ready pin.
    // Queue independent expected transactions before driving a CPU request.
    localparam READ_MEM=1, WRITE_MEM=2, READ_MMIO=3, WRITE_MMIO=4;
    localparam REQUEST_BOUND=8, COMPLETION_BOUND=30;
    integer expected_kind[0:63];
    reg [31:0] expected_addr[0:63], expected_data[0:63];
    reg [3:0] expected_mask[0:63];
    reg expected_store_miss[0:63];
    integer head=0, tail=0, read_requests=0, write_requests=0;
    integer mmio_reads=0, mmio_writes=0, fill_beats=0, completed_fills=0, aborted_fills=0;
    integer beat_in_request=0, assertions=0, kind;
    reg filling=0;

    task fail_msg;
        input [1023:0] name;
        begin
            $display("[FAIL] time=%0t %0s", $time, name);
            errors = errors + 1;
        end
    endtask

    task expect_bit;
        input actual;
        input expected;
        input [1023:0] name;
        begin
            assertions = assertions + 1;
            if (actual !== expected) begin
                $display("[FAIL] time=%0t %0s actual=%0b expected=%0b", $time, name, actual, expected);
                errors = errors + 1;
            end else begin
                $display("[PASS] %0s = %0b", name, actual);
            end
        end
    endtask

    task expect_word;
        input [XLEN-1:0] actual;
        input [XLEN-1:0] expected;
        input [1023:0] name;
        begin
            assertions = assertions + 1;
            if (actual !== expected) begin
                $display("[FAIL] time=%0t %0s actual=0x%08h expected=0x%08h", $time, name, actual, expected);
                errors = errors + 1;
            end else begin
                $display("[PASS] %0s = 0x%08h", name, actual);
            end
        end
    endtask

    task enqueue;
        input integer request_kind;
        input [31:0] addr, data;
        input [3:0] mask;
        input miss;
        begin
            if(tail>=64) $fatal(1,"expected transaction queue exhausted");
            expected_kind[tail]=request_kind; expected_addr[tail]=addr;
            expected_data[tail]=data; expected_mask[tail]=mask;
            expected_store_miss[tail]=miss; tail=tail+1;
        end
    endtask

    always @(posedge clk) begin
        #1;
        if(!rst_n) begin
            if(filling) aborted_fills=aborted_fills+1;
            filling=0; beat_in_request=0;
            if({bus_mem_re_o,bus_mem_we_o,bus_mmio_re_o,bus_mmio_we_o}!==4'b0)
                $fatal(1,"request escaped reset");
        end else begin
            if(bus_load_miss_o!==bus_mem_re_o)
                $fatal(1,"load-miss qualifier does not match memory read");
            if(bus_store_miss_o && !bus_mem_we_o)
                $fatal(1,"store-miss qualifier without memory write");
            kind=0;
            case({bus_mem_re_o,bus_mem_we_o,bus_mmio_re_o,bus_mmio_we_o})
              4'b0000: kind=0;
              4'b1000: kind=READ_MEM;
              4'b0100: kind=WRITE_MEM;
              4'b0010: kind=READ_MMIO;
              4'b0001: kind=WRITE_MMIO;
              default: $fatal(1,"overlapping or unknown request directions");
            endcase
            if(kind!=0) begin
                if(head>=tail) $fatal(1,"unexpected or duplicate bus request");
                if(kind!=expected_kind[head]) $fatal(1,"bus request direction/order mismatch");
                expect_word(bus_addr_o,expected_addr[head],"transaction address");
                if(kind==WRITE_MEM || kind==WRITE_MMIO) begin
                    expect_word(bus_wdata_o,expected_data[head],"transaction write data");
                    expect_word({28'b0,bus_wmask_o},{28'b0,expected_mask[head]},"transaction write mask");
                    expect_bit(bus_store_miss_o,expected_store_miss[head],"transaction store-miss flag");
                end
                if(kind==READ_MEM) begin
                    if(filling) $fatal(1,"duplicate read during outstanding fill");
                    filling=1;beat_in_request=0;read_requests=read_requests+1;
                end
                if(kind==WRITE_MEM) write_requests=write_requests+1;
                if(kind==READ_MMIO) mmio_reads=mmio_reads+1;
                if(kind==WRITE_MMIO) mmio_writes=mmio_writes+1;
                head=head+1;
            end
            if(bus_rdata_valid_i) begin
                if(!filling || beat_in_request>=4) $fatal(1,"unsolicited/extra fill beat");
                fill_beats=fill_beats+1;beat_in_request=beat_in_request+1;
                if(beat_in_request==4) begin filling=0;completed_fills=completed_fills+1;end
            end
        end
    end

    task wait_request;
        input integer sequence_number;
        input [1023:0] name;
        integer timeout;
        begin
            timeout=0;
            while(head<sequence_number && timeout<REQUEST_BOUND) begin
                @(posedge clk);#2;timeout=timeout+1;
            end
            if(head!=sequence_number) $fatal(1,"request timeout/count mismatch: %0s",name);
        end
    endtask

    task wait_ready;
        input [1023:0] name;
        integer timeout;
        begin
            timeout = 0;
            while (cpu_stall_o && timeout < COMPLETION_BOUND) begin
                @(posedge clk);
                #2;
                timeout = timeout + 1;
            end
            if (cpu_stall_o)
                $fatal(1,"completion timeout: %0s",name);
        end
    endtask

    task drive_fill4;
        input [XLEN-1:0] w0;
        input [XLEN-1:0] w1;
        input [XLEN-1:0] w2;
        input [XLEN-1:0] w3;
        begin
            @(negedge clk);
            bus_rdata_i = $test$plusargs("BAD_FILL") ? (w0^32'h1) : w0;
            bus_rdata_valid_i = 1'b1;
            @(negedge clk);
            bus_rdata_i = w1;
            @(negedge clk);
            bus_rdata_i = w2;
            @(negedge clk);
            bus_rdata_i = w3;
            @(negedge clk);
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
        input [1023:0] name;
        integer before_reads, before_beats;
        begin
            wait_ready(name);
            @(negedge clk);
            before_reads=read_requests; before_beats=fill_beats;
            enqueue(READ_MEM,addr,0,0,0);
            cpu_addr_i = addr;
            cpu_re_i = 1'b1;
            cpu_we_i = 1'b0;
            @(posedge clk);
            #2;
            expect_bit(cpu_stall_o, 1'b1, {name, " stalls after miss is registered"});
            @(negedge clk);
            cpu_re_i = 1'b0;
            wait_request(tail,name);
            expect_bit(bus_mem_re_o, 1'b1, {name, " bus load miss"});
            expect_bit(bus_load_miss_o, 1'b1, {name, " load miss pulse"});
            expect_word(bus_addr_o, addr, {name, " miss addr capture"});
            drive_fill4(w0, w1, w2, w3);
            wait_ready({name, " ready after fill"});
            expect_word(cpu_rdata_o, expected, {name, " fill returns requested word"});
            expect_word(read_requests-before_reads,1,{name," exactly one read request"});
            expect_word(fill_beats-before_beats,4,{name," exactly four fill beats"});
        end
    endtask

    task load_hit;
        input [XLEN-1:0] addr;
        input [XLEN-1:0] expected;
        input [1023:0] name;
        integer before_reads;
        begin
            wait_ready(name);
            @(negedge clk);
            before_reads=read_requests;
            cpu_addr_i = addr;
            cpu_re_i = 1'b1;
            cpu_we_i = 1'b0;
            @(posedge clk);
            #2;
            expect_bit(bus_mem_re_o, 1'b0, {name, " no bus load"});
            wait_ready({name, " hit data ready"});
            expect_word(cpu_rdata_o, expected, name);
            expect_word(read_requests-before_reads,0,{name," no read transactions"});
            @(negedge clk);
            cpu_re_i = 1'b0;
        end
    endtask

    task store_access;
        input [XLEN-1:0] addr;
        input [XLEN-1:0] wdata;
        input [XLEN/8-1:0] wmask;
        input expected_store_miss;
        input [1023:0] name;
        begin
            wait_ready(name);
            @(negedge clk);
            enqueue(WRITE_MEM,addr,wdata,wmask,expected_store_miss);
            cpu_addr_i = addr;
            cpu_wdata_i = wdata;
            cpu_wmask_i = wmask;
            cpu_re_i = 1'b0;
            cpu_we_i = 1'b1;
            wait_request(tail,name);
            expect_bit(bus_mem_we_o, 1'b1, {name, " memory write-through pulse"});
            expect_word(bus_addr_o, addr, {name, " write addr"});
            expect_word(bus_wdata_o, wdata, {name, " write data"});
            expect_word({28'h0, bus_wmask_o}, {28'h0, wmask}, {name, " write mask"});
            expect_bit(bus_store_miss_o, expected_store_miss, {name, " store miss flag"});
            @(negedge clk);
            cpu_we_i = 1'b0;
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

        repeat (3) @(negedge clk);
        rst_n = 1'b1;
        @(posedge clk);#2;
        expect_bit(cpu_stall_o,0,"reset releases idle cache");

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
        @(negedge clk);
        enqueue(READ_MEM,32'h10000040,0,0,0);
        cpu_addr_i = 32'h1000_0040;
        cpu_re_i = 1'b1;
        @(posedge clk);
        #2;
        expect_bit(cpu_stall_o,1,"store miss target stalls until refill");
        @(negedge clk);
        cpu_re_i = 1'b0;
        wait_request(tail,"store miss target refill request");
        expect_bit(bus_mem_re_o, 1'b1, "store miss target is still a load miss");
        drive_fill4(32'hEEEE_0000, 32'hEEEE_0001, 32'hEEEE_0002, 32'hEEEE_0003);
        wait_ready("ready after store-miss target refill");
        expect_word(cpu_rdata_o, 32'hEEEE_0000, "refill after store miss returns word0");

        @(negedge clk);
        enqueue(READ_MMIO,32'h20000000,0,0,0);
        cpu_addr_i = 32'h2000_0000;
        cpu_re_i = 1'b1;
        bus_rdata_i = 32'hFACE_CAFE;
        wait_request(tail,"uncached read request");
        expect_bit(bus_mmio_re_o, 1'b1, "uncached read routes to MMIO");
        @(negedge clk);cpu_re_i = 1'b0;
        wait_ready("uncached read fixed-latency completion");
        expect_word(cpu_rdata_o, 32'hFACE_CAFE, "uncached read data returned");

        @(negedge clk);
        enqueue(WRITE_MMIO,32'h20010004,32'h1234abcd,4'hf,0);
        cpu_addr_i = 32'h2001_0004;
        cpu_wdata_i = 32'h1234_ABCD;
        cpu_wmask_i = 4'hF;
        cpu_we_i = 1'b1;
        wait_request(tail,"uncached write request");
        expect_bit(bus_mmio_we_o, 1'b1, "uncached write routes to MMIO");
        expect_bit(bus_mem_we_o, 1'b0, "uncached write does not assert memory write");

        @(negedge clk);cpu_we_i = 0;
        cpu_req_stall_i = 1'b1;
        cpu_addr_i = 32'h1000_0080;
        cpu_re_i = 1'b1;
        repeat(3) begin
            @(posedge clk);#2;
            expect_bit(bus_mem_re_o, 1'b0, "pipeline stall suppresses new dcache request");
        end
        @(negedge clk);
        cpu_req_stall_i = 1'b0;
        cpu_re_i = 1'b0;

        // Additional byte lanes and consecutive stores, without deleting any
        // original scenario or changing its data expectations.
        store_access(32'h10000040,32'h11223311,4'b0001,0,"byte lane0 store");
        load_hit(32'h10000040,32'heeee0011,"byte lane0 preserved other bytes");
        store_access(32'h10000040,32'h55ffbb77,4'b1000,0,"byte lane3 store");
        load_hit(32'h10000040,32'h55ee0011,"byte lane3 preserved other bytes");
        @(negedge clk);
        enqueue(WRITE_MEM,32'h10000040,32'h12345678,4'hf,0);
        cpu_addr_i=32'h10000040;cpu_wdata_i=32'h12345678;cpu_wmask_i=4'hf;cpu_we_i=1;
        @(negedge clk);
        enqueue(WRITE_MEM,32'h10000040,32'habcd00ef,4'b0011,0);
        cpu_wdata_i=32'habcd00ef;cpu_wmask_i=4'b0011;
        @(negedge clk);cpu_we_i=0;
        wait_request(tail,"consecutive stores");
        load_hit(32'h10000040,32'h123400ef,"consecutive stores preserve order");

        // Abort a partially filled line. Reset must discard the outstanding
        // transaction and invalidate the partial data before a fresh miss.
        @(negedge clk);
        enqueue(READ_MEM,32'h10000080,0,0,0);
        cpu_addr_i=32'h10000080;cpu_re_i=1;
        @(negedge clk);cpu_re_i=0;
        wait_request(tail,"reset-aborted miss request");
        @(negedge clk);bus_rdata_valid_i=1;bus_rdata_i=32'hdead0000;
        @(negedge clk);bus_rdata_i=32'hdead0001;
        @(negedge clk);bus_rdata_valid_i=0;rst_n=0;
        repeat(2) @(negedge clk);
        rst_n=1;
        @(posedge clk);#2;
        expect_bit(cpu_stall_o,0,"reset clears in-flight miss stall");
        load_miss_and_fill(32'h10000080,32'hface0000,32'hface0001,32'hface0002,32'hface0003,
                           32'hface0000,"fresh miss after reset");
        load_hit(32'h10000084,32'hface0001,"post-reset fill word1");
        // A line that was fully valid before reset must miss as well; checking
        // only the aborted line would not detect stale valid/tag metadata.
        load_miss_and_fill(32'h10000040,32'hfeed0100,32'hfeed0101,32'hfeed0102,32'hfeed0103,
                           32'hfeed0100,"previously valid line invalidated by reset");
        repeat(3) begin @(posedge clk);#2;end
        expect_word(head,tail,"all expected transactions observed exactly once");
        expect_word(read_requests,5,"total cacheable read requests including reset abort");
        expect_word(write_requests,6,"total cacheable write requests");
        expect_word(mmio_reads,1,"exactly one MMIO read");
        expect_word(mmio_writes,1,"exactly one MMIO write");
        expect_word(completed_fills,4,"four completed four-beat fills");
        expect_word(aborted_fills,1,"one reset-aborted fill");
        expect_word(fill_beats,18,"fill beats include two aborted beats");

        if (errors == 0) begin
            $display("[RESULT] tb_dcache PASS assertions=%0d requests=%0d fill_beats=%0d",assertions,head,fill_beats);
        end else begin
            $display("[RESULT] tb_dcache FAIL errors=%0d", errors);
            $fatal(1);
        end
        $finish;
    end
    initial begin #10000;$fatal(1,"tb_dcache global watchdog");end
endmodule

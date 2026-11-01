`timescale 1ns / 1ps

module tb_icache;
    localparam XLEN = 32;

    reg              clk;
    reg              rst_n;
    reg  [XLEN-1:0]  cpu_addr_i;
    wire [31:0]      cpu_inst_o;
    wire             cpu_stall_o;
    reg  [31:0]      mem_rdata_i;
    reg              mem_rdata_valid;
    wire [XLEN-1:0]  mem_addr_o;
    wire             icache_miss;
    reg              redirect_i;
    reg              fence_i_flush;

    integer errors;

    icache #(
        .XLEN(XLEN),
        .ICACHE_SET_SIZE(4),
        .ICACHE_LINE_WORDS(4)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .cpu_addr_i(cpu_addr_i),
        .cpu_inst_o(cpu_inst_o),
        .cpu_stall_o(cpu_stall_o),
        .mem_rdata_i(mem_rdata_i),
        .mem_rdata_valid(mem_rdata_valid),
        .mem_addr_o(mem_addr_o),
        .icache_miss(icache_miss),
        .redirect_i(redirect_i),
        .fence_i_flush(fence_i_flush)
    );

`ifdef DUMP_FSDB
    initial begin
        $fsdbDumpfile("tb_icache.fsdb");
        $fsdbDumpvars(0, tb_icache, "+all");
    end
`else
    initial begin
        $dumpfile("tb_icache.vcd");
        $dumpvars(0, tb_icache);
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
        input [31:0] actual;
        input [31:0] expected;
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
        input [31:0] w0;
        input [31:0] w1;
        input [31:0] w2;
        input [31:0] w3;
        begin
            @(posedge clk);
            #1;

            mem_rdata_i = w0;
            mem_rdata_valid = 1'b1;
            @(posedge clk);
            #1;
            mem_rdata_i = w1;
            @(posedge clk);
            #1;
            mem_rdata_i = w2;
            @(posedge clk);
            #1;
            mem_rdata_i = w3;
            @(posedge clk);
            #1;
            mem_rdata_valid = 1'b0;
            mem_rdata_i = 32'h0;
        end
    endtask

    task fetch_miss_and_fill;
        input [XLEN-1:0] addr;
        input [31:0] w0;
        input [31:0] w1;
        input [31:0] w2;
        input [31:0] w3;
        input [31:0] expected;
        input [255:0] name;
        begin
            cpu_addr_i = addr;
            #1;
            expect_bit(icache_miss, 1'b1, {name, " miss request"});
            expect_word(mem_addr_o[31:0], addr[31:0], {name, " miss addr"});
            expect_bit(cpu_stall_o, 1'b1, {name, " stalls on miss"});
            drive_fill4(w0, w1, w2, w3);
            wait_ready({name, " ready after fill"});
            expect_word(cpu_inst_o, expected, {name, " filled instruction"});
        end
    endtask

    task fetch_hit;
        input [XLEN-1:0] addr;
        input [31:0] expected;
        input [255:0] name;
        begin
            cpu_addr_i = addr;
            #1;
            expect_bit(icache_miss, 1'b0, {name, " no refill miss"});
            @(posedge clk);
            #1;
            wait_ready({name, " hit data ready"});
            expect_word(cpu_inst_o, expected, name);
        end
    endtask

    initial begin
        errors = 0;
        rst_n = 1'b0;
        cpu_addr_i = 32'h1000_0000;
        mem_rdata_i = 32'h0;
        mem_rdata_valid = 1'b0;
        redirect_i = 1'b1;
        fence_i_flush = 1'b0;

        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);
        #1;
        redirect_i = 1'b0;
        #1;

        fetch_miss_and_fill(32'h1000_0000,
                            32'h1111_0000, 32'h1111_0001,
                            32'h1111_0002, 32'h1111_0003,
                            32'h1111_0000,
                            "cold line word0 fill");

        fetch_hit(32'h1000_0004, 32'h1111_0001, "same line word1 hit after address change");
        fetch_hit(32'h1000_0008, 32'h1111_0002, "same line word2 hit after address change");
        fetch_hit(32'h1000_0000, 32'h1111_0000, "word0 remains cached");

        fetch_miss_and_fill(32'h1000_0040,
                            32'h2222_0000, 32'h2222_0001,
                            32'h2222_0002, 32'h2222_0003,
                            32'h2222_0000,
                            "same-index second way fill");
        fetch_hit(32'h1000_0004, 32'h1111_0001, "first way survives second way fill");

        fence_i_flush = 1'b1;
        @(posedge clk);
        #1;
        fence_i_flush = 1'b0;
        cpu_addr_i = 32'h1000_0000;
        #1;
        expect_bit(icache_miss, 1'b1, "fence.i invalidates cached line");
        drive_fill4(32'h3333_0000, 32'h3333_0001, 32'h3333_0002, 32'h3333_0003);
        wait_ready("ready after fence refill");
        expect_word(cpu_inst_o, 32'h3333_0000, "refilled line after fence.i");

        redirect_i = 1'b1;
        cpu_addr_i = 32'h1000_0080;
        #1;
        expect_bit(icache_miss, 1'b0, "redirect suppresses miss request");
        redirect_i = 1'b0;
        #1;
        expect_bit(icache_miss, 1'b1, "miss starts once redirect drops");
        drive_fill4(32'h4444_0000, 32'h4444_0001, 32'h4444_0002, 32'h4444_0003);
        wait_ready("ready after redirected miss fill");
        expect_word(cpu_inst_o, 32'h4444_0000, "redirected line fetch");

        if (errors == 0) begin
            $display("[RESULT] tb_icache PASS");
        end else begin
            $display("[RESULT] tb_icache FAIL errors=%0d", errors);
            $fatal(1);
        end
        $finish;
    end
endmodule

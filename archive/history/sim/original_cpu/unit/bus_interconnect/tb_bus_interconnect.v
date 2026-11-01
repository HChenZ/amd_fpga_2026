`timescale 1ns / 1ps

module tb_bus_interconnect;
    localparam XLEN = 32;

    reg clk;
    reg rst_n;

    reg  [XLEN-1:0]   cpu_addr;
    reg  [XLEN-1:0]   cpu_wdata;
    reg  [XLEN/8-1:0] cpu_w_mask;
    reg               mem_re;
    reg               mem_we;
    reg               mmio_re;
    reg               mmio_we;
    reg               load_miss_i;
    reg               store_miss_i;
    wire [XLEN-1:0]   cpu_rdata;
    wire              cpu_rdata_valid;
    wire              cpu_axi_stall_req;

    reg               icache_miss_i;
    reg  [XLEN-1:0]   icache_addr_i;
    wire [31:0]       icache_rdata_o;
    wire              icache_rdata_valid_o;

    reg               cache_ready_i;
    reg  [XLEN-1:0]   cache_rdata_i;
    reg               cache_rdata_valid_i;
    reg               cache_rdata_last_i;
    reg               write_full_i;
    reg               write_empty_i;
    reg               write_done_pulse_i;
    reg               cache_rid_i;
    wire              cache_re_o;
    wire              cache_we_o;
    wire [XLEN-1:0]   cache_addr_o;
    wire [XLEN-1:0]   cache_waddr_o;
    wire [XLEN-1:0]   cache_wdata_o;
    wire [XLEN/8-1:0] cache_wmask_o;
    wire [2:0]        cache_arsize_o;
    wire              cache_rid_o;
    wire              cache_valid_o;
    wire              write_done_pulse_o;

    wire              clint_re;
    wire              clint_we;
    wire [2:0]        clint_addr_sel;
    wire [XLEN-1:0]   clint_wdata;
    wire [XLEN/8-1:0] clint_w_mask;
    reg  [XLEN-1:0]   clint_rdata;

    wire              uart_re;
    wire              uart_we;
    wire [1:0]        uart_addr_sel;
    wire [31:0]       uart_wdata;
    reg  [31:0]       uart_rdata;

    wire              gpio_re;
    wire              gpio_we;
    wire              gpio_addr_sel;
    wire [31:0]       gpio_wdata;
    reg  [31:0]       gpio_rdata;

    wire              cpi_re;
    wire [2:0]        cpi_addr_sel;
    reg  [XLEN-1:0]   cpi_rdata;

    integer errors;
    integer beat;

    bus_interconnect #(.XLEN(XLEN)) dut (
        .clk(clk),
        .rst_n(rst_n),
        .cpu_addr(cpu_addr),
        .cpu_wdata(cpu_wdata),
        .cpu_w_mask(cpu_w_mask),
        .mem_re(mem_re),
        .mem_we(mem_we),
        .mmio_re(mmio_re),
        .mmio_we(mmio_we),
        .load_miss_i(load_miss_i),
        .store_miss_i(store_miss_i),
        .cpu_rdata(cpu_rdata),
        .cpu_rdata_valid(cpu_rdata_valid),
        .cpu_axi_stall_req(cpu_axi_stall_req),
        .icache_miss_i(icache_miss_i),
        .icache_addr_i(icache_addr_i),
        .icache_rdata_o(icache_rdata_o),
        .icache_rdata_valid_o(icache_rdata_valid_o),
        .cache_ready_i(cache_ready_i),
        .cache_rdata_i(cache_rdata_i),
        .cache_rdata_valid_i(cache_rdata_valid_i),
        .cache_rdata_last_i(cache_rdata_last_i),
        .write_full_i(write_full_i),
        .write_empty_i(write_empty_i),
        .write_done_pulse_i(write_done_pulse_i),
        .cache_rid_i(cache_rid_i),
        .cache_re_o(cache_re_o),
        .cache_we_o(cache_we_o),
        .cache_addr_o(cache_addr_o),
        .cache_waddr_o(cache_waddr_o),
        .cache_wdata_o(cache_wdata_o),
        .cache_wmask_o(cache_wmask_o),
        .cache_arsize_o(cache_arsize_o),
        .cache_rid_o(cache_rid_o),
        .cache_valid_o(cache_valid_o),
        .write_done_pulse_o(write_done_pulse_o),
        .clint_re(clint_re),
        .clint_we(clint_we),
        .clint_addr_sel(clint_addr_sel),
        .clint_wdata(clint_wdata),
        .clint_w_mask(clint_w_mask),
        .clint_rdata(clint_rdata),
        .uart_re(uart_re),
        .uart_we(uart_we),
        .uart_addr_sel(uart_addr_sel),
        .uart_wdata(uart_wdata),
        .uart_rdata(uart_rdata),
        .gpio_re(gpio_re),
        .gpio_we(gpio_we),
        .gpio_addr_sel(gpio_addr_sel),
        .gpio_wdata(gpio_wdata),
        .gpio_rdata(gpio_rdata),
        .cpi_re(cpi_re),
        .cpi_addr_sel(cpi_addr_sel),
        .cpi_rdata(cpi_rdata)
    );

    initial begin
`ifdef DUMP_FSDB
        $fsdbDumpfile("tb_bus_interconnect.fsdb");
        $fsdbDumpvars(0, tb_bus_interconnect, "+all");
`else
        $dumpfile("tb_bus_interconnect.vcd");
        $dumpvars(0, tb_bus_interconnect);
`endif
    end

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task fail_msg;
        input [8*160-1:0] name;
        begin
            errors = errors + 1;
            $display("[FAIL] %0s", name);
        end
    endtask

    task expect_bit;
        input actual;
        input expected;
        input [8*160-1:0] name;
        begin
            if (actual !== expected)
                fail_msg({name, " expected bit mismatch"});
            else
                $display("[PASS] %0s = %0b", name, actual);
        end
    endtask

    task expect_word;
        input [XLEN-1:0] actual;
        input [XLEN-1:0] expected;
        input [8*160-1:0] name;
        begin
            if (actual !== expected) begin
                errors = errors + 1;
                $display("[FAIL] %0s expected=0x%08h actual=0x%08h",
                         name, expected, actual);
            end
            else begin
                $display("[PASS] %0s = 0x%08h", name, actual);
            end
        end
    endtask

    task tick;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    task reset_dut;
        begin
            rst_n = 1'b0;
            cpu_addr = {XLEN{1'b0}};
            cpu_wdata = {XLEN{1'b0}};
            cpu_w_mask = {XLEN/8{1'b0}};
            mem_re = 1'b0;
            mem_we = 1'b0;
            mmio_re = 1'b0;
            mmio_we = 1'b0;
            load_miss_i = 1'b0;
            store_miss_i = 1'b0;
            icache_miss_i = 1'b0;
            icache_addr_i = {XLEN{1'b0}};
            cache_ready_i = 1'b1;
            cache_rdata_i = {XLEN{1'b0}};
            cache_rdata_valid_i = 1'b0;
            cache_rdata_last_i = 1'b0;
            write_full_i = 1'b0;
            write_empty_i = 1'b1;
            write_done_pulse_i = 1'b0;
            cache_rid_i = 1'b0;
            clint_rdata = 32'hCA11_0001;
            uart_rdata = 32'hCA22_0002;
            gpio_rdata = 32'hCA33_0003;
            cpi_rdata = 32'hCA44_0004;
            repeat (4) tick();
            rst_n = 1'b1;
            tick();
        end
    endtask

    task drive_dcache_read;
        input [XLEN-1:0] addr;
        input [XLEN-1:0] first_data;
        begin
            cpu_addr = addr;
            mem_re = 1'b1;
            tick();
            mem_re = 1'b0;

            expect_bit(cache_valid_o, 1'b1, "dcache read cache_valid");
            expect_bit(cache_re_o, 1'b1, "dcache read cache_re");
            expect_bit(cache_rid_o, 1'b1, "dcache read RID");
            expect_word(cache_addr_o, {addr[XLEN-1:2], 2'b00}, "dcache read aligned address");
            expect_word({29'h0, cache_arsize_o}, 32'd2, "dcache read arsize");

            tick();
            for (beat = 0; beat < 4; beat = beat + 1) begin
                cache_rid_i = 1'b1;
                cache_rdata_i = first_data + beat;
                cache_rdata_valid_i = 1'b1;
                cache_rdata_last_i = (beat == 3);
                #1;
                expect_bit(cpu_rdata_valid, 1'b1, "dcache read data valid");
                expect_word(cpu_rdata, first_data + beat, "dcache read data");
                tick();
            end
            cache_rdata_valid_i = 1'b0;
            cache_rdata_last_i = 1'b0;
            tick();
            expect_bit(cache_valid_o, 1'b0, "dcache read returns idle");
        end
    endtask

    task drive_icache_read;
        input [XLEN-1:0] addr;
        input [31:0] first_data;
        begin
            icache_addr_i = addr;
            icache_miss_i = 1'b1;
            tick();
            icache_miss_i = 1'b0;

            expect_bit(cache_valid_o, 1'b1, "icache read cache_valid");
            expect_bit(cache_re_o, 1'b1, "icache read cache_re");
            expect_bit(cache_rid_o, 1'b0, "icache read RID");
            expect_word(cache_addr_o, addr, "icache read address");
            expect_word({29'h0, cache_arsize_o}, 32'd2, "icache read arsize");

            tick();
            for (beat = 0; beat < 4; beat = beat + 1) begin
                cache_rid_i = 1'b0;
                cache_rdata_i = first_data + beat;
                cache_rdata_valid_i = 1'b1;
                cache_rdata_last_i = (beat == 3);
                #1;
                expect_bit(icache_rdata_valid_o, 1'b1, "icache read data valid");
                expect_word(icache_rdata_o, first_data + beat, "icache read data");
                tick();
            end
            cache_rdata_valid_i = 1'b0;
            cache_rdata_last_i = 1'b0;
            tick();
            expect_bit(cache_valid_o, 1'b0, "icache read returns idle");
        end
    endtask

    task test_mmio_routes;
        begin
            cpu_wdata = 32'h5A5A_7788;
            cpu_w_mask = 4'b1010;

            cpu_addr = 32'h1200_4004;
            mmio_re = 1'b1;
            #1;
            expect_bit(clint_re, 1'b1, "CLINT read select");
            expect_word({29'h0, clint_addr_sel}, 32'd2, "CLINT address select");
            tick();
            mmio_re = 1'b0;
            #1;
            expect_word(cpu_rdata, clint_rdata, "CLINT read mux");
            tick();

            cpu_addr = 32'h2000_0004;
            mmio_we = 1'b1;
            #1;
            expect_bit(uart_we, 1'b1, "UART write select");
            expect_word({30'h0, uart_addr_sel}, 32'd1, "UART address select");
            expect_word(uart_wdata, cpu_wdata, "UART write data");
            tick();
            mmio_we = 1'b0;

            cpu_addr = 32'h2001_0004;
            mmio_re = 1'b1;
            #1;
            expect_bit(gpio_re, 1'b1, "GPIO read select");
            expect_word({31'h0, gpio_addr_sel}, 32'd1, "GPIO address select");
            tick();
            mmio_re = 1'b0;
            #1;
            expect_word(cpu_rdata, gpio_rdata, "GPIO read mux");
            tick();

            cpu_addr = 32'h6000_0008;
            mmio_re = 1'b1;
            #1;
            expect_bit(cpi_re, 1'b1, "CPI read select");
            expect_word({29'h0, cpi_addr_sel}, 32'd2, "CPI address select");
            tick();
            mmio_re = 1'b0;
            #1;
            expect_word(cpu_rdata, cpi_rdata, "CPI read mux");
            tick();
        end
    endtask

    task test_store_path;
        begin
            cpu_addr = 32'h1000_0020;
            cpu_wdata = 32'hDEAD_BEEF;
            cpu_w_mask = 4'b1100;
            write_full_i = 1'b0;
            mem_we = 1'b1;
            #1;
            expect_bit(cache_we_o, 1'b1, "store forwards to bridge");
            expect_word(cache_waddr_o, cpu_addr, "store write address");
            expect_word(cache_wdata_o, cpu_wdata, "store write data");
            expect_word({28'h0, cache_wmask_o}, 32'h0000_000C, "store write mask");
            expect_bit(cpu_axi_stall_req, 1'b0, "store no stall when FIFO ready");
            tick();
            mem_we = 1'b0;
            tick();

            cpu_addr = 32'h1000_0030;
            cpu_wdata = 32'h1234_5678;
            cpu_w_mask = 4'b0011;
            write_full_i = 1'b1;
            mem_we = 1'b1;
            #1;
            expect_bit(cpu_axi_stall_req, 1'b1, "store stalls when FIFO full");
            tick();
            mem_we = 1'b0;
            #1;
            expect_bit(cache_we_o, 1'b1, "store buffered while FIFO full");
            expect_word(cache_waddr_o, 32'h1000_0030, "buffered store address");
            write_full_i = 1'b0;
            tick();
            #1;
            expect_bit(cache_we_o, 1'b0, "buffered store drains when FIFO ready");

            write_done_pulse_i = 1'b1;
            #1;
            expect_bit(write_done_pulse_o, 1'b1, "write done passthrough");
            tick();
            write_done_pulse_i = 1'b0;
        end
    endtask

    task test_dcache_priority_then_icache_buffer;
        begin
            cpu_addr = 32'h1000_0100;
            icache_addr_i = 32'h1000_0200;
            mem_re = 1'b1;
            icache_miss_i = 1'b1;
            tick();
            mem_re = 1'b0;
            icache_miss_i = 1'b0;

            expect_bit(cache_valid_o, 1'b1, "simultaneous read first valid");
            expect_bit(cache_rid_o, 1'b1, "dcache priority over icache");
            expect_word(cache_addr_o, 32'h1000_0100, "dcache priority address");

            tick();
            for (beat = 0; beat < 4; beat = beat + 1) begin
                cache_rid_i = 1'b1;
                cache_rdata_i = 32'hD00D_0000 + beat;
                cache_rdata_valid_i = 1'b1;
                cache_rdata_last_i = (beat == 3);
                tick();
            end
            cache_rdata_valid_i = 1'b0;
            cache_rdata_last_i = 1'b0;
            #1;
            expect_bit(cache_valid_o, 1'b1, "buffered icache valid after dcache");
            expect_bit(cache_rid_o, 1'b0, "buffered icache RID");
            expect_word(cache_addr_o, 32'h1000_0200, "buffered icache address");

            tick();
            for (beat = 0; beat < 4; beat = beat + 1) begin
                cache_rid_i = 1'b0;
                cache_rdata_i = 32'h1ACE_0000 + beat;
                cache_rdata_valid_i = 1'b1;
                cache_rdata_last_i = (beat == 3);
                tick();
            end
            cache_rdata_valid_i = 1'b0;
            cache_rdata_last_i = 1'b0;
            tick();
        end
    endtask

    initial begin
        errors = 0;
        reset_dut();

        test_mmio_routes();
        test_store_path();
        drive_dcache_read(32'h1000_0006, 32'hA000_1000);
        drive_icache_read(32'h1000_0040, 32'hB000_2000);
        test_dcache_priority_then_icache_buffer();

        if (errors == 0)
            $display("[RESULT] tb_bus_interconnect PASS");
        else
            $display("[RESULT] tb_bus_interconnect FAIL errors=%0d", errors);
        $finish;
    end

endmodule

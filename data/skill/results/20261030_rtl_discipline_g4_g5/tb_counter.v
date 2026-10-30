`timescale 1ns/1ps

module tb_counter;
    reg        clk;
    reg        rst_n;
    reg        clear;
    reg        enable;
    reg        load;
    reg  [7:0] load_data;
    wire [7:0] count;

    reg  [7:0] model_count;
    reg [31:0] lfsr;
    integer errors;
    integer cycle_tag;
    integer rst_i;
    integer clear_i;
    integer enable_i;
    integer load_i;
    integer random_i;
    reg random_rst_n;
    reg random_clear;
    reg random_enable;
    reg random_load;

    counter8 dut (
        .clk(clk),
        .rst_n(rst_n),
        .clear(clear),
        .enable(enable),
        .load(load),
        .load_data(load_data),
        .count(count)
    );

    always #5 clk = ~clk;

    task automatic apply_case;
        input        in_rst_n;
        input        in_clear;
        input        in_enable;
        input        in_load;
        input [7:0]  in_load_data;
        input [31:0] tag;
        reg   [7:0]  expected;
        begin
            @(negedge clk);
            rst_n     = in_rst_n;
            clear     = in_clear;
            enable    = in_enable;
            load      = in_load;
            load_data = in_load_data;

            expected = model_count;
            if (!in_rst_n)
                expected = 8'h00;
            else if (in_clear)
                expected = 8'h00;
            else if (in_load)
                expected = in_load_data;
            else if (in_enable)
                expected = model_count + 8'h01;

            @(posedge clk);
            #1;
            cycle_tag = cycle_tag + 1;

            if (^count === 1'bx) begin
                errors = errors + 1;
                $display("FAIL tag=%0d cycle=%0d count_contains_x", tag, cycle_tag);
            end
            if (count !== expected) begin
                errors = errors + 1;
                $display("FAIL tag=%0d cycle=%0d expected=%02x actual=%02x",
                         tag, cycle_tag, expected, count);
            end
            model_count = expected;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        clear = 1'b0;
        enable = 1'b0;
        load = 1'b0;
        load_data = 8'h00;
        model_count = 8'h00;
        lfsr = 32'h20261030;
        errors = 0;
        cycle_tag = 0;

        apply_case(0, 0, 0, 0, 8'h00, 1);
        apply_case(0, 1, 1, 1, 8'hff, 2);
        apply_case(1, 0, 0, 0, 8'h00, 3);

        for (rst_i = 0; rst_i < 2; rst_i = rst_i + 1) begin
            for (clear_i = 0; clear_i < 2; clear_i = clear_i + 1) begin
                for (load_i = 0; load_i < 2; load_i = load_i + 1) begin
                    for (enable_i = 0; enable_i < 2; enable_i = enable_i + 1) begin
                        apply_case(
                            1, 0, 0, 1,
                            8'h10 + rst_i * 16 + clear_i * 8 + load_i * 4 + enable_i,
                            100 + rst_i * 8 + clear_i * 4 + load_i * 2 + enable_i
                        );
                        apply_case(
                            rst_i, clear_i, enable_i, load_i,
                            8'ha5,
                            200 + rst_i * 8 + clear_i * 4 + load_i * 2 + enable_i
                        );
                    end
                end
            end
        end

        apply_case(1, 0, 0, 1, 8'hff, 300);
        apply_case(1, 0, 1, 0, 8'h00, 301);
        apply_case(1, 0, 0, 0, 8'h00, 302);
        apply_case(1, 0, 0, 0, 8'h00, 303);

        apply_case(1, 0, 0, 1, 8'h12, 310);
        apply_case(1, 0, 0, 1, 8'h34, 311);

        apply_case(1, 0, 0, 1, 8'hfd, 320);
        apply_case(1, 0, 1, 0, 8'h00, 321);
        apply_case(1, 0, 1, 0, 8'h00, 322);
        apply_case(1, 0, 1, 0, 8'h00, 323);
        apply_case(1, 0, 1, 0, 8'h00, 324);

        for (random_i = 0; random_i < 1000; random_i = random_i + 1) begin
            lfsr = {lfsr[30:0],
                    lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
            random_rst_n = (lfsr[3:0] == 4'h0) ? 1'b0 : 1'b1;
            random_clear = lfsr[7];
            random_enable = lfsr[12];
            random_load = lfsr[20];
            apply_case(
                random_rst_n,
                random_clear,
                random_enable,
                random_load,
                lfsr[31:24],
                1000 + random_i
            );
        end

        if (errors != 0)
            $fatal(1, "FAIL tb_counter errors=%0d cycles=%0d", errors, cycle_tag);

        $display("PASS tb_counter cycles=%0d seed=%08x final_count=%02x",
                 cycle_tag, 32'h20261030, count);
        $finish;
    end

    initial begin
        #200000;
        $fatal(1, "FAIL tb_counter watchdog timeout");
    end
endmodule

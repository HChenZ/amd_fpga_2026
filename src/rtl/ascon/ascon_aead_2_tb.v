`timescale 1ns / 1ps
module tb;
    reg clk, rst_n, start;
    reg [127:0] k, npub, ad, m;
    reg [4:0] adlen, mlen;
    wire [127:0] c, tag;
    wire done, busy;

    crypto_aead_encrypt dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .k(k), .npub(npub), .ad(ad), .m(m),
        .adlen(adlen), .mlen(mlen),
        .c(c), .tag(tag), .done(done), .busy(busy));

    always #5 clk = ~clk;
    integer errors = 0;

    task run_vector;
        input [127:0] v_ad, v_m;
        input [4:0] v_adlen, v_mlen;
        input [127:0] v_exp_ct, v_exp_tag;
        reg [127:0] mask;
        begin
            @(negedge clk);
            ad = v_ad; m = v_m; adlen = v_adlen; mlen = v_mlen;
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
            wait (done === 1'b1);
            @(negedge clk);
            if (tag !== v_exp_tag) begin
                $display("FAIL tag: got %h exp %h", tag, v_exp_tag);
                errors = errors + 1;
            end else
                $display("PASS tag: %h", tag);
            if (v_mlen > 0) begin
                if (v_mlen == 5'd16) mask = {32{4'hF}};
                else mask = (128'h1 << (8 * v_mlen)) - 128'h1;
                if ((c & mask) !== (v_exp_ct & mask)) begin
                    $display("FAIL ct : got %h exp %h (mlen=%0d)", c & mask, v_exp_ct & mask, v_mlen);
                    errors = errors + 1;
                end else
                    $display("PASS ct : %h", c & mask);
            end
        end
    endtask

    initial begin
        clk = 0; rst_n = 0; start = 0;
        k = 128'h0F0E0D0C0B0A09080706050403020100; npub = 128'h1F1E1D1C1B1A19181716151413121110;
        ad = 0; m = 0; adlen = 0; mlen = 0;
        #25 rst_n = 1;
        #10;
        // V0_empty: adlen=0 mlen=0
        run_vector(128'h00000000000000000000000000000000, 128'h00000000000000000000000000000000, 5'd0, 5'd0, 128'h0, 128'hC62E8BEE468FF66B31C9BE1182279C4F);
        // V1_8_8: adlen=8 mlen=8
        run_vector(128'h00000000000000000706050403020100, 128'h00000000000000000F0E0D0C0B0A0908, 5'd8, 5'd8, 128'h000000000000000054D528D72A76D7E8, 128'hA2870CD104EEC6D2D0D7E9ADD54E86D9);
        // V2_16_16: adlen=16 mlen=16
        run_vector(128'h0F0E0D0C0B0A09080706050403020100, 128'h1F1E1D1C1B1A19181716151413121110, 5'd16, 5'd16, 128'h52020C19F0DDE595D0608B4DFE656A52, 128'h2849DB38331880AF094BC65D9864771C);
        // V3_15_15: adlen=15 mlen=15
        run_vector(128'h000E0D0C0B0A09080706050403020100, 128'h001D1C1B1A191817161514131211100F, 5'd15, 5'd15, 128'h005D6977AAF22C2A8978805EEA6D427C, 128'h009EB875FDFEBA143DF17279CF0EB142);
        // V4_5_3: adlen=5 mlen=3
        run_vector(128'h00000000000000000000000403020100, 128'h00000000000000000000000000070605, 5'd5, 5'd3, 128'h00000000000000000000000000E86555, 128'h8684F9C40FA3B232ECC7AC43B17BDC5B);

        #20;
        if (errors == 0) $display("ALL PASS");
        else $display("%0d ERRORS", errors);
        $finish;
    end
endmodule

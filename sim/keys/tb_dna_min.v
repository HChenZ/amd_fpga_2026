`timescale 1ns / 1ps
// 最小 DNA 读取出错定位：打印状态机每拍与移出的位
module tb_dna_min;
    reg clk = 0, rst_n = 0, start = 0;
    always #5 clk = ~clk;
    wire [56:0] dna;
    wire valid;

    localparam [56:0] DNAV = 57'h0123456789ABCD;

    device_dna #(.SIM_DNA(DNAV), .SHIFT_SKIP(1)) dut (
        .clk(clk), .rst_n(rst_n), .start(start), .dna(dna), .valid(valid)
    );

    integer i;
    initial begin
        repeat (3) @(posedge clk);
        rst_n = 1;
        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;
        for (i = 0; i < 70; i = i + 1) begin
            @(posedge clk);
            if (i < 66)
                $display("t=%0d state=%0d cnt=%0d dout=%b dna=%015h",
                         i, dut.state, dut.cnt, dut.dout, dna);
        end
        $display("FINAL dna=%015h want=%015h valid=%b", dna, DNAV, valid);
        $finish;
    end
endmodule

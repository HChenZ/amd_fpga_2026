`timescale 1ns/1ps
// AXI4-Lite 主机 BFM（单 outstanding，无 burst）。驱动与采样都在 negedge，
// 保证 handshake 的建立/保持窗口稳定；非法/未映射访问只由 DUT 决定 SLVERR。
module axi_lite_bfm #(parameter ADDR_W = 12)(
    input  wire            clk,
    input  wire            rst_n,
    output reg [ADDR_W-1:0] awaddr,
    output reg [2:0]        awprot,
    output reg              awvalid,
    input  wire             awready,
    output reg [31:0]       wdata,
    output reg [3:0]        wstrb,
    output reg              wvalid,
    input  wire             wready,
    input  wire [1:0]       bresp,
    input  wire             bvalid,
    output reg              bready,
    output reg [ADDR_W-1:0] araddr,
    output reg [2:0]        arprot,
    output reg              arvalid,
    input  wire             arready,
    input  wire [31:0]      rdata,
    input  wire [1:0]       rresp,
    input  wire             rvalid,
    output reg              rready
);
    integer guard;

    initial begin
        awaddr = 0; awprot = 0; awvalid = 0;
        wdata = 0; wstrb = 0; wvalid = 0; bready = 0;
        araddr = 0; arprot = 0; arvalid = 0; rready = 0;
    end

    task automatic axi_write(input [ADDR_W-1:0] a, input [31:0] d,
                             input [3:0] strb, output [1:0] resp);
        begin
            // AW 与 W 必须分开握手：本 BFM 一次只驱动一个通道，避免
            // "两个通道同一拍完成导致 WREADY 立刻回落" 造成的假超时。
            @(negedge clk);
            awaddr = a; awvalid = 1'b1;
            guard = 0;
            while (!awready) begin
                @(negedge clk); guard = guard + 1;
                if (guard > 200) $fatal(1,"BFM: AWREADY timeout addr=%h",a);
            end
            @(negedge clk);          // 中间那个 posedge 完成 AW 握手
            awvalid = 1'b0;
            wdata = d; wstrb = strb; wvalid = 1'b1;
            guard = 0;
            while (!wready) begin
                @(negedge clk); guard = guard + 1;
                if (guard > 200) $fatal(1,"BFM: WREADY timeout addr=%h",a);
            end
            @(negedge clk);          // 中间那个 posedge 完成 W 握手
            wvalid = 1'b0;
            bready = 1'b1;
            guard = 0;
            while (!bvalid) begin
                @(negedge clk); guard = guard + 1;
                if (guard > 200) $fatal(1,"BFM: BVALID timeout addr=%h",a);
            end
            resp = bresp;
            @(negedge clk);
            bready = 1'b0;
        end
    endtask

    task automatic axi_read(input [ADDR_W-1:0] a, output [31:0] d, output [1:0] resp);
        begin
            @(negedge clk);
            araddr = a; arvalid = 1'b1; rready = 1'b1;
            guard = 0;
            while (!arready) begin
                @(negedge clk); guard = guard + 1;
                if (guard > 200) $fatal(1,"BFM: ARREADY timeout");
            end
            @(negedge clk);          // 中间那个 posedge 完成 AR 握手
            arvalid = 1'b0;
            guard = 0;
            while (!rvalid) begin
                @(negedge clk); guard = guard + 1;
                if (guard > 200) $fatal(1,"BFM: RVALID timeout");
            end
            d = rdata; resp = rresp;
            @(negedge clk);
            rready = 1'b0;
        end
    endtask
endmodule

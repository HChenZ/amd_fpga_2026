`timescale 1ns/1ps
module puf_mmio_physical_v2 #(parameter DIAGNOSTIC=0, SHIFT_SKIP=1)(
    input wire clk, ro_clk, rst_n, valid, write,
    input wire [7:0] addr, input wire [31:0] wdata, input wire [3:0] wstrb,
    output wire ready, output wire [31:0] rdata, output wire bus_error, irq,
    output wire image_ready, output wire [127:0] image_data
);
    wire [255:0] osc;
    ro_array_v2 bank(.en(rst_n),.osc(osc));
    puf_mmio_v2 #(.DIAGNOSTIC(DIAGNOSTIC),.SHIFT_SKIP(SHIFT_SKIP)) peripheral(
        .clk(clk),.ro_clk(ro_clk),.rst_n(rst_n),.osc(osc),.valid(valid),.write(write),
        .addr(addr),.wdata(wdata),.wstrb(wstrb),.ready(ready),.rdata(rdata),
        .bus_error(bus_error),.irq(irq),.image_ready(image_ready),.image_data(image_data));
endmodule

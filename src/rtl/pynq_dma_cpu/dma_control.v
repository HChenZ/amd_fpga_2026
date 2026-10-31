`timescale 1ns/1ps
// Shared ABI v2 control wrapper. Epoch writes accepted only while reset is held.
module dma_control #(
    parameter MAX_MSG = 32, parameter MAX_AD = 32,
    parameter MODE_MASK = 7,
    parameter SW_MAX = 32, parameter HW_MAX = 16,
    parameter ISE_MAX = 32, parameter DIRECT_MAX = 0
)(
    input clk, input rst_n,
    input [7:0] s_axi_awaddr, input s_axi_awvalid, output s_axi_awready,
    input [31:0] s_axi_wdata, input [3:0] s_axi_wstrb,
    input s_axi_wvalid, output s_axi_wready,
    output reg [1:0] s_axi_bresp, output reg s_axi_bvalid, input s_axi_bready,
    input [7:0] s_axi_araddr, input s_axi_arvalid, output s_axi_arready,
    output reg [31:0] s_axi_rdata, output [1:0] s_axi_rresp,
    output reg s_axi_rvalid, input s_axi_rready,
    input endpoint_ready, input endpoint_busy, input endpoint_fault,
    output endpoint_rst_n, output reg [63:0] session_epoch
);
    reg reset_hold;
    reg aw_pending, w_pending;
    reg [7:0] awaddr;
    reg [31:0] wdata;
    reg [3:0] wstrb;
    assign endpoint_rst_n = rst_n && !reset_hold;
    assign s_axi_awready = !aw_pending && !s_axi_bvalid;
    assign s_axi_wready = !w_pending && !s_axi_bvalid;
    assign s_axi_arready = !s_axi_rvalid;
    assign s_axi_rresp = 0;
    integer j;
    always @(posedge clk) begin
        if (!rst_n) begin
            reset_hold <= 1; session_epoch <= 0;
            aw_pending <= 0; w_pending <= 0;
            awaddr <= 0; wdata <= 0; wstrb <= 0;
            s_axi_bresp <= 0; s_axi_bvalid <= 0;
            s_axi_rvalid <= 0; s_axi_rdata <= 0;
        end else begin
            if (s_axi_awvalid && s_axi_awready) begin awaddr <= s_axi_awaddr; aw_pending <= 1; end
            if (s_axi_wvalid && s_axi_wready) begin wdata <= s_axi_wdata; wstrb <= s_axi_wstrb; w_pending <= 1; end
            if (s_axi_bvalid && s_axi_bready) s_axi_bvalid <= 0;
            if (aw_pending && w_pending && !s_axi_bvalid) begin
                aw_pending <= 0; w_pending <= 0;
                s_axi_bvalid <= 1; s_axi_bresp <= 0;
                case (awaddr)
                    8'h08: if (wstrb[0]) reset_hold <= wdata[0];
                    8'h0c: if (reset_hold) begin
                        for (j=0;j<4;j=j+1) if (wstrb[j]) session_epoch[j*8+:8] <= wdata[j*8+:8];
                    end else s_axi_bresp <= 2;
                    8'h10: if (reset_hold) begin
                        for (j=0;j<4;j=j+1) if (wstrb[j]) session_epoch[32+j*8+:8] <= wdata[j*8+:8];
                    end else s_axi_bresp <= 2;
                    default: s_axi_bresp <= 2;
                endcase
            end
            if (s_axi_rvalid && s_axi_rready) s_axi_rvalid <= 0;
            if (s_axi_arvalid && s_axi_arready) begin
                s_axi_rvalid <= 1;
                case (s_axi_araddr)
                    8'h00: s_axi_rdata <= 32'h32414d44;
                    8'h04: s_axi_rdata <= 2;
                    8'h08: s_axi_rdata <= reset_hold;
                    8'h0c: s_axi_rdata <= session_epoch[31:0];
                    8'h10: s_axi_rdata <= session_epoch[63:32];
                    8'h14: s_axi_rdata <= MAX_MSG;
                    8'h18: s_axi_rdata <= MAX_AD;
                    8'h1c: s_axi_rdata <= MODE_MASK;
                    8'h20: s_axi_rdata <= reset_hold ? 0 : {29'b0,endpoint_fault,endpoint_busy,endpoint_ready};
                    8'h30,8'h34: s_axi_rdata <= SW_MAX;
                    8'h38,8'h3c: s_axi_rdata <= HW_MAX;
                    8'h40,8'h44: s_axi_rdata <= ISE_MAX;
                    8'h48,8'h4c: s_axi_rdata <= DIRECT_MAX;
                    default: s_axi_rdata <= 0;
                endcase
            end
        end
    end
endmodule

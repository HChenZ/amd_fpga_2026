`timescale 1ns/1ps
// AXI-Lite control + AXI-Stream authenticated hardware engine.
module dma_direct_top # (parameter MAX_BYTES=1024)(
    (* X_INTERFACE_INFO="xilinx.com:signal:clock:1.0 clk CLK", X_INTERFACE_PARAMETER="ASSOCIATED_BUSIF S_AXI:S_AXIS:M_AXIS, ASSOCIATED_RESET rst_n, FREQ_HZ 100000000" *) input wire clk,
    (* X_INTERFACE_INFO="xilinx.com:signal:reset:1.0 rst_n RST", X_INTERFACE_PARAMETER="POLARITY ACTIVE_LOW" *) input wire rst_n,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI AWADDR" *) input wire [11:0] s_axi_awaddr,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI AWPROT" *) input wire [2:0] s_axi_awprot,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI AWVALID" *) input wire s_axi_awvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI AWREADY" *) output wire s_axi_awready,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI WDATA" *) input wire [31:0] s_axi_wdata,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI WSTRB" *) input wire [3:0] s_axi_wstrb,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI WVALID" *) input wire s_axi_wvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI WREADY" *) output wire s_axi_wready,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI BRESP" *) output wire [1:0] s_axi_bresp,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI BVALID" *) output reg s_axi_bvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI BREADY" *) input wire s_axi_bready,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI ARADDR" *) input wire [11:0] s_axi_araddr,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI ARPROT" *) input wire [2:0] s_axi_arprot,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI ARVALID" *) input wire s_axi_arvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI ARREADY" *) output wire s_axi_arready,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI RDATA" *) output reg [31:0] s_axi_rdata,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI RRESP" *) output wire [1:0] s_axi_rresp,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI RVALID" *) output reg s_axi_rvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI RREADY" *) input wire s_axi_rready,
    (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 S_AXIS TDATA" *) input wire [31:0] s_axis_tdata,
    (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 S_AXIS TKEEP" *) input wire [3:0] s_axis_tkeep,
    (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 S_AXIS TVALID" *) input wire s_axis_tvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 S_AXIS TREADY" *) output wire s_axis_tready,
    (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 S_AXIS TLAST" *) input wire s_axis_tlast,
    (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 M_AXIS TDATA" *) output wire [31:0] m_axis_tdata,
    (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 M_AXIS TKEEP" *) output wire [3:0] m_axis_tkeep,
    (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 M_AXIS TVALID" *) output wire m_axis_tvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 M_AXIS TREADY" *) input wire m_axis_tready,
    (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 M_AXIS TLAST" *) output wire m_axis_tlast
);
    reg held_reset;
    reg [63:0] epoch;
    reg aw_pending,w_pending;
    reg [11:0] awaddr;
    reg [31:0] wdata;
    reg [3:0] wstrb;
    wire fault,engine_idle;
    integer b;
    assign s_axi_awready=!aw_pending&&!s_axi_bvalid;
    assign s_axi_wready=!w_pending&&!s_axi_bvalid;
    assign s_axi_arready=!s_axi_rvalid;
    assign s_axi_bresp=0;assign s_axi_rresp=0;
    ascon_axis_direct #(.MAX_BYTES(MAX_BYTES)) engine(
        .clk(clk),.rst_n(rst_n&&!held_reset),.session_epoch(epoch),
        .s_axis_tdata(s_axis_tdata),.s_axis_tkeep(s_axis_tkeep),.s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),.s_axis_tlast(s_axis_tlast),
        .m_axis_tdata(m_axis_tdata),.m_axis_tkeep(m_axis_tkeep),.m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),.m_axis_tlast(m_axis_tlast),.fault(fault),.idle(engine_idle));
    always @(posedge clk) begin
        if(!rst_n) begin
            held_reset<=1;epoch<=0;aw_pending<=0;w_pending<=0;awaddr<=0;wdata<=0;wstrb<=0;
            s_axi_bvalid<=0;s_axi_rvalid<=0;s_axi_rdata<=0;
        end else begin
            if(s_axi_awready&&s_axi_awvalid)begin aw_pending<=1;awaddr<=s_axi_awaddr;end
            if(s_axi_wready&&s_axi_wvalid)begin w_pending<=1;wdata<=s_axi_wdata;wstrb<=s_axi_wstrb;end
            if(s_axi_bvalid&&s_axi_bready)s_axi_bvalid<=0;
            if(aw_pending&&w_pending&&!s_axi_bvalid)begin
                aw_pending<=0;w_pending<=0;s_axi_bvalid<=1;
                case(awaddr)
                12'h008: if(wstrb[0])held_reset<=wdata[0];
                12'h00c: if(held_reset)for(b=0;b<4;b=b+1)if(wstrb[b])epoch[b*8+:8]<=wdata[b*8+:8];
                12'h010: if(held_reset)for(b=0;b<4;b=b+1)if(wstrb[b])epoch[32+b*8+:8]<=wdata[b*8+:8];
                default: ;
                endcase
            end
            if(s_axi_rvalid&&s_axi_rready)s_axi_rvalid<=0;
            if(s_axi_arvalid&&s_axi_arready)begin
                s_axi_rvalid<=1;
                case(s_axi_araddr)
                12'h000:s_axi_rdata<=32'h32414d44;
                12'h004:s_axi_rdata<=2;
                12'h008:s_axi_rdata<={31'b0,held_reset};
                12'h00c:s_axi_rdata<=epoch[31:0];
                12'h010:s_axi_rdata<=epoch[63:32];
                12'h014,12'h018:s_axi_rdata<=MAX_BYTES;
                12'h01c:s_axi_rdata<=32'h00000008; // bit (mode-1), mode4
                12'h020:s_axi_rdata<={29'b0,fault,(!engine_idle&&!held_reset),engine_idle};
                12'h024:s_axi_rdata<=0;
                12'h028:s_axi_rdata<=0;
                12'h02c:s_axi_rdata<=0;
                12'h030,12'h034,12'h038,12'h03c,12'h040,12'h044:s_axi_rdata<=0;
                12'h048,12'h04c:s_axi_rdata<=MAX_BYTES; // mode-4 message/AD maximum
                default:s_axi_rdata<=0;
                endcase
            end
        end
    end
endmodule

`timescale 1ns/1ps
// One bounded packet slot. All interfaces synchronous to clk.
module dma_cpu_endpoint #(
    parameter WATCHDOG_CYCLES = 50000000
)(
    input clk, input rst_n, input [63:0] session_epoch,
    input [31:0] s_axis_tdata, input [3:0] s_axis_tkeep,
    input s_axis_tvalid, output s_axis_tready, input s_axis_tlast,
    output [31:0] m_axis_tdata, output [3:0] m_axis_tkeep,
    output m_axis_tvalid, input m_axis_tready, output m_axis_tlast,
    input cpu_re, input cpu_we, input [7:0] cpu_addr,
    input [31:0] cpu_wdata, input [3:0] cpu_wstrb,
    output reg [31:0] cpu_rdata,
    output cpu_rst_n, output ready, output busy, output reg fault
);
    reg [63:0] epoch_q;
    reg [31:0] request_mem [0:39];
    reg [31:0] response_mem [0:23];
    reg [7:0] rx_bytes, tx_bytes;
    reg [5:0] rx_words, rd_word, wr_word, tx_word;
    reg request_ready, sending;
    reg [31:0] watchdog;
    wire epoch_match = session_epoch != 0 && epoch_q == session_epoch;
    assign cpu_rst_n = rst_n && epoch_match && !fault;
    assign busy = rx_words != 0 || request_ready || sending;
    assign ready = rst_n && epoch_match && !fault && !busy;
    assign s_axis_tready = rst_n && epoch_match && !fault && !request_ready && !sending && rx_words < 40;
    assign m_axis_tvalid = rst_n && epoch_match && !fault && sending;
    assign m_axis_tlast = sending && ((tx_word + 1) * 4 >= tx_bytes);
    assign m_axis_tkeep = !m_axis_tlast || tx_bytes[1:0] == 0 ? 4'hf :
                         tx_bytes[1:0] == 1 ? 4'h1 : tx_bytes[1:0] == 2 ? 4'h3 : 4'h7;
    assign m_axis_tdata = m_axis_tvalid ? response_mem[tx_word] : 32'b0;
    wire keep_valid = s_axis_tkeep == 1 || s_axis_tkeep == 3 || s_axis_tkeep == 7 || s_axis_tkeep == 15;
    wire [2:0] keep_bytes = s_axis_tkeep == 1 ? 1 : s_axis_tkeep == 3 ? 2 : s_axis_tkeep == 7 ? 3 : 4;
    wire [31:0] keep_mask = s_axis_tkeep == 1 ? 32'hff : s_axis_tkeep == 3 ? 32'hffff : s_axis_tkeep == 7 ? 32'hffffff : 32'hffffffff;
    integer i;
    always @(posedge clk) begin
        if (!rst_n || epoch_q != session_epoch) begin
            epoch_q <= session_epoch;
            rx_bytes <= 0; tx_bytes <= 0; rx_words <= 0; rd_word <= 0;
            wr_word <= 0; tx_word <= 0; request_ready <= 0; sending <= 0;
            watchdog <= 0; fault <= 0; cpu_rdata <= 0;
            for (i=0;i<40;i=i+1) request_mem[i] <= 0;
            for (i=0;i<24;i=i+1) response_mem[i] <= 0;
        end else begin
            cpu_rdata <= 0;
            if (busy && !fault) begin
                if (watchdog >= WATCHDOG_CYCLES-1) fault <= 1;
                else watchdog <= watchdog + 1;
            end else watchdog <= 0;
            if (s_axis_tvalid && s_axis_tready) begin
                if (!keep_valid || (!s_axis_tlast && s_axis_tkeep != 15) ||
                    (rx_words == 39 && !s_axis_tlast)) fault <= 1;
                else begin
                    request_mem[rx_words] <= s_axis_tdata & keep_mask;
                    rx_words <= rx_words + 1;
                    rx_bytes <= rx_bytes + keep_bytes;
                    if (s_axis_tlast) request_ready <= 1;
                end
            end
            if (cpu_re && cpu_rst_n) begin
                case (cpu_addr)
                    8'h00: cpu_rdata <= {29'b0, fault, sending, (request_ready && !sending)};
                    8'h04: cpu_rdata <= request_ready ? rx_bytes : 0;
                    8'h08: if (request_ready && !sending && rd_word < rx_words) begin
                        cpu_rdata <= request_mem[rd_word];
                        request_mem[rd_word] <= 0;
                        rd_word <= rd_word + 1;
                    end
                    8'h18: cpu_rdata <= epoch_q[31:0];
                    8'h1c: cpu_rdata <= epoch_q[63:32];
                    default: cpu_rdata <= 0;
                endcase
            end
            if (cpu_we && cpu_rst_n) begin
                if (cpu_wstrb != 15 || !request_ready || sending) fault <= 1;
                else case (cpu_addr)
                    8'h0c: if (wr_word < 24) begin
                        response_mem[wr_word] <= cpu_wdata;
                        wr_word <= wr_word + 1;
                    end else fault <= 1;
                    8'h10: if (cpu_wdata >= 48 && cpu_wdata <= 96) tx_bytes <= cpu_wdata[7:0];
                              else fault <= 1;
                    8'h14: if (cpu_wdata == 1 && tx_bytes >= 48 &&
                               wr_word == (tx_bytes+3)/4 && rd_word == rx_words) begin
                        sending <= 1;
                        tx_word <= 0;
                    end else fault <= 1;
                    default: fault <= 1;
                endcase
            end
            if (m_axis_tvalid && m_axis_tready) begin
                response_mem[tx_word] <= 0;
                if (m_axis_tlast) begin
                    rx_bytes <= 0; tx_bytes <= 0; rx_words <= 0;
                    rd_word <= 0; wr_word <= 0; tx_word <= 0;
                    request_ready <= 0; sending <= 0; watchdog <= 0;
                end else tx_word <= tx_word + 1;
            end
        end
    end
endmodule

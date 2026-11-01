`timescale 1ns / 1ps

module uart_ctrl #(
    parameter CLK_FREQ = 50000000,
    parameter UART_BPS = 115200,
    parameter BAUD_CNT_MAX = CLK_FREQ / UART_BPS,
    parameter RX_FIFO_DEPTH = 16,
    parameter TX_FIFO_DEPTH = 16
)(
    input           clk,
    input           rst_n,

    // uart CPU MMIO interface
    input  [1:0]    addr_sel,
    input  [31:0]   cpu_w_data,
    input           cpu_w_en,
    input           cpu_r_en,
    output reg [31:0] cpu_r_data,
    output          uart_irq,

    // external UART pins
    input           uart_rxd,
    output          uart_txd
);

    localparam RX_ADDR_WIDTH = $clog2(RX_FIFO_DEPTH);
    localparam TX_ADDR_WIDTH = $clog2(TX_FIFO_DEPTH);
    localparam RX_COUNT_WIDTH = $clog2(RX_FIFO_DEPTH + 1);
    localparam TX_COUNT_WIDTH = $clog2(TX_FIFO_DEPTH + 1);

    wire       rx_valid;
    wire [7:0] rx_data;
    wire       tx_busy;
    wire [7:0] tx_data;
    reg        rx_valid_d;

    reg        rx_ie_reg;
    reg        rx_overrun_reg;
    reg        tx_overrun_reg;

    reg [7:0] rx_fifo [0:RX_FIFO_DEPTH-1];
    reg [RX_ADDR_WIDTH-1:0] rx_rd_ptr;
    reg [RX_ADDR_WIDTH-1:0] rx_wr_ptr;
    reg [RX_COUNT_WIDTH-1:0] rx_count;

    reg [7:0] tx_fifo [0:TX_FIFO_DEPTH-1];
    reg [TX_ADDR_WIDTH-1:0] tx_rd_ptr;
    reg [TX_ADDR_WIDTH-1:0] tx_wr_ptr;
    reg [TX_COUNT_WIDTH-1:0] tx_count;

    wire status_sel = (addr_sel == 2'b00);
    wire data_sel   = (addr_sel == 2'b01);
    wire ctrl_sel   = (addr_sel == 2'b10);

    wire rx_empty = (rx_count == {RX_COUNT_WIDTH{1'b0}});
    wire rx_full  = (rx_count == RX_FIFO_DEPTH);
    wire tx_empty = (tx_count == {TX_COUNT_WIDTH{1'b0}});
    wire tx_full  = (tx_count == TX_FIFO_DEPTH);
    wire tx_busy_or_pending = tx_busy || !tx_empty;

    wire rx_valid_pulse = rx_valid && !rx_valid_d;
    wire rx_pop_req  = cpu_r_en && data_sel;
    wire rx_pop      = rx_pop_req && !rx_empty;
    wire rx_push_req = rx_valid_pulse;
    wire rx_push     = rx_push_req && (!rx_full || rx_pop);
    wire rx_drop     = rx_push_req && !rx_push;

    wire tx_start    = !tx_busy && !tx_empty;
    wire tx_pop      = tx_start;
    wire tx_push_req = cpu_w_en && data_sel;
    wire tx_push     = tx_push_req && (!tx_full || tx_pop);
    wire tx_drop     = tx_push_req && !tx_push;

    wire status_read = cpu_r_en && status_sel;

    assign uart_irq = rx_ie_reg && !rx_empty;
    assign tx_data = tx_fifo[tx_rd_ptr];

    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rx_valid_d <= 1'b0;
        else
            rx_valid_d <= rx_valid;
    end

    function [RX_ADDR_WIDTH-1:0] rx_ptr_next;
        input [RX_ADDR_WIDTH-1:0] ptr;
        begin
            if (ptr == RX_FIFO_DEPTH - 1)
                rx_ptr_next = {RX_ADDR_WIDTH{1'b0}};
            else
                rx_ptr_next = ptr + {{(RX_ADDR_WIDTH-1){1'b0}}, 1'b1};
        end
    endfunction

    function [TX_ADDR_WIDTH-1:0] tx_ptr_next;
        input [TX_ADDR_WIDTH-1:0] ptr;
        begin
            if (ptr == TX_FIFO_DEPTH - 1)
                tx_ptr_next = {TX_ADDR_WIDTH{1'b0}};
            else
                tx_ptr_next = ptr + {{(TX_ADDR_WIDTH-1){1'b0}}, 1'b1};
        end
    endfunction

    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            cpu_r_data <= 32'h0;
        else if(cpu_r_en)
        begin
            if(status_sel)
                cpu_r_data <= {24'h0, uart_irq, tx_overrun_reg, tx_empty,
                               rx_overrun_reg, rx_full, tx_full,
                               !rx_empty, tx_busy_or_pending};
            else if(data_sel && !rx_empty)
                cpu_r_data <= {24'h0, rx_fifo[rx_rd_ptr]};
            else
                cpu_r_data <= 32'h0;
        end
        else
            cpu_r_data <= 32'h0;
    end

    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
        begin
            rx_rd_ptr <= {RX_ADDR_WIDTH{1'b0}};
            rx_wr_ptr <= {RX_ADDR_WIDTH{1'b0}};
            rx_count  <= {RX_COUNT_WIDTH{1'b0}};
        end
        else
        begin
            if(rx_push)
            begin
                rx_fifo[rx_wr_ptr] <= rx_data;
                rx_wr_ptr <= rx_ptr_next(rx_wr_ptr);
            end

            if(rx_pop)
                rx_rd_ptr <= rx_ptr_next(rx_rd_ptr);

            case({rx_push, rx_pop})
                2'b10: rx_count <= rx_count + {{(RX_COUNT_WIDTH-1){1'b0}}, 1'b1};
                2'b01: rx_count <= rx_count - {{(RX_COUNT_WIDTH-1){1'b0}}, 1'b1};
                default: rx_count <= rx_count;
            endcase
        end
    end

    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
        begin
            tx_rd_ptr <= {TX_ADDR_WIDTH{1'b0}};
            tx_wr_ptr <= {TX_ADDR_WIDTH{1'b0}};
            tx_count  <= {TX_COUNT_WIDTH{1'b0}};
        end
        else
        begin
            if(tx_push)
            begin
                tx_fifo[tx_wr_ptr] <= cpu_w_data[7:0];
                tx_wr_ptr <= tx_ptr_next(tx_wr_ptr);
            end

            if(tx_pop)
                tx_rd_ptr <= tx_ptr_next(tx_rd_ptr);

            case({tx_push, tx_pop})
                2'b10: tx_count <= tx_count + {{(TX_COUNT_WIDTH-1){1'b0}}, 1'b1};
                2'b01: tx_count <= tx_count - {{(TX_COUNT_WIDTH-1){1'b0}}, 1'b1};
                default: tx_count <= tx_count;
            endcase
        end
    end

    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rx_ie_reg <= 1'b0;
        else if(ctrl_sel && cpu_w_en)
            rx_ie_reg <= cpu_w_data[0];
    end

    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            rx_overrun_reg <= 1'b0;
        else
        begin
            if(status_read)
                rx_overrun_reg <= 1'b0;
            if(rx_drop)
                rx_overrun_reg <= 1'b1;
        end
    end

    always @(posedge clk or negedge rst_n)
    begin
        if(~rst_n)
            tx_overrun_reg <= 1'b0;
        else
        begin
            if(status_read)
                tx_overrun_reg <= 1'b0;
            if(tx_drop)
                tx_overrun_reg <= 1'b1;
        end
    end

    uart_rx #(
        .CLK_FREQ(CLK_FREQ),
        .UART_BPS(UART_BPS),
        .BAUD_CNT_MAX(BAUD_CNT_MAX)
    ) u_uart_rx (
        .rx_clk(clk),
        .rst_n(rst_n),
        .uart_rxd(uart_rxd),
        .uart_rx_data(rx_data),
        .rx_ack(rx_valid_pulse),
        .rx_data_valid(rx_valid)
    );

    uart_tx #(
        .CLK_FREQ(CLK_FREQ),
        .UART_BPS(UART_BPS),
        .BAUD_CNT_MAX(BAUD_CNT_MAX)
    ) u_uart_tx (
        .tx_clk(clk),
        .rst_n(rst_n),
        .uart_tx_en(tx_start),
        .uart_tx_data(tx_data),
        .uart_txd(uart_txd),
        .uart_tx_busy(tx_busy)
    );

endmodule

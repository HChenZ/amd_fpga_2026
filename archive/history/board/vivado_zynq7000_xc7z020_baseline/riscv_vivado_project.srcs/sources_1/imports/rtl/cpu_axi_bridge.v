`timescale 1ns / 1ps

module cpu_axi_bridge #(
    parameter XLEN = 32
)(
    input               clk,
    input               rst_n,

    // =================================================================
    // 统一 Cache 接口（由 bus 仲裁后接入）
    // =================================================================
    input                   cache_re,
    input                   cache_we,
    input   [XLEN-1:0]      cache_addr,
    input   [XLEN-1:0]      cache_waddr,
    input   [XLEN-1:0]      cache_wdata,
    input   [XLEN/8-1:0]    cache_wmask,
    input   [2:0]           cache_arsize,       // 读 burst size: 3'b010=4B(icache), 3'b011=8B(dcache RV64)
    input                   cache_rid,          // 读请求 ID，0=icache, 1=dcache
    input                   cache_valid,        // 当前有有效请求 (cache_re || cache_we)
    output                  cache_ready,        // rd_state == RD_IDLE 时为 1，表示可接收新请求
    output  [XLEN-1:0]      cache_rdata,
    output                  cache_rdata_valid,
    output                  cache_rdata_last,
    output                  cache_rid_o, 
    output                  write_full,
    output                  write_empty,

    // =================================================================
    // AXI Master 接口
    // =================================================================
    input                   cpu_wdata_ready,
    input                   cpu_rdata_valid,
    input   [XLEN-1:0]      cpu_rdata,
    input                   cpu_rid_i,   
    input   [1:0]           resp,
    input                   resp_en,

    output reg              cpu_re,
    output reg              cpu_we,
    output reg  [XLEN-1:0]  cpu_wdata,
    output reg  [XLEN-1:0]  cpu_raddr,
    output reg  [XLEN-1:0]  cpu_waddr,
    output reg  [XLEN/8-1:0]cpu_wmask,
    output                  cpu_wid,
    output reg              cpu_rid,       
    output reg  [1:0]       cpu_arburst,
    output reg  [2:0]       cpu_arsize,
    output reg  [7:0]       cpu_arlen,
    output reg  [1:0]       cpu_awburst,
    output reg  [2:0]       cpu_awsize,
    output reg  [7:0]       cpu_awlen,

    output reg              cpu_wdata_valid,
    output                  cpu_rdata_ready,

    output                  rd_ready,
    output reg              write_done_pulse

);



// =================================================================
// 写数据 FIFO
// =================================================================
 (* ram_style = "block" *)   reg [XLEN-1:0]      wdata_fifo [0:7];
 (* ram_style = "block" *)   reg [XLEN-1:0]      waddr_fifo [0:7];
 (* ram_style = "block" *)   reg [XLEN/8-1:0]    mask_fifo [0:7];

    reg [1:0] w_ptr;
    reg [1:0] r_ptr;
    reg [2:0] fifo_cnt;

    wire   fifo_we;
    wire   fifo_re;
    wire   full;
    wire   empty;

// =================================================================
// 读状态机（2 状态）
// =================================================================
    localparam RD_IDLE   = 1'b0;
    localparam RD_BUSY = 1'b1;
    reg         rd_state;
    reg         rd_next_state;

// =================================================================
// 写状态机
// =================================================================
    localparam WR_IDLE   = 1'b0;
    localparam WR_BUSY = 1'b1;
    reg         wr_state;
    reg         wr_next_state;

// =================================================================
// 计数器
// =================================================================
    reg [1:0]   rdata_cnt;
    reg         rdata_done;

// =================================================================
// 读请求启动信号
// =================================================================
    wire read_req = (rd_state == RD_IDLE) && cache_re;
    assign rd_ready = read_req;

    assign cache_ready = (rd_state == RD_IDLE);

// =================================================================
// 读状态机
// =================================================================
    always @(*) 
    begin
        case (rd_state)
            RD_IDLE:   rd_next_state = read_req & cache_valid ? RD_BUSY : RD_IDLE;
            RD_BUSY: rd_next_state = rdata_done ? RD_IDLE : RD_BUSY;
            default:   rd_next_state = RD_IDLE;
        endcase
    end

    always @(posedge clk or negedge rst_n) 
    begin
        if (~rst_n)
            rdata_done <= 1'b0;
        else if ((rdata_cnt == 2'd3) && cpu_rdata_valid)
            rdata_done <= 1'b1;
        else
            rdata_done <= 1'b0;
    end

    always @(posedge clk or negedge rst_n) 
    begin
        if (~rst_n)
            rd_state <= RD_IDLE;
        else
            rd_state <= rd_next_state;
    end

// =================================================================
// 写状态机
// =================================================================
    always @(*) begin
        case (wr_state)
            WR_IDLE: wr_next_state = ~empty ? WR_BUSY : WR_IDLE;
            WR_BUSY: wr_next_state = resp_en ? WR_IDLE : WR_BUSY;
            default:   wr_next_state = WR_IDLE;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (~rst_n)
            wr_state <= WR_IDLE;
        else
            wr_state <= wr_next_state;
    end

// =================================================================
// 写数据 FIFO
// =================================================================
    assign fifo_re = cpu_wdata_valid & cpu_wdata_ready;
    assign fifo_we = cache_we && ~full;

    assign full  = (fifo_cnt == 3'd4);
    assign empty = (fifo_cnt == 3'd0);
    assign write_empty = empty;
    assign write_full = full;

    always @(posedge clk or negedge rst_n) begin
        if (~rst_n)
            fifo_cnt <= 3'h0;
        else if (fifo_we && fifo_re)
            fifo_cnt <= fifo_cnt;
        else if (fifo_we)
            fifo_cnt <= fifo_cnt + 1'b1;
        else if (fifo_re && ~empty)
            fifo_cnt <= fifo_cnt - 1'b1;
    end

    always @(posedge clk or negedge rst_n) begin
        if (~rst_n)
            w_ptr <= 2'h0;
        else if (fifo_we)
            w_ptr <= w_ptr + 1'b1;
    end

    always @(posedge clk or negedge rst_n) begin
        if (~rst_n)
            r_ptr <= 2'h0;
        else if (fifo_re && ~empty)
            r_ptr <= r_ptr + 1'b1;
    end

    always @(posedge clk) begin
        if (fifo_we) begin
            wdata_fifo[w_ptr] <= cache_wdata;
            waddr_fifo[w_ptr] <= cache_waddr;
            mask_fifo[w_ptr]  <= cache_wmask;
        end
    end

    always @(posedge clk) begin
        if (wr_state == WR_IDLE && ~empty) begin
            cpu_wdata <= wdata_fifo[r_ptr];
            cpu_waddr <= waddr_fifo[r_ptr];
            cpu_wmask <= mask_fifo[r_ptr];
        end
    end

// =================================================================
// write_done_pulse
// =================================================================
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n)
            write_done_pulse <= 1'b0;
        else if (resp_en && (wr_state == WR_BUSY) && empty)
            write_done_pulse <= 1'b1;
        else
            write_done_pulse <= 1'b0;
    end

// =================================================================
// AXI 接口信号
// =================================================================
    assign cpu_wid = 1;

    always @(posedge clk or negedge rst_n)
     begin
        if (~rst_n) 
        begin
            cpu_arlen   <= 8'd3;
            cpu_awlen   <= 8'h0;
            cpu_arburst <= 2'b10;       // WRAP
            cpu_awburst <= 2'b00;       // FIXED
            cpu_awsize  <= 3'b010;
        end
        else 
        begin
            cpu_arlen   <= 8'd3;
            cpu_awlen   <= 8'h0;
            cpu_arburst <= 2'b10;
            cpu_awburst <= 2'b00;
            if (XLEN == 64)
                cpu_awsize <= 3'b011;
            else
                cpu_awsize <= 3'b010;
        end
    end

    always @(posedge clk or negedge rst_n)
     begin
        if (~rst_n) 
        begin
            cpu_arsize  <= 3'b000;
            cpu_rid <= 1'b0;
        end
        else if(cache_ready && cache_valid && cache_re)
        begin
            cpu_arsize <= cache_arsize;
            cpu_rid <= cache_rid;
        end


     end

    // 写数据有效
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n)
            cpu_wdata_valid <= 1'b0;
        else if (wr_state == WR_IDLE && ~empty)
            cpu_wdata_valid <= 1'b1;
        else if (cpu_wdata_valid && cpu_wdata_ready)
            cpu_wdata_valid <= 1'b0;
    end

    // 写使能
    always @(posedge clk or negedge rst_n) 
    begin
        if (~rst_n)
            cpu_we <= 1'b0;
        else if (wr_state == WR_IDLE && ~empty)
            cpu_we <= 1'b1;
        else if (cpu_wdata_valid && cpu_wdata_ready)
            cpu_we <= 1'b0;
    end

    // 读数据计数器
    always @(posedge clk or negedge rst_n) 
    begin
        if (~rst_n)
            rdata_cnt <= 2'h0;
        else if (rd_state == RD_BUSY && cpu_rdata_valid)
            rdata_cnt <= rdata_cnt + 1'b1;
        else if (rd_state == RD_IDLE)
            rdata_cnt <= 2'h0;
    end

    assign cpu_rdata_ready = (rd_state == RD_BUSY);

    // 读请求
    always @(posedge clk or negedge rst_n) 
    begin
        if (~rst_n)
            cpu_re <= 1'b0;
        else if (read_req & cache_valid & cache_ready)
            cpu_re <= 1'b1;
        else
            cpu_re <= 1'b0;
    end

    // 读地址
    always @(posedge clk or negedge rst_n) 
    begin
        if (~rst_n)
            cpu_raddr <= {XLEN{1'b0}};
        else if (read_req & cache_valid & cache_ready)
            cpu_raddr <= cache_addr;
    end

// =================================================================
// 读数据 — 组合直传
// =================================================================
    assign cache_rdata       = (rd_state == RD_BUSY) ? cpu_rdata : {XLEN{1'b0}};
    assign cache_rdata_valid = (rd_state == RD_BUSY) && cpu_rdata_valid;
    assign cache_rdata_last  = (rd_state == RD_BUSY) && cpu_rdata_valid && (rdata_cnt == 2'd3);
    assign cache_rid_o = cpu_rid_i;

endmodule

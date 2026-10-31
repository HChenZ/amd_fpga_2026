`timescale 1ns / 1ps

module icache #(
    parameter XLEN = 32,
    parameter ICACHE_SET_SIZE = 64,       // 每组深度（路内组数）
    parameter ICACHE_LINE_WORDS = 4       // 每行字数
)(
    input                   clk,
    input                   rst_n,

    // ========== CPU 接口 ==========
    input       [XLEN-1:0]  cpu_addr_i,     // PC from if_stage
    output      [31:0]      cpu_inst_o,     // 指令输出到 if_id
    output                  cpu_stall_o,    // miss 时停顿流水线

    // ========== 外部 MEM 接口（用于行填充） ==========
    input       [31:0]      mem_rdata_i,    // 读数据   
    input                   mem_rdata_valid,// 读数据有效 
    output      [XLEN-1:0]  mem_addr_o,     // 外部 MEM 地址
    output                  icache_miss,    // miss 信号，传给 bus 做仲裁

    

    // ========== 来自 ctrl 的重定向信号 ==========
    input                   redirect_i,     

    // ========== FENCE.I 缓存刷新 ==========
    input                   fence_i_flush
);

    // =========================================================================
    // 参数计算
    // =========================================================================
    localparam INDEX_WIDTH  = $clog2(ICACHE_SET_SIZE);                  // 6
    localparam WOFF_WIDTH   = $clog2(ICACHE_LINE_WORDS);               // 2
    localparam TAG_WIDTH    = XLEN - INDEX_WIDTH - WOFF_WIDTH - 2;      // 22(RV32)
    localparam WDATA_W      = INDEX_WIDTH + WOFF_WIDTH;                // 8  ({idx, woff})

    localparam IDLE     = 1'b0;
    localparam FILL     = 1'b1;
    reg       state;
    reg       next_state;
    reg [2:0] fill_cnt;   // 0~5

    // =========================================================================
    // 地址分解
    // =========================================================================
    wire [TAG_WIDTH-1:0]   req_tag  = cpu_addr_i[XLEN-1:INDEX_WIDTH+WOFF_WIDTH+2];
    wire [INDEX_WIDTH-1:0] req_idx  = cpu_addr_i[INDEX_WIDTH+WOFF_WIDTH+1:WOFF_WIDTH+2];
    wire [WOFF_WIDTH-1:0]  req_woff = cpu_addr_i[WOFF_WIDTH+1:2];

    // =========================================================================
    // Way0 / Way1 Tag 存储（分布式 RAM，异步读）
    // =========================================================================
    (* ram_style = "distributed" *) reg [TAG_WIDTH-1:0] tag_way0 [0:ICACHE_SET_SIZE-1];
    (* ram_style = "distributed" *) reg [TAG_WIDTH-1:0] tag_way1 [0:ICACHE_SET_SIZE-1];

    wire [TAG_WIDTH-1:0] tag_way0_out = tag_way0[req_idx];
    wire [TAG_WIDTH-1:0] tag_way1_out = tag_way1[req_idx];

    // =========================================================================
    // Data 存储（两路独立 BRAM，每路 256×32 = 64组×4字）
    // 地址直连 {req_idx, req_woff}，组合逻辑驱动 BRAM 地址端口
    // =========================================================================
    (* ram_style = "block" *) reg [31:0] data_way0 [0:(1<<WDATA_W)-1];
    (* ram_style = "block" *) reg [31:0] data_way1 [0:(1<<WDATA_W)-1];
    reg [31:0] data_way0_out;
    reg [31:0] data_way1_out;

    // =========================================================================
    // Valid 位 & LRU 位（FF 实现）
    // =========================================================================
    reg [ICACHE_SET_SIZE-1:0] valid_way0;
    reg [ICACHE_SET_SIZE-1:0] valid_way1;
    reg [ICACHE_SET_SIZE-1:0] lru;      // 0=way0为LRU, 1=way1为LRU

    // =========================================================================
    // Tag 比较 & Hit 判断
    // =========================================================================
    wire hit_way0 = valid_way0[req_idx] && (tag_way0_out == req_tag);
    wire hit_way1 = valid_way1[req_idx] && (tag_way1_out == req_tag);
    wire hit = (hit_way0 || hit_way1) && (state == IDLE);

    // 寄存 hit_way0/hit_way1，与 data_way0_out/data_way1_out 同拍更新
    reg hit_way0_r, hit_way1_r;

    // =========================================================================
    // 替换策略 — 选择 Victim Way
    // =========================================================================
    wire way0_invalid = ~valid_way0[req_idx];
    wire way1_invalid = ~valid_way1[req_idx];
    wire victim_way = way0_invalid ? 1'b0 :    // 优先填充无效路
                      way1_invalid ? 1'b1 :
                      lru[req_idx];            // 都有效则按 LRU

    wire fetch_miss  = (state == IDLE) && !hit && !redirect_i && !fence_i_flush;
    wire fill_active = (state == FILL) && mem_rdata_valid;
    reg [TAG_WIDTH-1:0]   miss_tag;
    reg [INDEX_WIDTH-1:0] miss_idx;
    reg [WOFF_WIDTH-1:0]  miss_woff;
    reg                   miss_way;

    always @(posedge clk or negedge rst_n) 
    begin
        if (!rst_n) 
        begin
            miss_tag  <= {TAG_WIDTH{1'b0}};
            miss_idx  <= {INDEX_WIDTH{1'b0}};
            miss_woff <= {WOFF_WIDTH{1'b0}};
            miss_way  <= 1'b0;
        end 
        else if (fetch_miss) 
        begin
            miss_tag  <= req_tag;
            miss_idx  <= req_idx;
            miss_woff <= req_woff;
            miss_way  <= victim_way;
        end
    end

    wire [WOFF_WIDTH-1:0] fill_resp_woff = miss_woff + fill_cnt[1:0];
    // =========================================================================
    // BRAM 读写地址
    // =========================================================================
    wire [WDATA_W-1:0]   rd_addr = {req_idx, req_woff};

    wire [1:0] wr_word = fill_resp_woff;
    wire [WDATA_W-1:0]   wr_addr = {miss_idx, wr_word};

    // =========================================================================
    // 写使能
    // =========================================================================
    wire cache_we = fill_active;

    // =========================================================================
    // Hit 打拍对齐 BRAM 读延迟
    // =========================================================================
    reg hit_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            hit_r <= 1'b0;
        else if (redirect_i || fence_i_flush)
            hit_r <= 1'b0;
        else
            hit_r <= hit;
    end

    // =========================================================================
    // BRAM — 读／写分开
    // =========================================================================
    wire [31:0] data_out;
    assign data_out = hit_way0_r ? data_way0_out : data_way1_out;

    assign cpu_inst_o = hit_r ? data_out : 32'h00000013;

    assign icache_miss = fetch_miss;
    assign mem_addr_o  = cpu_addr_i;

    // =========================================================================
    // Stall 输出
    // =========================================================================
    assign cpu_stall_o = !(hit && hit_r);
    // Way0 读
    always @(posedge clk) begin
        data_way0_out <= data_way0[rd_addr];
    end
    // Way0 写
    always @(posedge clk) begin
        if (cache_we && (miss_way == 0))
            data_way0[wr_addr] <= mem_rdata_i;
    end

    // hit_way0/hit_way1 寄存（与 data_way0_out/data_way1_out 同拍）
    always @(posedge clk) begin
        hit_way0_r <= hit_way0;
        hit_way1_r <= hit_way1;
    end

    // Way1 读
    always @(posedge clk) begin
        data_way1_out <= data_way1[rd_addr];
    end
    // Way1 写
    always @(posedge clk) begin
        if (cache_we && (miss_way == 1))
            data_way1[wr_addr] <= mem_rdata_i;
    end

    // =========================================================================
    // FSM 次态逻辑（组合）
    // =========================================================================
    always @(*) begin
        case (state)
            IDLE: next_state = fetch_miss ? FILL : IDLE;
            FILL: next_state = (fill_cnt == 3'd3 && mem_rdata_valid) ? IDLE : FILL;
            default: next_state = IDLE;
        endcase
    end

    // =========================================================================
    // FSM 状态寄存（redirect_i 不会中止填充，避免 AXI 数据污染）
    // =========================================================================
    always @(posedge clk or negedge rst_n) 
    begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= next_state;
    end

    // =========================================================================
    // Fill 计数器（0~5，替代 FILL_0~FILL_RD 离散状态）
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            fill_cnt <= 3'd0;
        else if (state == IDLE)
            fill_cnt <= 3'd0;
        else if(fill_active)
            fill_cnt <= fill_cnt + 1'd1;
    end


    // =========================================================================
    // Tag 写
    // =========================================================================
    always @(posedge clk) 
    begin
        if (fill_active && fill_cnt == 3'd3 && (miss_way == 0))
            tag_way0[miss_idx] <= miss_tag;
    end

    always @(posedge clk) 
    begin
        if (fill_active && fill_cnt == 3'd3 && (miss_way == 1))
            tag_way1[miss_idx] <= miss_tag;
    end

    // =========================================================================
    // Valid / LRU 更新
    // =========================================================================
    always @(posedge clk or negedge rst_n) 
    begin
        if (!rst_n) 
        begin
            valid_way0 <= {ICACHE_SET_SIZE{1'b0}};
            valid_way1 <= {ICACHE_SET_SIZE{1'b0}};
            lru        <= {ICACHE_SET_SIZE{1'b0}};
        end 
        else 
        begin
            if (fence_i_flush) 
            begin
                valid_way0 <= {ICACHE_SET_SIZE{1'b0}};
                valid_way1 <= {ICACHE_SET_SIZE{1'b0}};
            end

            if (fetch_miss)
            begin
                if (victim_way == 0)
                    valid_way0[req_idx] <= 1'b0;
                else
                    valid_way1[req_idx] <= 1'b0;
            end

            if (fill_active && fill_cnt == 3'd3)
            begin
                if (miss_way == 0)
                begin
                    valid_way0[miss_idx] <= 1'b1;
                end
                else
                begin
                    valid_way1[miss_idx] <= 1'b1;
                end
                lru[miss_idx] <= ~miss_way;
            end

            if (hit && state == IDLE)
            begin
                if (hit_way0)
                    lru[req_idx] <= 1'b1;
                else
                    lru[req_idx] <= 1'b0;
            end
        end
    end

endmodule

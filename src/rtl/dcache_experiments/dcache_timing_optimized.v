`timescale 1ns / 1ps

module dcache #(
    parameter XLEN = 32,
    parameter DCACHE_SET_SIZE = 64,
    parameter DCACHE_LINE_WORDS = 4
)(
    input                   clk,
    input                   rst_n,

    // ========== CPU 接口（来自 ex_stage，送到 mem_stage） ==========
    input       [XLEN-1:0]  cpu_addr_i,
    input       [XLEN-1:0]  cpu_wdata_i,
    input       [XLEN/8-1:0]cpu_wmask_i,
    input                   cpu_re_i,
    input                   cpu_we_i,
    input                   cpu_req_stall_i,
    output      [XLEN-1:0]  cpu_rdata_o,
    output                  cpu_stall_o,

    // ========== Bus 接口（直连 bus_interconnect） ==========
    output      [XLEN-1:0]  bus_addr_o,
    output                  bus_mem_re_o,
    output                  bus_mem_we_o,
    output                  bus_mmio_re_o,
    output                  bus_mmio_we_o,
    output      [XLEN/8-1:0]bus_wmask_o,
    output      [XLEN-1:0]  bus_wdata_o,
    output                  bus_load_miss_o,
    output                  bus_store_miss_o,
    input       [XLEN-1:0]  bus_rdata_i,
    input                   bus_rdata_valid_i

);

    // =========================================================================
    // 参数计算
    // =========================================================================
    localparam BOFF_WIDTH   = $clog2(XLEN/8);   // RV32=2, RV64=3
    localparam INDEX_WIDTH  = $clog2(DCACHE_SET_SIZE);
    localparam WOFF_WIDTH   = $clog2(DCACHE_LINE_WORDS);
    localparam TAG_WIDTH    = XLEN - INDEX_WIDTH - WOFF_WIDTH - BOFF_WIDTH;
    localparam WDATA_W      = INDEX_WIDTH + WOFF_WIDTH;

    // =========================================================================
    // 地址分解 & 可缓存判断
    // =========================================================================
    wire [TAG_WIDTH-1:0]   req_tag  = cpu_addr_i[XLEN-1:INDEX_WIDTH+WOFF_WIDTH+BOFF_WIDTH];
    wire [INDEX_WIDTH-1:0] req_idx  = cpu_addr_i[INDEX_WIDTH+WOFF_WIDTH+BOFF_WIDTH-1:WOFF_WIDTH+BOFF_WIDTH];
    wire [WOFF_WIDTH-1:0]  req_woff = cpu_addr_i[WOFF_WIDTH+BOFF_WIDTH-1:BOFF_WIDTH];

    wire cacheable = (cpu_addr_i[31:20] == 12'h100);


    // =========================================================================
    // Way0 / Way1 Tag 存储（分布式 RAM，异步读）
    // =========================================================================
    (* ram_style = "distributed" *)
    reg [TAG_WIDTH-1:0] tag_way0 [0:DCACHE_SET_SIZE-1];
    (* ram_style = "distributed" *)
    reg [TAG_WIDTH-1:0] tag_way1 [0:DCACHE_SET_SIZE-1];

    wire [TAG_WIDTH-1:0] tag_way0_out = tag_way0[req_idx];
    wire [TAG_WIDTH-1:0] tag_way1_out = tag_way1[req_idx];

    // =========================================================================
    // Data 存储（两路独立 BRAM，每路 256×XLEN = 64组×4字）
    // 地址直连 {req_idx, req_woff}，组合逻辑驱动 BRAM 地址端口
    // =========================================================================
    (* ram_style = "block" *) reg [XLEN-1:0] data_way0 [0:(1<<WDATA_W)-1];
    (* ram_style = "block" *) reg [XLEN-1:0] data_way1 [0:(1<<WDATA_W)-1];
    reg [XLEN-1:0] data_way0_out;
    reg [XLEN-1:0] data_way1_out;

    // =========================================================================
    // Valid 位 & LRU 位（FF 实现）
    // =========================================================================
    reg [DCACHE_SET_SIZE-1:0] valid_way0;
    reg [DCACHE_SET_SIZE-1:0] valid_way1;
    reg [DCACHE_SET_SIZE-1:0] lru;

    // =========================================================================
    // Tag 比较 & Hit 判断
    // =========================================================================
    wire hit_way0 = cacheable && valid_way0[req_idx] && (tag_way0_out == req_tag);
    wire hit_way1 = cacheable && valid_way1[req_idx] && (tag_way1_out == req_tag);
    wire hit = hit_way0 || hit_way1;

    // 寄存 hit_way0/hit_way1，与 data_way0_out/data_way1_out 同拍更新
    reg hit_way0_r, hit_way1_r;

    // =========================================================================
    // 替换策略
    // =========================================================================
    wire way0_invalid = ~valid_way0[req_idx];
    wire way1_invalid = ~valid_way1[req_idx];
    wire victim_way = way0_invalid ? 1'b0 :
                      way1_invalid ? 1'b1 :
                      lru[req_idx];

    // =========================================================================
    // FSM 状态定义
    // =========================================================================
    localparam IDLE       = 2'd0;
    localparam FILL       = 2'd1;
    localparam STORE_WAIT = 2'd2;

    reg [1:0] state;
    reg [1:0] next_state;
    reg [2:0] fill_cnt;

    // Registered request bundle sent to bus_interconnect.
    reg [XLEN-1:0]      bus_addr_r;
    reg [XLEN-1:0]      bus_wdata_r;
    reg [XLEN/8-1:0]    bus_wmask_r;
    reg                 bus_mem_re_r;
    reg                 bus_mem_we_r;
    reg                 bus_mmio_re_r;
    reg                 bus_mmio_we_r;
    reg                 bus_load_miss_r;
    reg                 bus_store_miss_r;
    wire cache_access_fire = (state == IDLE) && !cpu_req_stall_i;
    wire mmio_access_fire = cache_access_fire;

    // =========================================================================
    // Miss 地址锁存（填充期间使用）
    // =========================================================================
    reg [TAG_WIDTH-1:0]   miss_tag;
    reg [INDEX_WIDTH-1:0] miss_idx;
    reg [WOFF_WIDTH-1:0]  miss_woff;
    reg                   miss_way;

    // =========================================================================
    // BRAM 读写地址
    // =========================================================================
    wire [WDATA_W-1:0]   rd_addr = {req_idx, req_woff};

    wire [1:0] wr_word = miss_woff + fill_cnt[1:0];
    wire [WDATA_W-1:0] fill_wr_addr = {miss_idx, wr_word};

    // =========================================================================
    // 写使能
    // =========================================================================
    wire fill_we = (state == FILL) && bus_rdata_valid_i;
    wire fill_way0_we = fill_we && (miss_way == 0);
    wire fill_way1_we = fill_we && (miss_way == 1);
    wire load_miss_now = cache_access_fire && cpu_re_i && cacheable && !hit;
    wire store_now = cache_access_fire && cpu_we_i && cacheable;
    wire store_cache_write = store_now;
    wire mmio_read_now = mmio_access_fire && cpu_re_i && !cacheable;
    wire mmio_write_now = mmio_access_fire && cpu_we_i && !cacheable;
    wire bus_req_capture = load_miss_now || store_now || mmio_read_now || mmio_write_now;
    wire store_miss = store_now && !hit;

    // =========================================================================
    // TIMING OPTIMIZATION: Pipeline bus_req_capture to break critical path
    // 时序优化: 将bus_req_capture流水线化，打破关键路径
    //
    // Critical path before: rs1_o_reg -> data_forward -> addr_calc ->
    //                       tag_read -> tag_compare -> hit -> bus_req_capture ->
    //                       bus_addr_r/CE (9.85ns, WNS=-0.177ns)
    //
    // After optimization: Split into two cycles:
    //   Cycle N:   rs1_o_reg -> ... -> bus_req_capture -> bus_req_capture_q/D (~7ns)
    //   Cycle N+1: bus_req_capture_q/Q -> bus_addr_r/CE (~0.5ns)
    //
    // Expected improvement: WNS from -0.177ns to +0.5ns or better
    // Trade-off: Cache miss latency +1 cycle (~+10%, <1% overall performance impact)
    //
    // DONT_TOUCH attribute prevents synthesis optimization from removing pipeline registers
    // =========================================================================
    (* DONT_TOUCH = "TRUE" *) reg bus_req_capture_q;
    (* DONT_TOUCH = "TRUE" *) reg [XLEN-1:0] cpu_addr_q;
    (* DONT_TOUCH = "TRUE" *) reg [XLEN-1:0] cpu_wdata_q;
    (* DONT_TOUCH = "TRUE" *) reg [XLEN/8-1:0] cpu_wmask_q;
    (* DONT_TOUCH = "TRUE" *) reg load_miss_q, store_q, store_miss_q;
    (* DONT_TOUCH = "TRUE" *) reg mmio_read_q, mmio_write_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bus_req_capture_q <= 1'b0;
            cpu_addr_q <= {XLEN{1'b0}};
            cpu_wdata_q <= {XLEN{1'b0}};
            cpu_wmask_q <= {(XLEN/8){1'b0}};
            load_miss_q <= 1'b0;
            store_q <= 1'b0;
            store_miss_q <= 1'b0;
            mmio_read_q <= 1'b0;
            mmio_write_q <= 1'b0;
        end
        else begin
            // Pipeline bus_req_capture by one cycle
            bus_req_capture_q <= bus_req_capture;

            // Capture address and data when access fires
            if (cache_access_fire || mmio_access_fire) begin
                cpu_addr_q <= cpu_addr_i;
                cpu_wdata_q <= cpu_wdata_i;
                cpu_wmask_q <= cpu_wmask_i;
            end

            // Pipeline control signals
            load_miss_q <= load_miss_now;
            store_q <= store_now;
            store_miss_q <= store_miss;
            mmio_read_q <= mmio_read_now;
            mmio_write_q <= mmio_write_now;
        end
    end

    wire load_miss = load_miss_now;
    reg  load_miss_reg;

    always @(posedge clk or negedge rst_n)
    begin
        if (!rst_n)
            load_miss_reg <= 1'b0;
        else
            load_miss_reg <= load_miss;
    end

    // FILL 期间直接抓取 miss 需要的那一个字（不经过 BRAM 读）
    reg [XLEN-1:0] fill_capture_data;

    always @(posedge clk or negedge rst_n)
    begin
        if (!rst_n)
            fill_capture_data <= {XLEN{1'b0}};
        else if (fill_we && fill_cnt == 3'd0)
            fill_capture_data <= bus_rdata_i;
    end

    // fill_done_r: FILL→IDLE 过渡周期为高，用于在 stall 释放的当拍直接返回 fill_capture_data
    reg fill_done_r;

    always @(posedge clk or negedge rst_n)
    begin
        if (!rst_n)
            fill_done_r <= 1'b0;
        else
            fill_done_r <= (state == FILL) && (fill_cnt == 3'd3) && bus_rdata_valid_i;
    end

    always @(posedge clk or negedge rst_n)
    begin
        if (!rst_n)
        begin
            miss_tag  <= {TAG_WIDTH{1'b0}};
            miss_idx  <= {INDEX_WIDTH{1'b0}};
            miss_woff <= {WOFF_WIDTH{1'b0}};
            miss_way  <= 1'b0;
        end
        else if (load_miss_now)
        begin
            miss_tag  <= req_tag;
            miss_idx  <= req_idx;
            miss_woff <= req_woff;
            miss_way  <= victim_way;
        end
    end

    // =========================================================================
    // MMIO
    // =========================================================================
    reg uncached_req_r;
    reg mmio_read_wait_r;

    always @(posedge clk or negedge rst_n)
    begin
        if (!rst_n)
        begin
            uncached_req_r   <= 1'b0;
            mmio_read_wait_r <= 1'b0;
        end
        else
        begin
            if (mmio_read_now)
                uncached_req_r <= 1'b1;
            else if (bus_rdata_valid_i)
                uncached_req_r <= 1'b0;

            if (mmio_read_now)
                mmio_read_wait_r <= 1'b1;
            else if (bus_rdata_valid_i)
                mmio_read_wait_r <= 1'b0;
        end
    end

    // =========================================================================
    // BRAM - 读／写分开（与 icache 结构一致）
    // =========================================================================
    wire [XLEN-1:0] data_out = hit_way0_r ? data_way0_out : data_way1_out;

    assign cpu_rdata_o = uncached_req_r  ? bus_rdata_i :
                         fill_done_r     ? fill_capture_data :
                                          data_out;

    // =========================================================================
    // Stall 输出
    // =========================================================================
    assign cpu_stall_o = (state != IDLE) || load_miss_reg || mmio_read_wait_r;

    // Way0 Port A: CPU 读 / store-hit 字节写
    integer way0_cpu_byte_i;
    always @(posedge clk)
    begin
        data_way0_out <= data_way0[rd_addr];
        if (store_cache_write)
        begin
            for (way0_cpu_byte_i = 0; way0_cpu_byte_i < XLEN/8; way0_cpu_byte_i = way0_cpu_byte_i + 1)
            begin
                if (cpu_wmask_i[way0_cpu_byte_i])
                    data_way0[rd_addr][way0_cpu_byte_i*8 +: 8] <= cpu_wdata_i[way0_cpu_byte_i*8 +: 8];
            end
        end
    end

    // Way0 Port B: fill 全字写
    always @(posedge clk)
    begin
        if (fill_way0_we)
            data_way0[fill_wr_addr] <= bus_rdata_i;
    end

    // Way1 Port A: CPU 读 / store-hit 字节写
    integer way1_cpu_byte_i;
    always @(posedge clk)
    begin
        data_way1_out <= data_way1[rd_addr];
        if (store_cache_write)
        begin
            for (way1_cpu_byte_i = 0; way1_cpu_byte_i < XLEN/8; way1_cpu_byte_i = way1_cpu_byte_i + 1)
            begin
                if (cpu_wmask_i[way1_cpu_byte_i])
                    data_way1[rd_addr][way1_cpu_byte_i*8 +: 8] <= cpu_wdata_i[way1_cpu_byte_i*8 +: 8];
            end
        end
    end

    // Way1 Port B: fill 全字写
    always @(posedge clk)
    begin
        if (fill_way1_we)
            data_way1[fill_wr_addr] <= bus_rdata_i;
    end

    // hit_way0/hit_way1 寄存（与 data_way0_out/data_way1_out 同拍）
    always @(posedge clk)
    begin
        hit_way0_r <= hit_way0;
        hit_way1_r <= hit_way1;
    end

    // =========================================================================
    // FSM 次态逻辑（组合）
    // =========================================================================
    always @(*) begin
        case (state)
            IDLE:       next_state = load_miss_now ? FILL : IDLE;
            FILL:       next_state = (fill_cnt == 3'd3 && bus_rdata_valid_i) ? IDLE : FILL;
            default:    next_state = IDLE;
        endcase
    end

    // =========================================================================
    // FSM 状态寄存
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
    always @(posedge clk or negedge rst_n)
    begin
        if (!rst_n)
            fill_cnt <= 3'd0;
        else if (state == IDLE)
            fill_cnt <= 3'd0;
        else if(fill_we)
            fill_cnt <= fill_cnt + 1'd1;
    end

    // =========================================================================
    // 外部 MEM 接口控制 - MODIFIED FOR TIMING OPTIMIZATION
    // Use pipelined signals instead of combinational bus_req_capture
    // =========================================================================
    always @(posedge clk or negedge rst_n)
    begin
        if (!rst_n)
        begin
            bus_addr_r          <= {XLEN{1'b0}};
            bus_wdata_r         <= {XLEN{1'b0}};
            bus_wmask_r         <= {(XLEN/8){1'b0}};
        end
        else if (bus_req_capture_q)  // CHANGED: Use pipelined signal
        begin
            bus_addr_r  <= cpu_addr_q;   // CHANGED: Use captured address
            bus_wdata_r <= cpu_wdata_q;  // CHANGED: Use captured data
            bus_wmask_r <= cpu_wmask_q;  // CHANGED: Use captured mask
        end
    end

    always @(posedge clk or negedge rst_n)
    begin
        if (!rst_n)
        begin
            bus_mem_re_r     <= 1'b0;
            bus_mem_we_r     <= 1'b0;
            bus_load_miss_r  <= 1'b0;
            bus_store_miss_r <= 1'b0;
        end
        else
        begin
            bus_mem_re_r     <= load_miss_q;     // CHANGED: Use pipelined signal
            bus_mem_we_r     <= store_q;         // CHANGED: Use pipelined signal
            bus_load_miss_r  <= load_miss_q;     // CHANGED: Use pipelined signal
            bus_store_miss_r <= store_miss_q;    // CHANGED: Use pipelined signal
        end
    end

    always @(posedge clk or negedge rst_n)
    begin
        if (!rst_n)
        begin
            bus_mmio_re_r <= 1'b0;
            bus_mmio_we_r <= 1'b0;
        end
        else
        begin
            bus_mmio_re_r <= mmio_read_q;   // CHANGED: Use pipelined signal
            bus_mmio_we_r <= mmio_write_q;  // CHANGED: Use pipelined signal
        end
    end

    assign bus_addr_o = bus_addr_r;
    assign bus_mem_re_o = bus_mem_re_r;
    assign bus_mem_we_o = bus_mem_we_r;
    assign bus_mmio_re_o = bus_mmio_re_r;
    assign bus_mmio_we_o = bus_mmio_we_r;

    assign bus_wmask_o = bus_wmask_r;
    assign bus_wdata_o = bus_wdata_r;
    assign bus_load_miss_o = bus_load_miss_r;
    assign bus_store_miss_o = bus_store_miss_r;




    // =========================================================================
    // Tag 写（独立 always 块 → Vivado 推断分布式 RAM）
    // =========================================================================
    always @(posedge clk)
    begin
        if (fill_we && fill_cnt == 3'd3 && (miss_way == 0))
            tag_way0[miss_idx] <= miss_tag;
    end
    always @(posedge clk)
    begin
        if (fill_we && fill_cnt == 3'd3 && (miss_way == 1))
            tag_way1[miss_idx] <= miss_tag;
    end

    // =========================================================================
    // Valid / LRU 更新
    // =========================================================================
    always @(posedge clk or negedge rst_n)
    begin
        if (!rst_n)
        begin
            valid_way0 <= {DCACHE_SET_SIZE{1'b0}};
            valid_way1 <= {DCACHE_SET_SIZE{1'b0}};
            lru        <= {DCACHE_SET_SIZE{1'b0}};
        end
        else
        begin

            if (load_miss_now)
            begin
                if (victim_way == 0)
                    valid_way0[req_idx] <= 1'b0;
                else
                    valid_way1[req_idx] <= 1'b0;
            end

            if (store_cache_write)
            begin
                if (hit_way0)
                    valid_way1[req_idx] <= 1'b0;
                else if (hit_way1)
                    valid_way0[req_idx] <= 1'b0;
                else
                begin
                    valid_way0[req_idx] <= 1'b0;
                    valid_way1[req_idx] <= 1'b0;
                end
            end

            if (fill_we && fill_cnt == 3'd3)
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

            if (cache_access_fire && hit && (cpu_re_i || cpu_we_i))
            begin
                if (hit_way0)
                    lru[req_idx] <= 1'b1;
                else
                    lru[req_idx] <= 1'b0;
            end
        end
    end

endmodule

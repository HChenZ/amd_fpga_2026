`timescale 1ns / 1ps
module bus_interconnect #(
    parameter XLEN = 32
)(
    input          clk,
    input          rst_n,

    // ==========================================
    // CPU Core 接口 (Master, 数据访存端口B)
    // ==========================================
    input   [XLEN-1:0]    cpu_addr,
    input   [XLEN-1:0]    cpu_wdata,
    input   [XLEN/8-1:0]  cpu_w_mask,
    input                 mem_re,
    input                 mem_we,
    input                 mmio_re,
    input                 mmio_we,
    input                 load_miss_i,
    input                 store_miss_i,
    output  [XLEN-1:0]    cpu_rdata,
    output                cpu_rdata_valid,
    output                cpu_axi_stall_req,

    // ==========================================
    // I-Cache CPU 侧接口
    // ==========================================
    input                   icache_miss_i,
    input   [XLEN-1:0]      icache_addr_i,
    output  [31:0]          icache_rdata_o,
    output                  icache_rdata_valid_o,

    // ==========================================
    // 统一 Cache 接口（→ Bridge）
    // ==========================================
    input                   cache_ready_i,
    input     [XLEN-1:0]    cache_rdata_i,
    input                   cache_rdata_valid_i,
    input                   cache_rdata_last_i,
    input                   write_full_i,
    input                   write_empty_i,
    input                   write_done_pulse_i,
    input                   cache_rid_i,    
    output                  cache_re_o,
    output                  cache_we_o,
    output reg [XLEN-1:0]   cache_addr_o,
    output    [XLEN-1:0]    cache_waddr_o,
    output    [XLEN-1:0]    cache_wdata_o,
    output    [XLEN/8-1:0]  cache_wmask_o,
    output    [2:0]         cache_arsize_o,
    output                  cache_rid_o,
    output                  cache_valid_o,
    output                  write_done_pulse_o,


    // ==========================================
    // CLINT 接口
    // ==========================================
    output                  clint_re,
    output                  clint_we,
    output reg [2:0]        clint_addr_sel,
    output     [XLEN-1:0]   clint_wdata,
    output     [XLEN/8-1:0] clint_w_mask,
    input      [XLEN-1:0]   clint_rdata,

    // ==========================================
    // UART 接口
    // ==========================================
    output              uart_re,
    output              uart_we,
    output reg [1:0]    uart_addr_sel,
    output     [31:0]   uart_wdata,
    input      [31:0]   uart_rdata,

    // ==========================================
    // GPIO 接口
    // ==========================================
    output         gpio_re,
    output         gpio_we,
    output  reg    gpio_addr_sel,
    output  [31:0] gpio_wdata,
    input   [31:0] gpio_rdata,

    // ==========================================
    // CPI_cnt
    // ==========================================
    output          cpi_re,
    output reg [2:0] cpi_addr_sel,
    input   [XLEN-1:0] cpi_rdata
);

    // 地址对齐
    wire [XLEN-1:0] cpu_addr_align;
    generate
      if(XLEN==64)
        assign cpu_addr_align = {cpu_addr[XLEN-1:3], 3'b000};
      else
        assign cpu_addr_align = {cpu_addr[XLEN-1:2], 2'b00};
    endgenerate

    // =================================================================
    // 地址译码
    // 地址映射：
    //   mem   : 0x10000000 (统一代码+数据空间)
    //   clint : 0x12000000
    //   uart  : 0x20000000
    //   gpio  : 0x20010000
    //   cpi   : 0x60000000
    // =================================================================
    wire [15:0] addr_high = cpu_addr[31:16];

    wire hit_mem   = (addr_high[15:4] == 12'h100);
    wire hit_clint = (addr_high == 16'h1200);
    wire hit_uart  = (addr_high == 16'h2000);
    wire hit_gpio  = (addr_high == 16'h2001);
    wire hit_cpi   = (addr_high == 16'h6000);


    // =================================================================
    // BUS总线状态机控制
    // =================================================================
    localparam RD_IDLE = 2'b00;
    localparam RD_DCACHE_WAIT_HS = 2'b01;    
    localparam RD_ICACHE_WAIT_HS = 2'b10;       
    localparam RD_BUSY = 2'b11;
    reg              store_fifo_not_empty;
    reg              we_buf;
    reg   [XLEN-1:0] waddr_buf;
    reg   [XLEN-1:0] wdata_buf;
    reg   [XLEN/8-1:0] wmask_buf;
    reg   [1:0]      rd_state;
    reg   [1:0]      rd_next_state;
    reg   [XLEN-1:0] dcache_re_addr;
    reg   [XLEN-1:0] icache_re_addr;   
    reg              dcache_re_buf; 
    reg              icache_re_buf; 
    reg   [1:0]      icache_resp_cnt;
    wire             mem_re_reg;
    wire             icache_rdata_fire = (rd_state == RD_BUSY) && (cache_rid_i == 1'b0) && cache_rdata_valid_i;
    wire             store_we_to_bridge = we_buf || mem_we;

    always @(posedge clk or negedge rst_n)
    begin
        if (!rst_n)
          rd_state <= 2'h0;
        else 
          rd_state <= rd_next_state;
    end

    always @(*)
    begin
      case(rd_state)
      RD_IDLE:
      begin
        cache_addr_o = cpu_addr;
        if(mem_re)
          rd_next_state = RD_DCACHE_WAIT_HS;
        else if(icache_miss_i)
          rd_next_state = RD_ICACHE_WAIT_HS;
        else 
          rd_next_state = RD_IDLE;
      end
      RD_DCACHE_WAIT_HS:
      begin
        rd_next_state = (cache_valid_o & cache_ready_i & cache_re_o) ? RD_BUSY : RD_DCACHE_WAIT_HS;
        cache_addr_o = dcache_re_addr;
      end
      RD_ICACHE_WAIT_HS:
      begin
        rd_next_state = (cache_valid_o & cache_ready_i & cache_re_o) ? RD_BUSY : RD_ICACHE_WAIT_HS; 
        cache_addr_o = icache_re_addr;
      end
      RD_BUSY:
      begin
        cache_addr_o = cpu_addr;

                                     
        if(cache_rdata_last_i & cache_rdata_valid_i)
        begin
          if(dcache_re_buf)
            rd_next_state = RD_DCACHE_WAIT_HS;
          else if(icache_re_buf)
            rd_next_state = RD_ICACHE_WAIT_HS;          
          else
          rd_next_state = RD_IDLE;            
        end
        else
          rd_next_state = RD_BUSY;
      end
      default:
      begin
        cache_addr_o = cpu_addr;
        rd_next_state = RD_IDLE;
      end
      endcase
    end

    always @(posedge clk or negedge rst_n)
    begin
        if(!rst_n)
        begin
          dcache_re_addr <= {XLEN{1'b0}};
        end
        else if(mem_re)
        begin
          dcache_re_addr <= cpu_addr_align;
        end
    end



    always @(posedge clk or negedge rst_n)
    begin
        if(!rst_n)
        begin
          icache_re_addr <= {XLEN{1'b0}};
        end
        else if(icache_miss_i)
        begin
          icache_re_addr <= icache_addr_i;
        end
    end


    always @(posedge clk or negedge rst_n)
    begin
        if(!rst_n)
          dcache_re_buf <= 1'b0;
        else if((rd_state != RD_IDLE) && mem_re)
          dcache_re_buf <= 1'b1;
        else if((rd_state == RD_DCACHE_WAIT_HS) && cache_valid_o & cache_ready_i & cache_re_o)
          dcache_re_buf <= 1'b0;
    end

    always @(posedge clk or negedge rst_n)
    begin
        if(!rst_n)
          icache_re_buf <= 1'b0;
        else if(((rd_state != RD_IDLE) || (mem_re)) && icache_miss_i)
          icache_re_buf <= 1'b1;
        else if((rd_state == RD_ICACHE_WAIT_HS) && cache_valid_o & cache_ready_i & cache_re_o)
          icache_re_buf <= 1'b0;
    end

    always @(posedge clk or negedge rst_n)
    begin
        if(!rst_n)
          icache_resp_cnt <= 2'b00;
        else if((rd_state == RD_ICACHE_WAIT_HS) && cache_valid_o && cache_ready_i && cache_re_o)
          icache_resp_cnt <= 2'b00;
        else if(icache_rdata_fire)
          icache_resp_cnt <= icache_resp_cnt + 1'b1;
    end

    always @(posedge clk or negedge rst_n)
    begin
        if(!rst_n)
            store_fifo_not_empty <= 1'b0;
        else if(store_we_to_bridge)
            store_fifo_not_empty <= 1'b1;
        else if(write_done_pulse_i)
            store_fifo_not_empty <= 1'b0;
    end

    always @(posedge clk or negedge rst_n)
    begin
        if(!rst_n)
        begin
            we_buf    <= 1'b0;
            waddr_buf <= {XLEN{1'b0}};
            wdata_buf <= {XLEN{1'b0}};
            wmask_buf <= {(XLEN/8){1'b0}};
        end
        else if(we_buf && !write_full_i)
        begin
            we_buf <= 1'b0;
        end
        else if(mem_we && write_full_i && !we_buf)
        begin
            we_buf    <= 1'b1;
            waddr_buf <= cpu_addr;
            wdata_buf <= cpu_wdata;
            wmask_buf <= cpu_w_mask;
        end
    end


    // =================================================================
    // AXI接口信号
    // =================================================================

    //发送给AXI信号
    assign cache_we_o = store_we_to_bridge;
    assign cache_re_o = (rd_state == RD_DCACHE_WAIT_HS && ~store_fifo_not_empty) || (rd_state == RD_ICACHE_WAIT_HS);    
    assign cache_waddr_o = we_buf ? waddr_buf : cpu_addr;
    assign cache_wdata_o = we_buf ? wdata_buf : cpu_wdata;
    assign cache_wmask_o = we_buf ? wmask_buf : cpu_w_mask;
    assign cache_valid_o = (rd_state == RD_DCACHE_WAIT_HS) || (rd_state == RD_ICACHE_WAIT_HS); 
    assign cache_rid_o = (rd_state == RD_DCACHE_WAIT_HS) ? 1'b1 : 1'b0; 
    generate
      if(XLEN == 64)
      begin
        assign cache_arsize_o = (rd_state == RD_DCACHE_WAIT_HS) ? 3'b011 : 3'b010;
      end
      else 
      begin
        assign cache_arsize_o = 3'b010;
      end
    endgenerate


    //发送给icahce信号
    generate
      if(XLEN == 64)
      begin
        wire icache_lane_hi = icache_re_addr[2] ^ icache_resp_cnt[0];
        assign icache_rdata_o = icache_lane_hi ? cache_rdata_i[63:32] : cache_rdata_i[31:0];
      end
      else
      begin
        assign icache_rdata_o = cache_rdata_i;
      end
    endgenerate

    assign icache_rdata_valid_o = icache_rdata_fire;


    // =================================================================
    //写 FIFO 满时暂停CPU
    // =================================================================
    assign cpu_axi_stall_req = store_we_to_bridge && write_full_i;

    // =================================================================
    // write_done_pulse 透传
    // =================================================================
    assign write_done_pulse_o = write_done_pulse_i;

    // =================================================================
    // 外设接口 — 纯组合地址译码直传
    // =================================================================
    assign clint_re  = mmio_re & hit_clint;
    assign clint_we  = mmio_we & hit_clint;
    assign clint_w_mask = cpu_w_mask;
    assign clint_wdata  = cpu_wdata;

    assign uart_re = mmio_re & hit_uart;
    assign uart_we = mmio_we & hit_uart;

    assign gpio_re = mmio_re & hit_gpio;
    assign gpio_we = mmio_we & hit_gpio;

    assign cpi_re = mmio_re & hit_cpi;

    // uart 32位写数据
    wire [31:0] wdata_32;
    generate
      if(XLEN==64)
        assign wdata_32 = cpu_addr[2] ? cpu_wdata[XLEN-1:XLEN-32] : cpu_wdata[31:0];
      else
        assign wdata_32 = cpu_wdata[31:0];
    endgenerate
    assign uart_wdata = wdata_32;
    assign gpio_wdata = wdata_32;

    // UART 地址选择
    wire [3:0] uart_addr = cpu_addr[3:0];
    always @(*)
    begin
      case(uart_addr)
        4'h0: uart_addr_sel = 2'b00;
        4'h4: uart_addr_sel = 2'b01;
        4'h8: uart_addr_sel = 2'b10;
        default: uart_addr_sel = 2'b00;
      endcase
    end

    // CLINT 地址选择
    wire [15:0] clint_addr = cpu_addr[15:0];
    always @(*)
    begin
      case(clint_addr)
        16'h0000: clint_addr_sel = 3'b000;
        16'h4000: clint_addr_sel = 3'b001;
        16'h4004: clint_addr_sel = 3'b010;
        16'hBFF8: clint_addr_sel = 3'b011;
        16'hBFFC: clint_addr_sel = 3'b100;
        default:  clint_addr_sel = 3'b000;
      endcase
    end

    // GPIO 地址选择
    wire [3:0] gpio_addr = cpu_addr[3:0];
    always @(*)
    begin
      case(gpio_addr)
        4'h0: gpio_addr_sel = 1'b0;
        4'h4: gpio_addr_sel = 1'b1;
        default: gpio_addr_sel = 1'b0;
      endcase
    end

    // CPI 地址选择
    wire [7:0] cpi_addr = cpu_addr[7:0];
    always @(*)
    begin
      case(cpi_addr)
        8'h00: cpi_addr_sel = 3'b000;
        8'h04: cpi_addr_sel = 3'b001;
        8'h08: cpi_addr_sel = 3'b010;
        8'h0C: cpi_addr_sel = 3'b011;
        8'h10: cpi_addr_sel = 3'b100;
        8'h14: cpi_addr_sel = 3'b101;
        8'h18: cpi_addr_sel = 3'b110;
        8'h1C: cpi_addr_sel = 3'b111;
        default: cpi_addr_sel = 3'b000;
      endcase
    end

    // =================================================================
    // 锁存片选信号（上一拍记录谁在读，用于对齐同步读回来的数据）
    // =================================================================

    reg cpi_re_reg;
    reg gpio_re_reg;
    reg uart_re_reg;
    reg clint_re_reg;    
    wire [4:0] read_sel_q;

    always @(posedge clk or negedge rst_n)
    begin
        if (!rst_n)
        begin
            cpi_re_reg   <= 1'b0;
            gpio_re_reg  <= 1'b0;
            uart_re_reg  <= 1'b0;
            clint_re_reg <= 1'b0;
        end
        else
        begin
            cpi_re_reg   <= cpi_re;
            gpio_re_reg  <= gpio_re;
            uart_re_reg  <= uart_re;
            clint_re_reg <= clint_re;
        end
    end

    wire dcache_rdata_valid = (cache_rid_i == 1'b1) && cache_rdata_valid_i;
    assign read_sel_q = {cpi_re_reg, gpio_re_reg, uart_re_reg, clint_re_reg, dcache_rdata_valid};


    // =================================================================
    // 读数据多路选择器
    // =================================================================
    wire [XLEN-1:0] uart_rdata_x;
    wire [XLEN-1:0] gpio_rdata_x;
    generate
      if(XLEN==64)
      begin
        assign uart_rdata_x = {uart_rdata, uart_rdata};
        assign gpio_rdata_x = {gpio_rdata, gpio_rdata};
      end
      else
      begin
        assign uart_rdata_x = uart_rdata;
        assign gpio_rdata_x = gpio_rdata;
      end
    endgenerate

    assign cpu_rdata =
        (read_sel_q[0] ? cache_rdata_i : {(XLEN){1'b0}}) |
        (read_sel_q[1] ? clint_rdata  : {(XLEN){1'b0}}) |
        (read_sel_q[2] ? uart_rdata_x : {(XLEN){1'b0}}) |
        (read_sel_q[3] ? gpio_rdata_x : {(XLEN){1'b0}}) |
        (read_sel_q[4] ? cpi_rdata    : {(XLEN){1'b0}});

    assign cpu_rdata_valid = dcache_rdata_valid;

endmodule

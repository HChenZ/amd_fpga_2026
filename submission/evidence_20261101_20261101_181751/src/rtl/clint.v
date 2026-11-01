`timescale 1ns / 1ps
module clint #(
    parameter XLEN = 32
)(
    input   clk, 
    input   rst_n,
    
    // MMIO 总线接口 (来自 bus_interconnect)
    input                   clint_re,   // 读使能
    input                   clint_we,   // 写使能
    input       [2:0]       clint_addr_sel, // 内部偏移地址
    input       [XLEN-1:0]  clint_wdata,// 写入的数据
    input       [XLEN/8-1:0]clint_w_mask,
    output reg  [XLEN-1:0]  clint_rdata,// 读出的数据

    // 输出给 CPU 核的两根中断线
    output              irq_timer,     // 定时器中断 (MTI)
    output              irq_software   // 软件中断 (MSI)
    );

    //写数据时MASK的位宽
    localparam MASK_LEN = XLEN/8;
    integer i;


    // 定义 64 位寄存器
    reg [63:0]   mtime;
    reg [63:0]   mtimecmp;
    reg [XLEN-1:0]   msip;

    // mtime 硬件自增逻辑
    always @(posedge clk or negedge rst_n) 
    begin
        if (!rst_n) 
          mtime <= 64'b0;
        else        
          mtime <= mtime + 1'b1; // 每个时钟周期自动加 1
    end

    // =========================================================
    // 写逻辑
    // =========================================================

    reg [XLEN-1:0] clint_wdata_real;
    reg [XLEN-1:0] clint_wdata_old;

    always @(*)
    begin
      case (clint_addr_sel)
        3'b000: clint_wdata_old = msip;
        3'b001: clint_wdata_old = (XLEN == 64) ? mtimecmp : mtimecmp[31:0];
        3'b010: clint_wdata_old = (XLEN == 64) ? mtimecmp : mtimecmp[63:32];
        default: clint_wdata_old = {XLEN{1'b0}};
      endcase

      clint_wdata_real = clint_wdata_old;
      if(clint_we)
      begin
        for (i = 0; i < MASK_LEN; i = i + 1) 
        begin
            if (clint_w_mask[i]) 
                clint_wdata_real[i*8 +: 8] = clint_wdata[i*8 +: 8];
        end
      end
    end

    always @(posedge clk or negedge rst_n)
    begin
        if (!rst_n) 
        begin
            mtimecmp <= 64'hFFFFFFFF_FFFFFFFF; // 初始设为最大值，防止一开机就中断
            msip     <= {XLEN{1'b0}};
        end 
        else if (clint_we) 
        begin
            case (clint_addr_sel)
                // msip 软件中断地址
                3'b000: msip <= clint_wdata_real;
                // mtimecmp 低 32 位地址
                3'b001: 
                begin
                    if(XLEN == 64)
                      mtimecmp  <= clint_wdata_real; 
                    else
                      mtimecmp[31:0]  <= clint_wdata_real; 
                end
                // mtimecmp 高 32 位地址
                3'b010: 
                begin
                    if(XLEN == 64)
                      mtimecmp <= clint_wdata_real;
                    else
                      mtimecmp[63:32] <= clint_wdata_real;
                end
                default:;
            endcase
        end
    end

    // =========================================================
    // 读逻辑
    // =========================================================
    always @(posedge clk or negedge rst_n) 
    begin
        if (!rst_n) 
            clint_rdata = {(XLEN){1'b0}};
        else if (clint_re) 
        begin
            case (clint_addr_sel)
                3'b000: clint_rdata =  msip;         
                3'b001: clint_rdata = (XLEN == 64) ? mtimecmp : mtimecmp[31:0]; // rv32时读mtimecmp低 32位；rv64时读rv32时读mtimecmp
                3'b010: clint_rdata = (XLEN == 64) ? {XLEN{1'b0}} : mtimecmp[63:32];                          // 读mtimecmp 高 32 位
                3'b011: clint_rdata = (XLEN == 64) ? mtime : mtime[31:0];       // rv32时读 mtime 低32位；rv64时读mtime
                3'b100: clint_rdata = (XLEN == 64) ? {XLEN{1'b0}} : mtime[63:32];                             // 读 mtime 高32位               
                default:;
            endcase
        end
    end

    // =========================================================
    // 生成中断信号
    // =========================================================
    // 定时器中断：只要 mtime 跑到了 mtimecmp 的值，就一直拉高！
    assign irq_timer = (mtime >= mtimecmp); 
    
    // 软件中断：只要 msip 最低位为 1，就拉高
    assign irq_software = msip[0];

endmodule

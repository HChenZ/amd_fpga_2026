`timescale 1ns / 1ps

module axi_master #(
    parameter XLEN = 32
)
(
    input                       m_aclk,
    input                       m_arst_n,
    /* ------------------- AW: 写地址通道 (Write Address) ------------------- */
    input                       m_awready,
    output  reg                 m_awvalid,
    output  reg                 m_awid,
    output  reg [XLEN-1:0]      m_awaddr,
    output  reg [7:0]           m_awlen,
    output  reg [2:0]           m_awsize,
    output  reg [1:0]           m_awburst,
    output  reg                 m_awlock,
    output  reg [3:0]           m_awcache,
    output  reg [2:0]           m_awprot,
    output  reg [3:0]           m_awqos,
    output  reg [3:0]           m_awregion,
    output  reg                 m_awuser,

    /* ------------------- W: 写数据通道 (Write Data) --------------------- */
    input                       m_wready,
    output  reg                 m_wvalid,
    output                      m_wlast,
    output  reg [XLEN-1:0]      m_wdata,
    output  reg [(XLEN/8)-1:0]  m_wstrb,
    output  reg                 m_wuser,

    /* ------------------- B: 写响应通道 (Write Response) ----------------- */
    input                       m_bvalid,
    input                       m_bid,
    input   [1:0]               m_bresp,
    input                       m_buser,
    output  reg                 m_bready,

    /* ------------------- AR: 读地址通道 (Read Address) ------------------ */
    input                       m_arready,
    output  reg                 m_arvalid,
    output  reg                 m_arlock,
    output  reg                 m_arid,
    output  reg [XLEN-1:0]      m_araddr,
    output  reg [7:0]           m_arlen,
    output  reg [2:0]           m_arsize,
    output  reg [1:0]           m_arburst,
    output  reg [3:0]           m_arcache,
    output  reg [2:0]           m_arprot,
    output  reg [3:0]           m_arqos,
    output  reg [3:0]           m_arregion,
    output  reg                 m_aruser,

     /* ------------------- R: 读数据通道 (Read Data) ---------------------- */
    input                       m_rvalid,
    input                       m_rlast,
    input                       m_rid,
    input       [XLEN-1:0]      m_rdata,
    input       [1:0]           m_rresp,
    input                       m_ruser,
    output  reg                 m_rready,

     /* -------------------------- 自定义信号 ------------------------------ */

    input                       cpu_re,         //cpu读请求
    input                       cpu_we,         //cpu写请求
    input       [XLEN-1:0]      cpu_wdata,      //cpu写数据
    input       [XLEN-1:0]      cpu_raddr,      //cpu读请求地址
    input       [XLEN-1:0]      cpu_waddr,      //cpu写请求地址
    input       [XLEN/8-1:0]    cpu_wmask,      //cpu写数据掩码
    input                       cpu_wid,        //cpu写事务ID (0:I-CACHE  1:D-CACHE)
    input                       cpu_rid,        //cpu读事务ID (0:I-CACHE  1:D-CACHE)    
    input       [1:0]           cpu_arburst,    //cpu读Burst类型 (00=FIXED, 01=INCR, 10=WRAP)
    input       [2:0]           cpu_arsize,     //cpu读Burst每次传输大小 
    input       [7:0]           cpu_arlen,      //cpu读Burst长度
    input       [1:0]           cpu_awburst,    //cpu写Burst类型 (00=FIXED, 01=INCR, 10=WRAP)
    input       [2:0]           cpu_awsize,     //cpu写Burst每次传输大小 
    input       [7:0]           cpu_awlen,      //cpu写Burst长度   

    input                       cpu_wdata_valid,
    input                       cpu_rdata_ready,

    output  reg                 cpu_rid_o,
    output                      cpu_wdata_ready,
    output  reg                 cpu_rdata_valid,
    output      [XLEN-1:0]      cpu_rdata,      //cpu读数据   
    output  reg [1:0]           resp,           //axi写响应 
    output  reg                 resp_en         //axi写响应有效信号 


);
// =================================================================
// 信号定义
// =================================================================

    //写响应状态
    localparam  OKAY = 2'b00;
    localparam  EXOKAY = 2'b01;    
    localparam  SLVERR = 2'b10;
    localparam  DECERR = 2'b11;  

    //握手有效信号
    wire aw_hs_en = m_awready & m_awvalid;
    wire w_hs_en = m_wready & m_wvalid;
    wire b_hs_en = m_bready & m_bvalid;
    wire ar_hs_en = m_arready & m_arvalid;
    wire r_hs_en = m_rready & m_rvalid;

    //写地址(写数据)相关信号
    reg         aw_done;
    reg         w_done;

    //写通道状态机
    localparam  W_IDLE = 2'b00;
    localparam  W_WRITE = 2'b01;
    localparam  W_RESP = 2'b10;
    reg [1:0]  w_next_state;
    reg [1:0]  w_state;


    //读通道状态机
    localparam  R_IDLE = 2'b00;
    localparam  R_ADDR = 2'b01;
    localparam  R_DATA = 2'b10;
    reg [1:0]  r_next_state;
    reg [1:0]  r_state;     

    //计数器
    reg [7:0]   wdata_cnt;
    reg [1:0]   rdata_cnt;


    //存储相关信号
    reg [7:0]       wlen_buf;
    reg [2:0]       wsize_buf;
    reg [1:0]       wburst_buf;


    reg [7:0]       rlen_buf;
    reg [2:0]       rsize_buf;
    reg [1:0]       rburst_buf;

    reg [XLEN-1:0]  wdata_buf;


    //读取数据存储
    reg [XLEN-1:0]    rdata_buf;   


    //其他信号



// =================================================================
// 状态寄存
// =================================================================

    always @(posedge m_aclk or negedge m_arst_n)
    begin
        if(~m_arst_n)     
        begin 
            wlen_buf <= 8'h0;
            wsize_buf <= 3'h0;
            wburst_buf <= 2'h0;
        end
        else if(cpu_we && w_state == W_IDLE)
        begin
            wlen_buf <= cpu_awlen;
            wsize_buf <= cpu_awsize;
            wburst_buf <= cpu_awburst;            
        end
    end

    always @(posedge m_aclk or negedge m_arst_n)
    begin
        if(~m_arst_n)     
        begin 
            rlen_buf <= 8'h0;
            rsize_buf <= 3'h0;
            rburst_buf <= 2'h0;            
        end
        else if(cpu_re && r_state == R_IDLE)
        begin
            rlen_buf <= cpu_arlen;
            rsize_buf <= cpu_arsize;
            rburst_buf <= cpu_arburst;     
        end
    end


    //暂时固定属性
    always @(posedge m_aclk or negedge m_arst_n)
    begin
        if(~m_arst_n)     
        begin 
            m_awlock <= 1'b0;
            m_awcache <= 4'h0;
            m_awprot <= 3'h0;
            m_awqos <= 4'h0;
            m_awregion <= 4'h0;

            m_arlock <= 1'h0;
            m_arcache <= 4'h0;
            m_arprot <= 3'h0;
            m_arqos <= 4'h0;
            m_arregion <= 4'h0;

            m_awuser <= 1'b0;
            m_wuser <= 1'b0;
            m_aruser  <= 1'b0;
        end
        else 
        begin
            m_awlock <= 1'b0;
            m_awcache <= 4'b0011;
            m_awprot <= 3'h0;
            m_awqos <= 4'h0;
            m_awregion <= 4'h0;

            m_arlock <= 1'h0;
            m_arcache <= 4'b0011;
            m_arprot <= 3'h0;
            m_arqos <= 4'h0;
            m_arregion <= 4'h0;

            m_awuser <= 1'b0;
            m_wuser <= 1'b0;
            m_aruser  <= 1'b0;
        end
    end


// =================================================================
// 状态机
// =================================================================

    //写地址(写数据)通道
    always @(*)
    begin
        case(w_state)
        W_IDLE:
        begin
            w_next_state = cpu_we ? W_WRITE : W_IDLE;
        end
        W_WRITE:
        begin
            w_next_state = aw_done & w_done ? W_RESP : W_WRITE;
        end
        W_RESP:
        begin
            w_next_state = b_hs_en ? W_IDLE : W_RESP;
        end
        default:
        begin
            w_next_state = W_IDLE;
        end
        endcase

    end
    always @(posedge m_aclk or negedge m_arst_n)
    begin
        if(~m_arst_n)
            w_state <= 2'h0;
        else
            w_state <= w_next_state;
    end


    //读地址(读数据)通道
    always @(*)
    begin
        case(r_state)
        R_IDLE:
        begin
            r_next_state = cpu_re ? R_ADDR : R_IDLE;
        end
        R_ADDR:
        begin
            r_next_state = ar_hs_en ? R_DATA : R_ADDR;
        end
        R_DATA:
        begin
            r_next_state = r_hs_en & m_rlast ? R_IDLE : R_DATA;
        end
        default:
        begin
            r_next_state = R_IDLE;
        end
        endcase
    end
    always @(posedge m_aclk or negedge m_arst_n)
    begin
        if(~m_arst_n)
            r_state <= 2'b0;
        else
            r_state <= r_next_state;
    end    



// =================================================================
// 逻辑判断
// =================================================================


    //写地址结束标志
    always @(posedge m_aclk or negedge m_arst_n)
    begin
        if(~m_arst_n)
            aw_done <= 1'b0;
        else if(w_state == W_RESP)
            aw_done <= 1'b0;
        else if(w_state == W_WRITE && aw_hs_en)
            aw_done <= 1'b1;

    end


    //写数据结束标志
    always @(posedge m_aclk or negedge m_arst_n)
    begin
        if(~m_arst_n)
            w_done <= 1'b0;
        else if(w_state == W_RESP)
            w_done <= 1'b0;
        else if(w_hs_en && m_wlast)
            w_done <= 1'b1;
    end






// =================================================================
// 写地址通道
// =================================================================

    always @(posedge m_aclk or negedge m_arst_n)
    begin
        if(~m_arst_n)
        begin
            m_awaddr <= {XLEN{1'b0}};
            m_awlen <= 8'h0;
            m_awsize <= 3'h0;
            m_awburst <= 2'h0;
            m_awid <= 1'b0;
        end
        else if(cpu_we && w_state == W_IDLE)
        begin
            m_awaddr <= cpu_waddr;
            m_awlen <= cpu_awlen;
            m_awsize <= cpu_awsize;
            m_awburst <= cpu_awburst;
            m_awid <= cpu_wid;
        end
    end

    always @(posedge m_aclk or negedge m_arst_n)
    begin
        if(~m_arst_n)
            m_awvalid <= 1'b0;
        else if(cpu_we && w_state == W_IDLE)
            m_awvalid <= 1'b1;
        else if(aw_hs_en)
            m_awvalid <= 1'b0;
    end









// =================================================================
// 写数据通道
// =================================================================



    always @(posedge m_aclk or negedge m_arst_n)
    begin
        if(~m_arst_n)
        begin
            m_wdata <= {XLEN{1'b0}};
            m_wstrb <= {(XLEN/8){1'b0}};
            m_wvalid <= 1'b0;
        end
        else
        begin
            if(cpu_wdata_valid && cpu_wdata_ready)
            begin
                m_wdata <= cpu_wdata;
                m_wstrb <= cpu_wmask;
                m_wvalid <= 1'b1;
            end
            else if(w_hs_en)
            begin
                m_wvalid <= 1'b0;
            end
        end
    end



    //发送数据拍数
    always @(posedge m_aclk or negedge m_arst_n)
    begin
        if(~m_arst_n)
            wdata_cnt <= 8'h0;
        else if(w_state == W_IDLE)
            wdata_cnt <= 8'h0;
        else if(w_state == W_WRITE && w_hs_en)
            wdata_cnt <= wdata_cnt + 1'b1;
    end


    assign m_wlast = m_wvalid && (wdata_cnt == wlen_buf);




// =================================================================
// 写响应通道
// =================================================================


    always @(posedge m_aclk or negedge m_arst_n)
    begin
        if(~m_arst_n)
            m_bready <= 1'b0;
        else if(w_state == W_RESP && b_hs_en)
            m_bready <= 1'b0;
        else if(aw_done && w_done)
            m_bready <= 1'b1;
    end  

    always @(posedge m_aclk or negedge m_arst_n)
    begin
        if(~m_arst_n)
        begin
            resp <= 2'h0;
            resp_en <= 1'b0;
        end
        else if(w_state == W_RESP && b_hs_en)
        begin
            resp <= m_bresp;
            resp_en <= 1'b1;
        end
        else
            resp_en <= 1'b0;
    end



// =================================================================
// 读地址通道
// =================================================================
    always @(posedge m_aclk or negedge m_arst_n)
    begin
        if(~m_arst_n)
        begin
            m_araddr <= {XLEN{1'b0}};
            m_arlen <= 8'h0;
            m_arsize <= 3'h0;
            m_arburst <= 2'h0;
            m_arid <= 1'b0;            
        end
        else if(cpu_re && r_state == R_IDLE)
        begin
            m_araddr <= cpu_raddr;
            m_arlen <= cpu_arlen;
            m_arsize <= cpu_arsize;
            m_arburst <= cpu_arburst;
            m_arid <= cpu_rid;    
        end
    end


    always @(posedge m_aclk or negedge m_arst_n)
    begin
        if(~m_arst_n)
            m_arvalid <= 1'b0;
        else if(cpu_re && r_state == R_IDLE)
            m_arvalid <= 1'b1;
        else if(ar_hs_en)
            m_arvalid <= 1'b0;
    end

// =================================================================
// 读数据通道
// =================================================================

    always @(posedge m_aclk or negedge m_arst_n)
    begin
        if(~m_arst_n) 
            rdata_buf <= {{XLEN}{1'b0}};
        else if(r_state == R_DATA && r_hs_en)
            rdata_buf <= m_rdata;
    end



    always @(posedge m_aclk or negedge m_arst_n)
    begin
        if(~m_arst_n)    
            rdata_cnt <= 2'h0;
        else if(r_state == R_DATA && r_hs_en)  
            rdata_cnt <= rdata_cnt + 1'b1;
        else if(r_state == R_IDLE)
            rdata_cnt <= 2'h0;
    end


    always @(posedge m_aclk or negedge m_arst_n)
    begin
        if(~m_arst_n)   
            m_rready <= 1'b0;
        else if(ar_hs_en)
            m_rready <= 1'b1;
        else if(r_hs_en && m_rlast)
            m_rready <= 1'b0;
    end    


// =================================================================
// 与cpu核交互信号
// =================================================================

    always @(posedge m_aclk or negedge m_arst_n)
    begin
        if(~m_arst_n) 
            cpu_rdata_valid <= 1'b0;
        else if(r_state == R_DATA && r_hs_en)
            cpu_rdata_valid <= 1'b1;
        else 
            cpu_rdata_valid <= 1'b0;
    end
    always @(posedge m_aclk or negedge m_arst_n)
    begin
        if(~m_arst_n) 
            cpu_rid_o <= 1'b0;
        else if(r_state == R_DATA && r_hs_en)
            cpu_rid_o <= m_rid;
    end



    assign cpu_wdata_ready = (w_state == W_WRITE) && (~m_wvalid || m_wready);
    assign cpu_rdata = rdata_buf;




endmodule
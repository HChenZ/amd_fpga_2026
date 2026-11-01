`timescale 1ns / 1ps
module uart_rx(
    input                   rx_clk,
    input                   rst_n,
    input                   uart_rxd,
    input                   rx_ack,//为高时表示数据已经被cpu读走了，可以接收数据

    output reg              rx_data_valid,
    output reg     [7:0]       uart_rx_data
);  

parameter CLK_FREQ = 50000000;              
parameter UART_BPS = 115200  ;              
parameter BAUD_CNT_MAX = 434; //根据波特率和时钟频率能算出波特率计数器最大值

reg             uart_rxd_d0;
reg             uart_rxd_d1;
reg             uart_rxd_d2;
reg             rx_flag;
reg [3:0]       rx_cnt;
reg [15:0]      baud_cnt;
reg [7:0]       rx_data_t;
reg             uart_rx_done;


wire    start_en;


assign start_en = (!uart_rxd_d0)& uart_rxd_d1 & (!rx_flag);
//打两拍，以及检测下降沿
always @(posedge rx_clk or negedge rst_n) begin
    if(!rst_n) begin
        uart_rxd_d0 <= 1'd0;
        uart_rxd_d1 <= 1'd0;
        uart_rxd_d2 <= 1'd0;    
    end
    else begin 
    uart_rxd_d0 <= uart_rxd;
    uart_rxd_d1 <= uart_rxd_d0;
    uart_rxd_d2 <= uart_rxd_d1; 
    end
end

//给接收标志赋值
always @(posedge rx_clk or negedge rst_n) begin
    if(!rst_n) 
        rx_flag <= 1'b0;
    else if(start_en && !rx_ack)    //检测到起始位
        rx_flag <= 1'b1; //接收过程中，标志信号rx_flag拉高
    //在停止位一半的时候，即接收过程结束，标志信号rx_flag拉低
    else if((rx_cnt == 4'd9) && (baud_cnt == BAUD_CNT_MAX/2 - 1'b1))
        rx_flag <= 1'b0;
    else
        rx_flag <= rx_flag;
end  

//给接受计数器赋值
always @(posedge rx_clk or negedge rst_n) begin
    if(!rst_n) 
        rx_cnt <= 4'd0;
    else if(rx_flag)
        if(baud_cnt == BAUD_CNT_MAX - 1'b1)
            rx_cnt <= rx_cnt + 16'd1;
        else
            rx_cnt <= rx_cnt;
    else  rx_cnt <=  4'd0;

end 

//给波特率赋值
always @(posedge rx_clk or negedge rst_n) begin
    if(!rst_n)
        baud_cnt <= 16'd0;
    else if(rx_flag && baud_cnt < (BAUD_CNT_MAX - 1)) 
        baud_cnt <= baud_cnt + 16'd1;
    else 
        baud_cnt <= 16'd0;
end


always @(posedge rx_clk or negedge rst_n) begin
    if(!rst_n)
        rx_data_t <= 8'd0;
   else if(rx_flag) begin                           //系统处于接收过程时
            if(baud_cnt == BAUD_CNT_MAX/2 - 1'b1) begin  //判断baud_cnt是否计数到数据位的中间
                case(rx_cnt)
                    
                            4'd1 : rx_data_t[0] <= uart_rxd_d2;   //寄存数据的最低位
                            4'd2 : rx_data_t[1] <= uart_rxd_d2;
                            4'd3 : rx_data_t[2] <= uart_rxd_d2;
                            4'd4 : rx_data_t[3] <= uart_rxd_d2;
                            4'd5 : rx_data_t[4] <= uart_rxd_d2;
                            4'd6 : rx_data_t[5] <= uart_rxd_d2;
                            4'd7 : rx_data_t[6] <= uart_rxd_d2;
                            4'd8 : rx_data_t[7] <= uart_rxd_d2;   //寄存数据的高低位
                        default : ;
                endcase
            end
            else rx_data_t <= rx_data_t;
                    end
    else 
        rx_data_t <= 8'b0;       
end

//给接收完成信号和接收到的数据赋值
always @(posedge rx_clk or negedge rst_n) begin
    if(!rst_n) begin
        uart_rx_done <= 1'b0;
        uart_rx_data <= 8'b0;

    end
    //当接收数据计数器计数到停止位，且baud_cnt计数到停止位的中间时
    else if(rx_cnt == 4'd9 && baud_cnt == BAUD_CNT_MAX/2 - 1'b1) 
    begin
        uart_rx_done <= 1'b1     ;  //拉高接收完成信号
        uart_rx_data <= rx_data_t;  //并对UART接收到的数据进行赋值
    end
    else if(rx_ack && rx_data_valid)
    begin
        uart_rx_done <= 1'b0     ;  //拉高接收完成信号
        uart_rx_data <= 8'b0;  //并对UART接收到的数据进行赋值
    end
    else begin
        uart_rx_done <= 1'b0;
        uart_rx_data <= uart_rx_data;
    end
end



    
    




always @(posedge rx_clk or negedge rst_n) 
begin
    if(!rst_n) 
        rx_data_valid <= 1'b0;
    else if(uart_rx_done)
        rx_data_valid <= 1'b1;
    else if(rx_ack && rx_data_valid)
        rx_data_valid <=1'b0;
end




endmodule

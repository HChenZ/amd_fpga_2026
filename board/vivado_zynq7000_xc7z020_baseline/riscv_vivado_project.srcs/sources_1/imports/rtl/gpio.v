`timescale 1ns / 1ps

module gpio_ctrl (
    input          clk,
    input          rst_n,
    
    // ==========================================
    // 总线接口
    // ==========================================
    input          cpu_re,     // 读使能
    input          cpu_we,     // 写使能
    input   [31:0] cpu_wdata,   // CPU 写入的数据
    input          addr_sel,    // CPU 访问的地址
    output  [31:0] cpu_rdata,  // 返回给 CPU 的数据

    output reg     gpio_irq,   //中断请求

    // ==========================================
    // 物理引脚
    // ==========================================
    output reg  [1:0]  led_pins,    // 接 4 个 LED 灯
    input   [1:0]  btn_pins     // 接 4 个 按键/拨码开关
);

    // parameter DELAY_MAX = 21'd2_000_000; 
    parameter DELAY_MAX = 21'd2000000; 
    parameter PWM_DIV_MAX = 16'd255;
    parameter LED = 1'b0;   //LED灯
    parameter BTN = 1'b1;   //按键

    reg [31:0] led_control;
    reg [31:0] led_control_active;
    reg [15:0] pwm_divider;
    reg [7:0] pwm_phase;

    // ==========================================
    // 写逻辑
    // 地址约定：基址 + 0x00
    // ==========================================
    always @(posedge clk or negedge rst_n) 
    begin
        if (!rst_n)
        begin
            led_control <= 32'b0;
        end 
        else if (cpu_we) 
        begin
            // 只有访问偏移地址 0x00 时，才允许修改 LED
            if (addr_sel == LED) 
            begin
                // 因为只有 2 个灯，所以只截取最低 2 位数据
                led_control <= cpu_wdata;
            end
        end
    end

    always @(posedge clk or negedge rst_n)
    begin
        if (!rst_n)
        begin
            pwm_divider <= 16'b0;
            pwm_phase <= 8'b0;
            led_control_active <= 32'b0;
            led_pins <= 2'b00;
        end
        else
        begin
            if (pwm_divider >= PWM_DIV_MAX)
            begin
                pwm_divider <= 16'b0;
                pwm_phase <= pwm_phase + 1'b1;
                if (pwm_phase == 8'hff)
                    led_control_active <= led_control;
            end
            else
            begin
                pwm_divider <= pwm_divider + 1'b1;
            end

            if (led_control_active[16])
            begin
                if (led_control_active[15:8] == 8'h00)
                    led_pins <= 2'b00;
                else if (led_control_active[15:8] == 8'hff)
                    led_pins <= led_control_active[1:0];
                else if (pwm_phase < led_control_active[15:8])
                    led_pins <= led_control_active[1:0];
                else
                    led_pins <= 2'b00;
            end
            else
            begin
                led_pins <= led_control[1:0];
            end
        end
    end

    // ==========================================
    // 读逻辑
    // 地址约定：
    // 基址 + 0x00 -> 读 LED 当前状态
    // 基址 + 0x04 -> 读 按键 当前状态
    // ==========================================
    reg[31:0] rdata_reg;
    
    always @(posedge clk or negedge rst_n) 
    begin
        if (!rst_n) 
        begin
            rdata_reg <= 32'b0;
        end 
        else if (cpu_re) 
        begin
            case (addr_sel)
                // 读 LED 状态：高 30 位补 0，低 2 位是灯的状态
                LED: rdata_reg <= {30'b0, led_pins};    
                
                // 返回低有效按键的锁存事件，CPU 读取后自动清除。
                BTN: rdata_reg <= {30'b0, btn_latched};    
                
                // 读其他未定义地址，默认返回 0
                default: rdata_reg <= 32'b0;
            endcase
        end 
        else 
        begin
            // 没有读请求时，必须输出 0，防止总线上的 OR 门串线！
            rdata_reg <= 32'b0;
        end
    end

    // 将寄存器的值送给总线
    assign cpu_rdata = rdata_reg;



    // ==========================================
    // 按键消抖
    // ==========================================

    reg [1:0]  key_sync1;
    reg [1:0]  key_sync2;
    reg [1:0]  key_out;   

    // 两级同步器：消除异步信号的亚稳态
    always @(posedge clk or negedge rst_n) 
    begin
        if (!rst_n) 
        begin
            key_sync1 <= 2'h3;
            key_sync2 <= 2'h3;
        end 
        else 
        begin
            key_sync1 <= btn_pins;
            key_sync2 <= key_sync1;
        end
    end

    // 核心消抖逻辑
    reg [20:0] cnt0;
    reg [20:0] cnt1;
    always @(posedge clk or negedge rst_n) 
    begin
        if (!rst_n) 
        begin
            cnt0    <= 21'd0;
            cnt1    <= 21'd0;
            key_out <= 2'h3;
        end 
        else 
        begin
            // 如果同步后的输入，和当前输出状态不一样，说明电平变化了！
            if (key_sync2[0] != key_out[0] ) 
            begin
                cnt0 <= cnt0 + 1'b1; // 开始计时验证
                
                // 如果稳定保持了 20ms
                if (cnt0 >= DELAY_MAX) 
                begin
                    key_out[0]  <= key_sync2[0]; // 认可这个新状态！
                    cnt0     <= 21'd0;     // 计数器清零
                end
            end 
            // 如果期间电平又变回去了（说明是抖动毛刺），立刻清零计数器
            else 
            begin
                cnt0 <= 21'd0; 
            end


            if (key_sync2[1] != key_out[1] ) 
            begin
                cnt1 <= cnt1 + 1'b1; 
                
                if (cnt1 >= DELAY_MAX) 
                begin
                    key_out[1]  <= key_sync2[1]; 
                    cnt1     <= 21'd0;    
                end
            end 
            else 
            begin
                cnt1 <= 21'd0; 
            end
       
        end
    end    


    reg[1:0] btn_clean_d1;
    always @(posedge clk or negedge rst_n) 
    begin
        if (!rst_n)
          btn_clean_d1 <= 2'h3;
        else
          btn_clean_d1 <= key_out;
    end    

    wire [1:0] btn_pressed = ~key_out & btn_clean_d1;    


    reg[1:0] btn_latched;
    always @(posedge clk or negedge rst_n) 
    begin
        if (!rst_n) 
        begin
            btn_latched <= 2'b0;
        end 
        else 
        begin
            // CPU 读走后清零
            if (cpu_re && (addr_sel == BTN)) 
              btn_latched <= 2'h0;
            // 只要检测到干净的脉冲，就锁死为 1
            if (btn_pressed[0]) 
              btn_latched[0] <= 1'b1;
            if (btn_pressed[1]) 
              btn_latched[1] <= 1'b1;
            

        end
    end

    always @(posedge clk or negedge rst_n) 
    begin
        if (!rst_n) 
        begin
            gpio_irq <= 1'b0;
        end 
        else 
        begin
            if (btn_pressed != 2'h0) 
              gpio_irq <= 1'b1;
            else if (cpu_re && (addr_sel == BTN)) 
            begin
              gpio_irq <= 1'b0;
            end
        end
    end

endmodule

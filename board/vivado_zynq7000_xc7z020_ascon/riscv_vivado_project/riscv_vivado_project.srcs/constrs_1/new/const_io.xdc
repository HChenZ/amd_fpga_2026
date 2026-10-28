# =============================================================================
# const_io.xdc — 板级 IO 时序约束（XC7Z020 上板工程，签核变体）
# -----------------------------------------------------------------------------
# 目标：给 const.xdc 里"只有引脚、没有时序语义"的板级端口补上
#   (a) 语义正确的绑定约束（异步 → false_path），
#   (b) 数值可推导的形式 IO delay（让 check_timing 的 no_input_delay /
#       no_output_delay 归零，否则覆盖率判据过不了）。
#
# 与 const.xdc 的分工（**本文件不改动 const.xdc 的任何一行**）：
#   const.xdc    : 引脚 + IOSTANDARD + create_clock（clk = U18 50 MHz 晶振，20 ns）
#                  + set_false_path -from [get_ports reset_btn]
#   const_io.xdc : 2 个虚拟参考时钟 + set_input_delay/set_output_delay + false_path
#   → 这里不重复 create_clock 定义 clk，也不重复 reset_btn 的 false_path。
#
# =============================================================================
# 一、为什么 uart/button 必须用 false_path，而 IO delay 只是"形式覆盖"
# -----------------------------------------------------------------------------
# 本设计 5 个板级端口分成两类：
#   同步类：无。所有外部器件（CH340C 串口、机械按键、LED、复位）都与 PL 时钟
#           **没有** 相位关系。
#   异步类：全部。所以真正的时序契约不是"在某个时钟边沿前多少 ns 稳定"，而是
#           由 RTL 侧的结构保证：
#             · uart_rxd ：src/rtl/uart_rx.v:31-42 两级同步器 + 第 74/85 行
#                          波特计数到 BAUD_CNT_MAX/2 采样 → 比特中点采样，
#                          容差 ±T_bit/2 = ±4340.278 ns。
#             · button   ：src/rtl/gpio.v:146-160 两级同步器 + 163 行起 21 位消抖
#                          （2^21/100 MHz ≈ 21 ms）。
#             · reset_btn：const.xdc 已有 false_path；top_pl_bram.v:36-43 是
#                          "异步置位、同步释放"（rst_sync 三级），断言/释放都不该
#                          过同步时序检查。
#             · led      ：静态指示灯，人眼阈值 ~10 ms，无任何要求。
#
# 本轮把"用 IO delay 强行当同步接口约束"这件事做了四次实验，全部记录在
# docs/io_timing_signoff.md §4，结论是：**在这块板上，IO delay 的数值上限被
# 采样时钟周期（10 ns）锁死，而不是被 UART 位周期（8680 ns）锁死**。原因是
# Vivado 对"虚拟/无关时钟 → clk_100m"的边沿配对取的是**最小正 requirement**：
#
#   变体 A 参考端口 clk(20 ns)：requirement = 10 − 20 − tsu ≈ −10 ns
#                                → uart_rxd slack −14.490 ns（硬失败）
#   变体 B 参考 8680.556 ns 虚拟时钟：8680.556 mod 10 = 0.556 →
#                                最坏边沿对 requirement = 0.556 ns
#                                → uart_txd slack −27.105 ns（更糟）
#   变体 D 参考 8680.000 ns（与 10 ns 网格对齐）：边沿重合 → Vivado 取下一个
#                                捕获沿 → requirement = 10.000 ns
#                                → uart_rxd slack −17.067 ns（仍然失败）
#   变体 E 用 io_slow=10 µs 覆盖 LED（同样是"大 period 虚拟时钟 + 20 ns 预算"）：
#                                requirement 照样塌到 10 ns 量级
#                                → led[1] setup −13.888 / hold −18.452 ns
#   ⇒ 只要 input/output delay 的数值 > 捕获时钟周期（本设计 10 ns），**任何**参考
#     时钟都救不了：Vivado 的 requirement 取"最小正边沿对"，虚拟时钟的周期再大，
#     最近的两个捕获沿也只差一个 clk_100m 周期。
#     要把 UART 的 4340 ns 容差表达出来，就必须用**与边沿无关**的约束
#     （false_path / set_max_delay -datapath_only）。
#
# 所以本文件的最终形态是（5 个端口一律如此）：
#   false_path  → 承载真实语义（异步，不做同步时序判定）
#   IO delay    → 承载"外部链路预算 ≤ 20 ns"的建模数值 + 闭合 check_timing 覆盖
#                 （实测：Vivado 的 no_input_delay / no_output_delay 不因 false_path
#                  而豁免该端口，只加 false_path 时 no_input_delay=4、no_output_delay=3；
#                  两者同时存在才既计数 0 又 0 违反）
# 该组合在已布线 checkpoint 上的实测：no_input_delay=0、no_output_delay=0，
#   且 uart/button/led/reset 的路径全部退出同步检查（untimed）。
#   证据：build/local/io_sta_20261027/sem3.log、ist2.log
#
# =============================================================================
# 二、证据边界（最重要的一段，请连同 docs/io_timing_signoff.md 一起看）
# -----------------------------------------------------------------------------
#   * 下面所有 ns 数值都是 **modeled assumption（建模假定）**：来源是板卡原理图
#     的器件链路 + 叠层估算 + UART 帧格式 + 器件手册，**不是示波器/眼图实测**。
#     底板走线长度表缺失（核心板有 核心板信号走线长度.csv，底板没有）→ 只能估算。
#     全文标 not_measured。
#   * 本文件能证明：形式覆盖闭合（IO 侧 0 未约束）、IO 侧不成为关键路径、
#     false_path 与 RTL 的异步处理一致。
#     本文件**不能**证明：板级真实建立/保持余量、CH340C 的实际输出相位、
#     115200 下的误码率。板级延迟实测 = not_measured。
#   * 端口/引脚（来自 const.xdc，此处只引用不改）：
#       uart_rxd=T19 / uart_txd=J15 / button[0]=L14 button[1]=K16 /
#       led[0]=H15 led[1]=L15 / reset_btn=N16 / clk=U18
#   * 链路（底板原理图 V3.9）：CH340C ─ P5 跳线 ─ 74LVC1G125(U11/U12) ─ PL 引脚
#   * 时钟（Vivado 探针实测 2026-10-27）：clk=20 ns（端口晶振）、
#     clk_out1_clk_wiz_0=10 ns（MMCM 输出，全部 IO 触发器的实际时钟）、
#     clkfbout_clk_wiz_0=20 ns。
#
# 位周期算术：
#   T_bit = 1/115200 = 8680.5556 ns；T_bit/2 = 4340.2778 ns
#   T_bit/20 ns = 434 倍；T_bit/10 ns = 868 倍（约三个数量级）
#   CLK_FREQ 依据：src/rtl/top.v:9 UART_CLK_FREQ=100000000，top_pl_bram.v:102-106
#   不覆盖该参数 → 波特计数上限 = 100e6/115200 = 868。
# =============================================================================


# -----------------------------------------------------------------------------
# 0) 虚拟参考时钟（无源端口：只给 STA 一个"外部器件时钟"的框架，不改 RTL）
# -----------------------------------------------------------------------------
# uart_bit：UART 一位的时间，对应"外部器件按 115200 Bd 逐位收发"。
#   取值 8680.000（真实位周期 1/115200 = 8680.5556 ns，差 0.556 ns = 0.006%），
#   取整到 8680 ns 是因为 8680 是 10 ns 的整数倍（= 868 × 10 ns），这样它与
#   clk_100m 的边沿网格可公度——否则 Vivado 会报
#   TIMING-8 Critical Warning "No common period between related clocks"
#   （本轮用真实位周期 8680.556 时实测确有此 warning）。
#   0.556 ns 的偏差对"一位 8.68 µs"的参考框架没有意义；
#   而且 uart 路径本身是 false_path，这个 period 只决定 STA 的参考框架。
create_clock -name uart_bit -period 8680.000
# io_slow：LED / 复位这类无要求端口用的参考时钟，取 10 µs
#   （= 1000 × 10 ns，同样为可公度取值；用 1 ms 实测会触发 TIMING-8）。
#   数值本身没有物理意义（这些端口真的没有要求），目的只是让 requirement ≈ 10 µs，
#   任何内部路径都不可能被它压到，同时形式覆盖能闭合。
create_clock -name io_slow -period 10000.000


# -----------------------------------------------------------------------------
# 1) UART 接收：uart_rxd（T19）
# -----------------------------------------------------------------------------
# 语义（绑定）：异步输入 → false_path。
#   端口到第一级触发器 uart_rxd_d0.D 之间只有 IBUF，无组合逻辑；正确性由
#   两级同步器 + 比特中点采样保证（见文件头 §一）。
set_false_path -from [get_ports uart_rxd]
#
# 形式数值（modeled, not measured）——外部链路预算：
#     CH340C TxD 输出/边沿            ≤ 10.000 ns   假定：CH340C 手册无 Tco 指标
#   + 74LVC1G125 缓冲器 tpd          ≤  4.500 ns   手册：Nexperia 74LVC1G125
#                                                  Rev.17.1(2024-09-03) Table 8，
#                                                  VCC=3.0~3.6 V / -40~85 °C max 4.5 ns
#                                                  （-40~125 °C max 6 ns）
#   + 底板走线 ≤ 30 cm × 6.7 ps/mm   ≈  2.010 ns   估算：FR4 εr≈4.2 → ~6.7 ps/mm
#   + 22R/33R 串阻（边沿变缓，不计为延迟） + 余量
#   ---------------------------------------------------------------
#   = 16.510 ns → 取整上界 20.000 ns
set_input_delay -clock uart_bit -max 20.000 [get_ports uart_rxd]
set_input_delay -clock uart_bit -min  0.000 [get_ports uart_rxd]


# -----------------------------------------------------------------------------
# 2) UART 发送：uart_txd（J15）
# -----------------------------------------------------------------------------
# 语义（绑定）：异步输出 → false_path。
#   接收侧（CH340C RXD）按自己的波特率在比特中点采样，对 PL 输出的建立/保持
#   要求被放宽到 ±T_bit/2 ≈ ±4340.278 ns；PL 侧的 ±20 ns 外部预算比它严格 200 倍。
set_false_path -to [get_ports uart_txd]
#
# 形式数值（modeled）：与输入侧共用同一套"外部链路 ≤ 20 ns"预算（同一段 PCB +
#   同一个缓冲器），这样表里的数字能互相印证，而不是每条各编一个数。
set_output_delay -clock uart_bit -max  20.000 [get_ports uart_txd]
set_output_delay -clock uart_bit -min -20.000 [get_ports uart_txd]


# -----------------------------------------------------------------------------
# 3) LED 指示：led[0]（H15）/ led[1]（L15）
# -----------------------------------------------------------------------------
# RTL 事实：led 是 gpio_ctrl 寄存器在 clk_100m 上直接驱动的输出，只是指示灯，
#   没有外部器件对它的时序要求（人眼阈值 ~10 ms，比任何时钟周期宽 6 个数量级）。
#
# ⚠ 实测教训（本轮踩到，别再用"大 period 虚拟时钟 + 20 ns 外部预算"来覆盖 LED）：
#   用 io_slow=10 µs 作参考、set_output_delay -max 20 / -min -20 时，实测
#     led[1] setup slack = **-13.888 ns**、hold slack = **-18.452 ns**（led[0] 同量级）
#   原因同 §一：requirement 取的是"最小正边沿对"。io_slow 与 clk_100m 可公度，
#   最近的两个捕获沿只差 10 ns，于是 requirement ≈ 10 − 20 − tsu 仍为负，
#   再加上输出路径的 MMCM 插入延迟差，就成了 −13.9 / −18.5。
#   → 结论：只要 delay 数值 > 捕获时钟周期（10 ns），任何参考时钟都会失败。
#   证据：build/local/io_sta_20261027/ist.log / ist_setup.rpt / ist_hold.rpt
#         （top_pl_bram_physopt.dcp 上的 report_timing）
#
# 所以 LED 与 UART/按键一样，用 false_path 承载语义，delay 只做形式覆盖：
set_false_path -to [get_ports {led[0] led[1]}]
# 形式数值（modeled）：与前两类共用同一套 ±20 ns 预算，仅用于 no_output_delay 归零。
# **不要**理解成"LED 需要 20 ns 建立/保持"——它没有任何要求。
set_output_delay -clock io_slow -max  20.000 [get_ports {led[0] led[1]}]
set_output_delay -clock io_slow -min -20.000 [get_ports {led[0] led[1]}]


# -----------------------------------------------------------------------------
# 4) 按键：button[0]（L14）/ button[1]（K16）—— 异步，false_path 为绑定语义
# -----------------------------------------------------------------------------
# RTL：src/rtl/gpio.v:146-160 两级同步器；163 行起 21 位消抖（≈21 ms）。
set_false_path -from [get_ports {button[0] button[1]}]
# 形式数值（只为让 no_input_delay 归零，不承载物理含义）：
set_input_delay -clock uart_bit -max 20.000 [get_ports {button[0] button[1]}]
set_input_delay -clock uart_bit -min  0.000 [get_ports {button[0] button[1]}]


# -----------------------------------------------------------------------------
# 5) 复位：reset_btn（N16）—— const.xdc 的 false_path 保留，此处只补形式覆盖
# -----------------------------------------------------------------------------
# const.xdc 第 18 行已有：set_false_path -from [get_ports reset_btn]
# 不在此重复声明 false_path（重复例外会在同一端口叠加两条同义路径）。
# 保留理由：异步置位 / 同步释放（top_pl_bram.v:36-43 的 rst_sync 三级），
#   上电瞬间电平不受任何时钟约束，编"同步"要求的 input delay 无物理意义。
set_input_delay -clock io_slow -max 20.000 [get_ports reset_btn]
set_input_delay -clock io_slow -min  0.000 [get_ports reset_btn]


# -----------------------------------------------------------------------------
# 6) 本轮**不**加的约束（避免过度声明，写清楚为什么不加）
# -----------------------------------------------------------------------------
#   * 不给 clk 加 create_generated_clock：clk_100m 由 MMCM 自动派生。
#   * 不加 set_clock_groups -asynchronous 切 clk 与 clk_100m：二者同源，
#     切开只会丢掉真实的 MMCM 相位关系（本设计内部只有一个时钟域）。
#   * 不给 M_AXI_* 加 IO delay：AXI 口在 PL 内部直连 axi_bram_ctrl_0
#     （top_pl_bram.v:161-212），不是板级引脚。
#   * 不给 uart 用 set_input_delay 单独承担语义：见文件头 §一 的变体 A/B/D 实测。
# =============================================================================
# 7) 备选写法（注释掉，不启用）
# -----------------------------------------------------------------------------
# (a) 用与边沿无关的路径约束替代 false_path（想给异步路径一个"组合跨度上限"时）：
#       set_max_delay -datapath_only 4340.278 -from [get_ports uart_rxd]
#       set_max_delay -datapath_only 4340.278 -to   [get_ports uart_txd]
#     （build/local/iodelay/const_io_delay_draft.xdc 是这一路线的早期草案）
#
# (b) 若将来某个外设变成**同步**接口（LCD / DVP 摄像头 / RGMII / HDMI），
#     那时 IO delay 才有真实意义，模板：
#       create_clock -period 10.000 -name cam_pclk [get_ports cam_pclk]
#       set_input_delay  -clock cam_pclk -max [expr $tco_max + $pcb_max] [get_ports {cam_data[*]}]
#       set_input_delay  -clock cam_pclk -min [expr $tco_min + $pcb_min] [get_ports {cam_data[*]}]
#       set_output_delay -clock lcd_clk  -max [expr $tsu + $pcb_max]  [get_ports {lcd_data[*]}]
#       set_output_delay -clock lcd_clk  -min [expr -$th + $pcb_min]  [get_ports {lcd_data[*]}]
#     数值来源必须齐三样：器件手册 Tco/Tsu/Th + PCB 走线长度/叠层 + 串阻/缓冲器延迟；
#     底板没有走线长度表 → 只能用叠层估算并标 estimate。
# =============================================================================

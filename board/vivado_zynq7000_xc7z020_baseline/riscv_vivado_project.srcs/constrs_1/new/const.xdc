
# 引脚约束
set_property -dict {PACKAGE_PIN U18 IOSTANDARD LVCMOS33} [get_ports clk]
#-------------------UART----------------#
set_property -dict {PACKAGE_PIN T19 IOSTANDARD LVCMOS33} [get_ports uart_rxd]
set_property -dict {PACKAGE_PIN J15 IOSTANDARD LVCMOS33} [get_ports uart_txd]

#-------------------按键----------------#
set_property -dict {PACKAGE_PIN L14 IOSTANDARD LVCMOS33} [get_ports {button[0]}]
set_property -dict {PACKAGE_PIN K16 IOSTANDARD LVCMOS33} [get_ports {button[1]}]

#-------------------LED灯----------------#
set_property -dict {PACKAGE_PIN H15 IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN L15 IOSTANDARD LVCMOS33} [get_ports {led[1]}]

set_property -dict {PACKAGE_PIN N16 IOSTANDARD LVCMOS33} [get_ports reset_btn]

set_false_path -from [get_ports reset_btn]

## 主时钟：50MHz
create_clock -period 20.000 -name clk [get_ports clk]




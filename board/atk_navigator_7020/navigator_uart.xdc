# Minimal candidate for existing top_pl_bram, NOT attached to either baseline.
# Source: vendor NAVIGATOR_ZYNQ_IO.xdc; core 2V5 p3; base V3.9 p5/p6.
# External PL clock 50 MHz; existing PLL supplies internal 100 MHz separately.
# USB UART through P5 PL selection (3-5 and 4-6). No RS232/RS485 pins.
# Physical board revision/speed grade and board IO timing remain unverified.
create_clock -period 20.000 -name navigator_clk_50m [get_ports clk]
set_property -dict {PACKAGE_PIN U18 IOSTANDARD LVCMOS33} [get_ports clk]
set_property -dict {PACKAGE_PIN N16 IOSTANDARD LVCMOS33} [get_ports reset_btn]
set_property -dict {PACKAGE_PIN L14 IOSTANDARD LVCMOS33} [get_ports {button[0]}]
set_property -dict {PACKAGE_PIN K16 IOSTANDARD LVCMOS33} [get_ports {button[1]}]
set_property -dict {PACKAGE_PIN H15 IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN L15 IOSTANDARD LVCMOS33} [get_ports {led[1]}]
set_property -dict {PACKAGE_PIN T19 IOSTANDARD LVCMOS33} [get_ports uart_rxd]
set_property -dict {PACKAGE_PIN J15 IOSTANDARD LVCMOS33} [get_ports uart_txd]

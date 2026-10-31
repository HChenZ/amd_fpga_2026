# Independent genuine frequency variant after the fixed-port 100MHz timing FAIL.
# Call in the same authorized session after closing the 100MHz project.
set root [file normalize [file join [file dirname [info script]] ../..]]
set ::cpu_dma_work $root/build/local/dma_cpu/fclk80
set ::cpu_dma_mhz 80
set ::cpu_dma_resume 0
source -notrace $root/board/vivado_zynq7000_xc7z020_pynq_dma_cpu/setup.tcl

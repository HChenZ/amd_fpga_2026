# Layout probe: device clock-region geometry + current per-module placement bbox.
#   vivado -mode batch -source build/backend_opt_20261021/probe_layout.tcl -notrace
set root   [file normalize [file join [file dirname [info script]] .. ..]]
set outdir [file join $root build local backend_opt_20261021 recon]
file mkdir $outdir
set ref [file join $root build local timing_acb_impl riscv_vivado_project.runs acb_remap top_pl_bram_postroute_physopt.dcp]
open_checkpoint $ref

# ---- device geometry per clock region (from the real device of this part)
set fp [open [file join $outdir clock_regions.csv] w]
puts $fp "cr,slices,slicems,minx,maxx,miny,maxy"
foreach cr [lsort [get_clock_regions]] {
    set in [get_sites -quiet -of_objects $cr -filter {SITE_TYPE == "SLICEL" || SITE_TYPE == "SLICEM"}]
    if {[llength $in] == 0} { continue }
    set xs {} ; set ys {} ; set nsm 0
    foreach s $in {
        if {[regexp {SLICE_X(\d+)Y(\d+)} [get_property NAME $s] -> x y]} { lappend xs $x ; lappend ys $y }
        if {[get_property SITE_TYPE $s] eq "SLICEM"} { incr nsm }
    }
    puts $fp "[get_property NAME $cr],[llength $in],$nsm,[lindex [lsort -integer $xs] 0],[lindex [lsort -integer $xs] end],[lindex [lsort -integer $ys] 0],[lindex [lsort -integer $ys] end]"
}
close $fp

# ---- current placement bbox per module (only placed leaf cells)
set mods {
    u_soc_axi_top/u_soc_top/u_cpu_core
    u_soc_axi_top/u_soc_top/u_cpu_core/u_if_stage
    u_soc_axi_top/u_soc_top/u_cpu_core/u_icache
    u_soc_axi_top/u_soc_top/u_cpu_core/u_if_id
    u_soc_axi_top/u_soc_top/u_cpu_core/id_ex_u
    u_soc_axi_top/u_soc_top/u_cpu_core/u_ex_stage
    u_soc_axi_top/u_soc_top/u_cpu_core/u_ex_stage/u_multiplier
    u_soc_axi_top/u_soc_top/u_cpu_core/u_ex_stage/u_divider
    u_soc_axi_top/u_soc_top/u_cpu_core/u_ex_stage/u_ascon_ise
    u_soc_axi_top/u_soc_top/u_cpu_core/u_csr_file
    u_soc_axi_top/u_soc_top/u_cpu_core/u_dcache
    u_soc_axi_top/u_soc_top/u_cpu_core/u_ex_mem
    u_soc_axi_top/u_soc_top/u_cpu_core/u_mem_wb
    u_soc_axi_top/u_soc_top/u_cpu_core/u_predictor
    u_soc_axi_top/u_soc_top/u_ascon_mmio
    u_soc_axi_top/u_soc_top/u_ascon_mmio/u_ascon_core
    u_soc_axi_top/u_soc_top/u_bus_interconnect
    u_soc_axi_top/u_soc_top/u_uart_ctrl
    u_soc_axi_top/u_soc_top/u_gpio_ctrl
    u_soc_axi_top/u_soc_top/u_cpi_cnt
    u_soc_axi_top/u_soc_top/u_clint
    u_soc_axi_top/u_soc_top/u_cpu_axi_bridge
    u_soc_axi_top/u_soc_top/u_axi_master
    u_soc_axi_top/u_soc_top/u_axi_bram_ctrl_0
}
set fp [open [file join $outdir module_bbox.csv] w]
puts $fp "module,cells,placed,minx,maxx,miny,maxy"
foreach m $mods {
    set cells [get_cells -quiet -hier -filter "NAME =~ \"$m/*\""]
    if {[llength $cells] == 0} { puts $fp "$m,0,0,,,,," ; continue }
    set xs {} ; set ys {} ; set n 0
    foreach c $cells {
        incr n
        set st [get_property -quiet SITE $c]
        if {[regexp {SLICE_X(\d+)Y(\d+)} $st -> x y]} { lappend xs $x ; lappend ys $y }
    }
    if {[llength $xs] == 0} { puts $fp "$m,$n,0,,,,," ; continue }
    set sx [lsort -integer $xs] ; set sy [lsort -integer $ys]
    puts $fp "$m,$n,[llength $xs],[lindex $sx 0],[lindex $sx end],[lindex $sy 0],[lindex $sy end]"
}
close $fp
puts "LAYOUT PROBE DONE"

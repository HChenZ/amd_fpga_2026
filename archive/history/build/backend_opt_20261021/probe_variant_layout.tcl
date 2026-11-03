# Per-module placement bbox of a routed variant checkpoint (evidence for the
# floorplan question: are the pipeline stages actually adjacent?).
#   vivado -mode batch -source build/backend_opt_20261021/probe_variant_layout.tcl \
#          -notrace -tclargs <variant>
set root    [file normalize [file join [file dirname [info script]] .. ..]]
set variant [lindex $argv 0]
if {$variant eq ""} { error "usage: -tclargs <variant>" }
set dcp [file join $root build local backend_opt_20261021 $variant ${variant}_routed.dcp]
if {![file exists $dcp]} { error "missing $dcp" }
set outdir [file join $root build reports backend_opt_20261021 $variant]
open_checkpoint $dcp

set mods {
    u_soc_axi_top/u_soc_top/u_cpu_core
    u_soc_axi_top/u_soc_top/u_cpu_core/u_if_stage
    u_soc_axi_top/u_soc_top/u_cpu_core/u_icache
    u_soc_axi_top/u_soc_top/u_cpu_core/u_if_id
    u_soc_axi_top/u_soc_top/u_cpu_core/id_ex_u
    u_soc_axi_top/u_soc_top/u_cpu_core/u_ex_stage
    u_soc_axi_top/u_soc_top/u_cpu_core/u_ex_stage/u_ascon_ise
    u_soc_axi_top/u_soc_top/u_cpu_core/u_csr_file
    u_soc_axi_top/u_soc_top/u_cpu_core/u_dcache
    u_soc_axi_top/u_soc_top/u_cpu_core/u_ex_mem
    u_soc_axi_top/u_soc_top/u_cpu_core/u_mem_wb
    u_soc_axi_top/u_soc_top/u_cpu_core/u_predictor
    u_soc_axi_top/u_soc_top/u_ascon_mmio
    u_soc_axi_top/u_soc_top/u_bus_interconnect
}
set fp [open [file join $outdir module_bbox.csv] w]
puts $fp "module,cells,placed,minx,maxx,miny,maxy,spanx,spany"
foreach m $mods {
    set cells [get_cells -quiet -hier -filter "NAME =~ \"$m/*\""]
    if {[llength $cells] == 0} { puts $fp "$m,0,0,,,,,," ; continue }
    set xs {} ; set ys {}
    foreach c $cells {
        if {[regexp {SLICE_X(\d+)Y(\d+)} [get_property -quiet SITE $c] -> x y]} { lappend xs $x ; lappend ys $y }
    }
    if {[llength $xs] == 0} { puts $fp "$m,[llength $cells],0,,,,,," ; continue }
    set sx [lsort -integer $xs] ; set sy [lsort -integer $ys]
    set lo [lindex $sx 0] ; set hi [lindex $sx end]
    set ly [lindex $sy 0] ; set hy [lindex $sy end]
    puts $fp "$m,[llength $cells],[llength $xs],$lo,$hi,$ly,$hy,[expr {$hi-$lo}],[expr {$hy-$ly}]"
}
close $fp

# worst path with its full pin sequence, so hop-by-hop distance can be read
set p [get_timing_paths -max_paths 1 -nworst 1 -setup]
puts "VARIANTLAYOUT $variant wns=[format %.3f [get_property SLACK $p]] start=[get_property STARTPOINT_PIN $p] end=[get_property ENDPOINT_PIN $p]"
report_timing -max_paths 1 -nworst 1 -delay_type max -input_pins -file [file join $outdir worst_path_full.rpt]
close_project
puts "VARIANTLAYOUT $variant DONE"

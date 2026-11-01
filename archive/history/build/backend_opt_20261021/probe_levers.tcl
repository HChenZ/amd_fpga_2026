# Backend lever probe (read-only): what the control cone looks like, and which
# place/opt options Vivado 2025.2 actually exposes on this part.
#
#   vivado -mode batch -source build/backend_opt_20261021/probe_levers.tcl -notrace
#
# Opens the accepted routed reference (+0.007 ns, Performance_ExploreWithRemap),
# never writes into the project. Outputs under build/local/backend_opt_20261021/recon/.

set root   [file normalize [file join [file dirname [info script]] .. ..]]
set outdir [file join $root build local backend_opt_20261021 recon]
file mkdir $outdir

set ref [file join $root build local timing_acb_impl riscv_vivado_project.runs acb_remap top_pl_bram_postroute_physopt.dcp]
if {![file exists $ref]} { error "missing reference routed checkpoint $ref" }
if {![string match "2025.2*" [version -short]]} { error "Requires Vivado 2025.2" }

puts "PROBE tool=[version -short] ref=$ref"
open_checkpoint $ref

# ---------------------------------------------------------------- 0) sanity
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
set whs [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]]
puts "PROBE ref_wns=[format %.3f $wns] ref_whs=[format %.3f $whs]"

# ---------------------------------------------------------------- 1) options
set fp [open [file join $outdir help_options.txt] w]
foreach cmd {opt_design place_design phys_opt_design route_design} {
    puts $fp "===== help $cmd ====="
    catch {puts $fp [help $cmd]} err
    catch {puts $fp [help -verbose $cmd]} err
}
close $fp

# ---------------------------------------------------------------- 2) geometry
set sl [get_sites -filter {SITE_TYPE == "SLICEL" || SITE_TYPE == "SLICEM"}]
set fp [open [file join $outdir geometry.txt] w]
puts $fp "slices=[llength $sl]"
set crs [get_clock_regions]
puts $fp "clock_regions=[llength $crs]"
foreach r $crs { puts $fp "cr [get_property NAME $r]" }
if {[llength [get_sites -quiet -filter {SITE_TYPE == "DSP48E1"}]] > 0} {
    set dsps [get_sites -filter {SITE_TYPE == "DSP48E1"}]
    puts $fp "dsp=[llength $dsps] first=[lindex $dsps 0] last=[lindex $dsps end]"
}
set brams [get_sites -filter {SITE_TYPE =~ "RAMB*"}]
puts $fp "bram=[llength $brams] first=[lindex $brams 0] last=[lindex $brams end]"
close $fp

# ---------------------------------------------------------------- 3) hierarchy
report_utilization -hierarchical -hierarchical_depth 3 -file [file join $outdir util_hier.rpt]

# cell count / bbox per candidate module (paths below are matched by name)
set mods {
    u_soc_axi_top/u_soc_top/u_cpu_core
    u_soc_axi_top/u_soc_top/u_cpu_core/u_if_stage
    u_soc_axi_top/u_soc_top/u_cpu_core/u_icache
    u_soc_axi_top/u_soc_top/u_cpu_core/u_if_id
    u_soc_axi_top/u_soc_top/u_cpu_core/id_ex_u
    u_soc_axi_top/u_soc_top/u_cpu_core/u_ex_stage
    u_soc_axi_top/u_soc_top/u_cpu_core/u_csr_file
    u_soc_axi_top/u_soc_top/u_cpu_core/u_dcache
    u_soc_axi_top/u_soc_top/u_cpu_core/u_ex_mem
    u_soc_axi_top/u_soc_top/u_cpu_core/u_mem_wb
    u_soc_axi_top/u_soc_top/u_cpu_core/u_regfile
    u_soc_axi_top/u_soc_top/u_cpu_core/u_branch_predictor
    u_soc_axi_top/u_soc_top/u_cpu_core/u_mult
    u_soc_axi_top/u_soc_top/u_cpu_core/u_divider
    u_soc_axi_top/u_soc_top/u_ascon_mmio
    u_soc_axi_top/u_soc_top/u_ascon_ise
}
set fp [open [file join $outdir modules.csv] w]
puts $fp "module,cells,luts,ffs,brams,dsps"
foreach m $mods {
    set cells [get_cells -quiet -hier -filter "NAME =~ \"$m/*\""]
    if {[llength $cells] == 0} { puts $fp "$m,0,0,0,0,0" ; continue }
    set nl [llength [get_cells -quiet $cells -filter {PRIMITIVE_GROUP == "LUT"}]] 
    set nf [llength [get_cells -quiet $cells -filter {IS_SEQUENTIAL}]]
    set nb [llength [get_cells -quiet $cells -filter {PRIMITIVE_GROUP =~ "BLOCKRAM*"}]]
    set nd [llength [get_cells -quiet $cells -filter {PRIMITIVE_GROUP == "DSP"}]]
    puts $fp "$m,[llength $cells],$nl,$nf,$nb,$nd"
}
close $fp

# ---------------------------------------------------------------- 4) fanout
report_high_fanout_nets -fanout_greater_than 64 -max_nets 400 -load_types -timing \
    -file [file join $outdir high_fanout.rpt]

# sequential-cell fanout histogram (drives MAX_FANOUT choice).
# Fast path: net-level FLAT_PIN_COUNT filter, then map to its driver cell.
set fp [open [file join $outdir seq_fanout.csv] w]
puts $fp "net,pins,driver_cell"
set big [get_nets -quiet -hier -filter {FLAT_PIN_COUNT >= 128}]
if {[llength $big] == 0} {
    puts $fp "#FLAT_PIN_COUNT filter unavailable"
    set big [get_nets -quiet -hier -filter {PIN_COUNT >= 128}]
}
foreach n $big {
    set d [get_pins -quiet -leaf -of_objects $n -filter {DIRECTION == "OUT"}]
    set cell ""
    if {[llength $d] == 1} { set cell [get_property REF_NAME $d] ; set cell "[get_property NAME $d]" }
    puts $fp "$n,[get_property FLAT_PIN_COUNT $n],$cell"
}
close $fp
puts "PROBE high-fanout nets(>=128 pins): [llength $big]"

# ---------------------------------------------------------------- 5) path pairs
set fp [open [file join $outdir paths_lt2p0.csv] w]
puts $fp "slack,start_pin,end_pin"
set paths [get_timing_paths -quiet -max_paths 400000 -nworst 1 -setup -slack_less_than 2.0]
foreach p $paths {
    puts $fp "[get_property SLACK $p],[get_property STARTPOINT_PIN $p],[get_property ENDPOINT_PIN $p]"
}
close $fp
puts "PROBE paths_lt2p0=[llength $paths]"

# ---------------------------------------------------------------- 6) control-cone nets
# exact fanout of the nets that show up as CE / flush / stall in the failing paths
set fp [open [file join $outdir control_net_fanout.txt] w]
foreach pat {*flush* *stall* *cancel* *hit* *sel_ex_mem* *valid_way* *lru*} {
    foreach n [get_nets -quiet -hier -filter "NAME =~ \"$pat\""] {
        set f [llength [get_pins -quiet -of_objects $n]]
        if {$f >= 32} { puts $fp "$f $n" }
    }
}
close $fp

close_design
puts "PROBE DONE"

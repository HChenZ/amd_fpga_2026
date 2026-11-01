# Probe module placement spread (bbox) from the routed snapshot. Read-only.
set root [file normalize [file join [file dirname [info script]] ..]]
set dcp [file join $root build local timing_acb_impl riscv_vivado_project.runs acb_remap top_pl_bram_routed.dcp]
open_checkpoint $dcp

proc bbox {filterexpr label} {
    set minx 9999
    set maxx -1
    set miny 9999
    set maxy -1
    set n 0
    foreach c [get_cells -quiet -hier -filter $filterexpr] {
        set s [get_sites -quiet -of_objects $c]
        if {$s eq ""} { continue }
        if {[regexp {SLICE_X([0-9]+)Y([0-9]+)} [get_property NAME $s] m x y]} {
            if {$x < $minx} {set minx $x}
            if {$x > $maxx} {set maxx $x}
            if {$y < $miny} {set miny $y}
            if {$y > $maxy} {set maxy $y}
            incr n
        }
    }
    if {$n > 0} {
        puts "BBOX $label cells=$n X=$minx..$maxx span=[expr {$maxx-$minx+1}] Y=$miny..$maxy span=[expr {$maxy-$miny+1}]"
    } else {
        puts "BBOX $label cells=0"
    }
}
bbox {NAME =~ "u_soc_axi_top/u_soc_top/u_cpu_core/*"} cpu_core_all
bbox {NAME =~ "*/u_if_stage/*"} if_stage
bbox {NAME =~ "*/u_icache/*"} icache
bbox {NAME =~ "*/u_id_stage/*"} id_stage
bbox {NAME =~ "*/u_ex_stage/*"} ex_stage
bbox {NAME =~ "*/u_ex_stage/u_ascon_ise/*"} ascon_ise
bbox {NAME =~ "*/u_dcache/*"} dcache
bbox {NAME =~ "*/u_csr_file/*"} csr_file
bbox {NAME =~ "*/u_regfile*/*"} regfile
bbox {NAME =~ "*/u_axi_interconnect*/*"} interconnect
puts "PROBE2 DONE"

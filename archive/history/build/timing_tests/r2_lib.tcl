# R2 replication arms -- shared helpers.
# ASCII ONLY: Vivado sources TCL.PRE/TCL.POST step files with the platform
# encoding; a non-UTF8 comment can break the enclosing braced string.
#
# Root cause this wave is chasing (see docs/timing_route_replication_r2.md):
# the R1 arm passed 12 net objects that are only 4 real nets (12 = 4 nets x 3
# hierarchical aliases). Vivado collapsed the aliases ("Using parent net ... of
# the net ...") and then phys_opt_design reported:
#     Phase 2 Fanout Optimization
#     Pass 1. Identified 12 candidate nets for fanout optimization.
#     Optimized 0 net. Created 0 new instance.
# i.e. candidates were accepted, replication was refused by the cost model, no
# replica cell was created (replica_cells stayed 51).

set ::R2_SEL_PREFIX "u_soc_axi_top/u_soc_top/u_cpu_core"

# The four sel_* nets of the current worst path, by PARENT name.
set ::R2_SEL4 [list \
  "$::R2_SEL_PREFIX/id_ex_u/sel_ex_mem_rs1_o" \
  "$::R2_SEL_PREFIX/id_ex_u/sel_ex_mem_rs2_o" \
  "$::R2_SEL_PREFIX/id_ex_u/sel_mem_wb_rs1_o" \
  "$::R2_SEL_PREFIX/id_ex_u/sel_mem_wb_rs2_o" ]

# Exact-name lookup: net names contain [ ] which get treated as a character
# class when passed as a pattern, so always match through -filter {NAME == ...}.
proc r2_net {name} {
    set n [get_nets -quiet -hier -filter "NAME == \"$name\""]
    if {[llength $n] != 1} {
        puts "R2 WARN net lookup failed ($name) -> [llength $n] objects"
        return ""
    }
    return $n
}

proc r2_drv_cell {n} {
    set drv [get_pins -quiet -leaf -of_objects $n -filter {DIRECTION == "OUT"}]
    if {[llength $drv] != 1} { return "" }
    return [get_cells -quiet -of_objects $drv]
}

proc r2_dump {phase n} {
    set dc [r2_drv_cell $n]
    puts [format "R2 %-6s fo=%-4d loc=%-12s drv=%s net=%s" $phase \
        [get_property FLAT_PIN_COUNT $n] \
        [expr {$dc ne "" ? [get_property LOC $dc] : "?"}] \
        [expr {$dc ne "" ? [get_property NAME $dc] : "?"}] \
        [get_property NAME $n]]
}

# Freeze the driver against later equivalent-register folding, otherwise the
# replicas get merged back by opt/phys_opt (recorded in the campaign notes).
proc r2_freeze {n} {
    set dc [r2_drv_cell $n]
    foreach c $dc { catch { set_property EQUIVALENT_REGISTER_REMOVAL NO $c } }
}

proc r2_reps {} {
    return [get_cells -hier -quiet -filter {IS_SEQUENTIAL && NAME =~ "*_rep*"}]
}

proc r2_summary {tag} {
    set reps [r2_reps]
    puts "R2 $tag replica_cells=[llength $reps]"
    foreach c $reps { catch { set_property EQUIVALENT_REGISTER_REMOVAL NO $c } }
}

# Dump cell placement (name -> LOC) of two R2 arms so the +0.097 can be
# attributed to placement or to routing.  Light: opens 4 checkpoints, writes text.
set root [file normalize [file join [file dirname [info script]] ../..]]
set out  [file join $root build reports tests_20261025 _place_cmp]
file mkdir $out

set jobs [list \
  [list ctl_placed   [file join $root build local tests_20261025 r2_ctl  riscv_vivado_project.runs impl_m top_pl_bram_placed.dcp]] \
  [list net1_placed  [file join $root build local tests_20261025 r2_net1 riscv_vivado_project.runs impl_m top_pl_bram_placed.dcp]] \
  [list ctl_routed   [file join $root build local tests_20261025 r2_ctl  r2_ctl_routed.dcp]] \
  [list net1_routed  [file join $root build local tests_20261025 r2_net1 r2_net1_routed.dcp]] \
]

foreach j $jobs {
    set tag [lindex $j 0]
    set dcp [lindex $j 1]
    if {![file exists $dcp]} { puts "PLACECMP MISSING $tag $dcp"; continue }
    open_checkpoint $dcp
    set fh [open [file join $out ${tag}.txt] w]
    set n 0
    foreach c [get_cells -quiet -hier -filter {IS_PRIMITIVE}] {
        puts $fh "[get_property NAME $c] [get_property LOC $c]"
        incr n
    }
    close $fh
    puts "PLACECMP $tag cells=$n -> [file join $out ${tag}.txt]"
    close_design
}
puts "PLACECMP DONE"

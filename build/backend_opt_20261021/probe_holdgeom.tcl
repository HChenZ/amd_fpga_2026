# Geometry of the crypto block on the champion netlist, so a hold-oriented pblock split
# can be sized from real numbers instead of guessing.
#   vivado -mode batch -source build/backend_opt_20261021/probe_holdgeom.tcl -notrace
set root [file normalize [file join [file dirname [info script]] .. ..]]
set dcp  [file join $root build local backend_opt_20261021 pl_ndh_crit200_ntr pl_ndh_crit200_ntr_routed.dcp]
if {![file exists $dcp]} { error "missing $dcp" }
set outdir [file join $root build local backend_opt_20261021 recon]
open_checkpoint $dcp

set mods {
    u_soc_axi_top/u_soc_top/u_ascon_mmio
    u_soc_axi_top/u_soc_top/u_ascon_mmio/u_ascon_core
    u_soc_axi_top/u_soc_top/u_ascon_mmio/u_ascon_core/u_crypto_aead
    u_soc_axi_top/u_soc_top/u_ascon_mmio/u_ascon_core/u_crypto_aead/p8_inst
    u_soc_axi_top/u_soc_top/u_ascon_mmio/u_ascon_core/u_crypto_aead/p12_inst
}
set fp [open [file join $outdir holdgeom.csv] w]
puts $fp "module,cells,luts,ffs,minx,maxx,miny,maxy"
foreach m $mods {
    set cells [get_cells -quiet -hier -filter "NAME =~ \"$m/*\" || NAME == \"$m\""]
    if {[llength $cells] == 0} { puts $fp "$m,0,0,0,,,," ; continue }
    set nl [llength [get_cells -quiet $cells -filter {PRIMITIVE_GROUP == "LUT"}]]
    set nf [llength [get_cells -quiet $cells -filter {IS_SEQUENTIAL}]]
    set xs {} ; set ys {}
    foreach c $cells {
        if {[regexp {SLICE_X(\d+)Y(\d+)} [get_property -quiet SITE $c] -> x y]} { lappend xs $x ; lappend ys $y }
    }
    set sx [lsort -integer $xs] ; set sy [lsort -integer $ys]
    if {[llength $sx] == 0} { puts $fp "$m,[llength $cells],$nl,$nf,,,," ; continue }
    puts $fp "$m,[llength $cells],$nl,$nf,[lindex $sx 0],[lindex $sx end],[lindex $sy 0],[lindex $sy end]"
}
close $fp

# immediate children of crypto_aead, so the split boundary is chosen on real structure
set fp [open [file join $outdir holdgeom_children.txt] w]
foreach parent {u_soc_axi_top/u_soc_top/u_ascon_mmio/u_ascon_core/u_crypto_aead} {
    foreach kid [get_cells -quiet -hier -filter "NAME =~ \"$parent/*\" && IS_HIER"] {
        set kn [get_property NAME $kid]
        set rest [string range $kn [string length $parent] end]
        if {[regexp {^/[^/]+$} $rest]} {
            set leaves [get_cells -quiet -hier -filter "NAME =~ \"$kn/*\""]
            puts $fp "$kn cells=[llength $leaves]"
        }
    }
}
close $fp
puts "HOLDGEOM DONE"
close_project

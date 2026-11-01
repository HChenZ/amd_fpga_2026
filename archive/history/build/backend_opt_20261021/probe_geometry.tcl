# Device geometry only (no design): slice bbox + SLICEM count per clock region.
#   vivado -mode batch -source build/backend_opt_20261021/probe_geometry.tcl -notrace
set root   [file normalize [file join [file dirname [info script]] .. ..]]
set outdir [file join $root build local backend_opt_20261021 recon]
file mkdir $outdir
create_project -in_memory -part xc7z020clg400-1
set sl [get_sites -filter {SITE_TYPE == "SLICEL" || SITE_TYPE == "SLICEM"}]
set sm [get_sites -filter {SITE_TYPE == "SLICEM"}]
set fp [open [file join $outdir clock_regions.csv] w]
puts $fp "cr,slices,slicems,minx,maxx,miny,maxy"
foreach cr [lsort [get_clock_regions]] {
    set in [get_sites -quiet -of_objects $cr -filter {SITE_TYPE == "SLICEL" || SITE_TYPE == "SLICEM"}]
    if {[llength $in] == 0} { continue }
    set xs {} ; set ys {}
    foreach s $in {
        if {[regexp {SLICE_X(\d+)Y(\d+)} [get_property NAME $s] -> x y]} {
            lappend xs $x ; lappend ys $y
        }
    }
    set nsm 0
    foreach s $in { if {[get_property SITE_TYPE $s] eq "SLICEM"} { incr nsm } }
    puts $fp "[get_property NAME $cr],[llength $in],$nsm,[lindex [lsort -integer $xs] 0],[lindex [lsort -integer $xs] end],[lindex [lsort -integer $ys] 0],[lindex [lsort -integer $ys] end]"
}
close $fp
# global bbox
set xs {} ; set ys {}
foreach s $sl { if {[regexp {SLICE_X(\d+)Y(\d+)} [get_property NAME $s] -> x y]} { lappend xs $x ; lappend ys $y } }
puts "GEOM slices=[llength $sl] slicem=[llength $sm] X=[lindex [lsort -integer $xs] 0]..[lindex [lsort -integer $xs] end] Y=[lindex [lsort -integer $ys] 0]..[lindex [lsort -integer $ys] end]"
close_project

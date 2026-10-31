# 第二轮收敛性实验：目标是剪掉"健康归约 -> 128 个 result 位"的长扇出。
# 手段只有物理层扇出约束（MAX_FANOUT，让 opt_design 复制驱动）+ place/route 指令，
# 不加时序例外、不改时钟、不改 keys_v2 的 RTL。
set root [file dirname [file normalize [info script]]]
while {![file exists [file join $root AGENTS.md]]} {
    set parent [file dirname $root]
    if {$parent eq $root} {error "repo root not found"}
    set root $parent
}
set board $root/board/vivado_zynq7000_xc7z020_puf_min
set stamp [clock format [clock seconds] -format %Y%m%d_%H%M%S]
set out $root/data/advanced/puf_min/sweep2_$stamp
file mkdir $out
open_project $board/work_v2/puf_min.xpr

set fp [open $out/sweep2.tsv w]
puts $fp "combo\tplace\troute\tmaxfanout\twns\twhs\tlogic_levels\tdatapath_ns"
close $fp
proc sweep_row {path row} {
    set fp [open $path a]; puts $fp $row; close $fp
}

# {combo place route maxfanout}
set combos {
    {5 Default Default 32}
    {6 ExtraTimingOpt NoTimingRelaxation 32}
    {7 Default Default 8}
}
foreach combo $combos {
    lassign $combo id placed routed nf
    puts "==== SWEEP2 combo $id place=$placed route=$routed maxfanout=$nf"
    set ::env(PUF_MIN_SAMPLER_REGION) ""
    set ::env(PUF_MIN_MAXFANOUT) $nf
    set_property STEPS.OPT_DESIGN.ARGS.DIRECTIVE Default [get_runs impl_1]
    set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE $placed [get_runs impl_1]
    set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE $routed [get_runs impl_1]
    reset_run impl_1
    launch_runs impl_1 -to_step route_design -jobs 4
    wait_on_run impl_1
    if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
        sweep_row $out/sweep2.tsv "$id\t$placed\t$routed\t$nf\tFAILED\tFAILED\t-\t-"
        continue
    }
    open_run impl_1
    set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
    set whs [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
    set p [get_timing_paths -delay_type max -max_paths 1]
    set lv "-"; catch {set lv [get_property LOGIC_LEVELS $p]}
    set dp "-"; catch {set dp [get_property DATAPATH_DELAY $p]}
    report_timing -max_paths 20 -file $out/combo${id}_setup_paths.rpt
    report_utilization -file $out/combo${id}_utilization.rpt
    write_checkpoint -force $out/combo${id}_routed.dcp
    sweep_row $out/sweep2.tsv "$id\t$placed\t$routed\t$nf\t$wns\t$whs\t$lv\t$dp"
    puts "==== SWEEP2 combo $id wns=$wns whs=$whs levels=$lv datapath=$dp"
}
puts "PUF_MIN_SWEEP2_DONE $out"

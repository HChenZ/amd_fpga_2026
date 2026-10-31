# PUF-MIN 100MHz 收敛性扫描：只改 opt/place/route 指令组合（最后一组额外加一个
# 采样器布局区域），不加任何时序例外、不改时钟、不改 keys_v2。
# 每个组合都 reset_run impl_1 重跑 opt->place->route，记录 WNS/WHS 与最差路径。
# 由脚本位置向上找到仓库根（含 AGENTS.md），避免手工算 ../.. 出错。
set root [file dirname [file normalize [info script]]]
while {![file exists [file join $root AGENTS.md]]} {
    set parent [file dirname $root]
    if {$parent eq $root} {error "repo root (AGENTS.md) not found above [info script]"}
    set root $parent
}
set board $root/board/vivado_zynq7000_xc7z020_puf_min
set stamp [clock format [clock seconds] -format %Y%m%d_%H%M%S]
set out $root/data/advanced/puf_min/sweep_$stamp
file mkdir $out
open_project $board/work_v2/puf_min.xpr

set fp [open $out/sweep.tsv w]
puts $fp "combo\topt\tplace\troute\tregion\twns\twhs\tlogic_levels\tdatapath_ns"
close $fp

proc sweep_row {path row} {
    set fp [open $path a]
    puts $fp $row
    close $fp
}

# {combo opt place route region}
set combos {
    {1 Explore Explore Explore {}}
    {2 Explore AltSpreadLogic_high MoreGlobalIterations {}}
    {3 Explore ExtraTimingOpt NoTimingRelaxation {}}
    {4 Explore AltSpreadLogic_low Explore {SLICE_X54Y70:SLICE_X113Y149}}
}
foreach combo $combos {
    lassign $combo id optd placed routed region
    puts "==== SWEEP combo $id opt=$optd place=$placed route=$routed region=$region"
    set ::env(PUF_MIN_SAMPLER_REGION) $region
    set_property STEPS.OPT_DESIGN.ARGS.DIRECTIVE $optd [get_runs impl_1]
    set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE $placed [get_runs impl_1]
    set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE $routed [get_runs impl_1]
    reset_run impl_1
    launch_runs impl_1 -to_step route_design -jobs 4
    wait_on_run impl_1
    if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
        sweep_row $out/sweep.tsv "$id\t$optd\t$placed\t$routed\t$region\tFAILED\tFAILED\t-\t-"
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
    sweep_row $out/sweep.tsv "$id\t$optd\t$placed\t$routed\t$region\t$wns\t$whs\t$lv\t$dp"
    puts "==== SWEEP combo $id wns=$wns whs=$whs levels=$lv datapath=$dp"
}
puts "PUF_MIN_SWEEP_DONE $out"

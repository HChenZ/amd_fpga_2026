# 定点扇出复制（本地化复制寄存器，缩短单根走线）
#
#   目的：把压在关键路径上的大扇出网拆成多份本地副本。当前最差路径是
#         u_crypto_aead/state[3]（fo=627、单根走线 9.29 ns、1 级逻辑 → p12_in_reg[*]/D），
#         全局最大扇出是复位分发网 u_ascon_mmio/rst_sync_reg[2]（fo=9757）。
#
#   选点（不做全局 MAX_FANOUT —— campaign 的全局复制臂证明会把不相关的网也拆坏）：
#     A) 布线后 DCP 里最差 200 条 setup 路径的「起点寄存器输出网」，fo >= MINFO；
#     B) 同一条路径终点 2 级扇入里的宽网，fo >= MINFO；
#     C) 可选：rst_sync* 分发网（fo >= 1000）。
#     全部排除时钟网络（BUFG/MMCM/PLL 驱动）。
#     post-opt（未布线）的时序视图看不出 70~90% 的走线，所以必须用 seed=布线后 DCP 选点。
#
#   防折叠约束：
#     - opt_design 之前给候选网驱动单元设 EQUIVALENT_REGISTER_REMOVAL=NO，否则
#       opt/phys_opt 会把复制出的等价寄存器合并回去（campaign 记过：只给 MAX_FANOUT
#       而不触发复制时，两臂结果逐位相同）；
#     - 复制入口只有 phys_opt_design -force_replication_on_nets（2025.2）；
#     - 复制后再给新建的 *_rep* 单元设一次 EQUIVALENT_REGISTER_REMOVAL=NO；
#       不用 DONT_TOUCH —— 它同时会冻结放置，副本就搬不到负载附近了。
#
#   vivado -mode batch -source build/timing_tests/rep_fanout.tcl -notrace \
#          -tclargs <tag> <post-opt.dcp> <probe|ctl|rep> [minfo] [with_rst] [seed_routed.dcp]
set root [file normalize [file join [file dirname [info script]] ../..]]
set tag   [lindex $argv 0]
set dcp   [lindex $argv 1]
set mode  [expr {[llength $argv] > 2 ? [lindex $argv 2] : "rep"}]
set minfo [expr {[llength $argv] > 3 ? [lindex $argv 3] : 150}]
set wrst  [expr {[llength $argv] > 4 ? [lindex $argv 4] : 0}]
set seed  [expr {[llength $argv] > 5 ? [lindex $argv 5] : ""}]
set ::drv_kind [expr {[llength $argv] > 6 ? [lindex $argv 6] : "any"}]
if {$tag eq "" || $dcp eq ""} {
    error "usage: -tclargs <tag> <post-opt.dcp> \[probe|ctl|rep\] \[minfo\] \[with_rst 0|1\] \[seed_routed.dcp\]"
}
if {![string match "2025.2*" [version -short]]} { error "Requires Vivado 2025.2" }

set workdir [file join $root build local timing_tests rep $tag]
set repdir  [file join $root build reports timing_tests $tag]
if {[file exists [file join $repdir result.txt]]} { error "tag $tag already has a result" }
file mkdir $workdir; file mkdir $repdir

# ================================================================ 工具过程（必须先定义）
# 引脚/网络名带 [ ]，直接当模式传给 get_pins/get_nets 会被当成字符类；
# 统一走 -filter {NAME == ...} 精确匹配（变量值不会被二次替换），并且 get_pins 必须 -hier。
proc pin1 {name} { return [get_pins -quiet -hier -filter "NAME == \"$name\""] }
proc net1 {name} { return [get_nets -quiet -hier -filter "NAME == \"$name\""] }

proc is_clock_cell {c} {
    if {$c eq ""} { return 1 }
    set r [get_property REF_NAME $c]
    return [expr {$r in {BUFG BUFGCE BUFGCE_DIV BUFG_GT BUFR BUFH BUFIO BUFMR MMCME2_ADV PLLE2_ADV PS7}}]
}

# 只保留「复制有意义」的网：驱动必须是 FF 或 LUT，排除常量、进位链、MUX、RAM、时钟、
# 以及输入端口（rst_n 这类由 IBUF 驱动的网复制不了）。drv_kind=ff 时只留触发器驱动。
proc net_ok {n} {
    set drv [get_pins -quiet -leaf -of_objects $n -filter {DIRECTION == "OUT"}]
    if {[llength $drv] != 1} { return 0 }
    set dc [get_cells -quiet -of_objects $drv]
    if {[llength $dc] != 1} { return 0 }
    set r [get_property REF_NAME $dc]
    if {[is_clock_cell $dc]} { return 0 }
    if {$r in {VCC GND CARRY4 MUXF7 MUXF8 RAMB18E1 RAMB36E1 RAMD32 RAMD64E IBUF IBUFDS OBUF}} { return 0 }
    if {$::drv_kind eq "ff" && ![string match "FD*" $r]} { return 0 }
    if {$::drv_kind eq "lut" && ![string match "LUT*" $r]} { return 0 }
    return 1
}

proc out_net_of {pinobj} {
    set cell [get_cells -quiet -of_objects $pinobj]
    if {[llength $cell] != 1} { return "" }
    set op [get_pins -quiet -leaf -of_objects $cell -filter {DIRECTION == "OUT"}]
    if {[llength $op] != 1} { return "" }
    set n [get_nets -quiet -of_objects $op]
    if {[llength $n] != 1} { return "" }
    return $n
}

proc wide_nets_fanin {pinobj minfo levels} {
    set out {}
    set frontier [list $pinobj]
    for {set lvl 0} {$lvl < $levels} {incr lvl} {
        set next {}
        foreach pin $frontier {
            set cell [get_cells -quiet -of_objects $pin]
            if {[llength $cell] != 1} { continue }
            foreach ip [get_pins -quiet -of_objects $cell -filter {DIRECTION == "IN"}] {
                set n [get_nets -quiet -of_objects $ip]
                if {[llength $n] != 1} { continue }
                if {[get_property FLAT_PIN_COUNT $n] >= $minfo} {
                    set drv [get_pins -quiet -leaf -of_objects $n -filter {DIRECTION == "OUT"}]
                    if {![is_clock_cell [get_cells -quiet -of_objects $drv]]} { lappend out $n }
                }
                set d [get_pins -quiet -leaf -of_objects $n -filter {DIRECTION == "OUT"}]
                if {[llength $d] == 1} { lappend next $d }
            }
        }
        set frontier [lsort -unique $next]
    }
    return $out
}

# ================================================================ 种子：布线后 DCP 上取真实关键路径
set seed_names {}
if {$seed ne ""} {
    if {![file exists $seed]} { error "missing seed dcp $seed" }
    open_checkpoint $seed
    set sp_nets 0
    foreach p [get_timing_paths -quiet -max_paths 200 -nworst 1 -setup] {
        set sp [pin1 [get_property STARTPOINT_PIN $p]]
        if {[llength $sp] == 1} {
            set n [out_net_of $sp]
            if {$n ne "" && [get_property FLAT_PIN_COUNT $n] >= $minfo} {
                set drv [get_pins -quiet -leaf -of_objects $n -filter {DIRECTION == "OUT"}]
                if {![is_clock_cell [get_cells -quiet -of_objects $drv]]} {
                    lappend seed_names [get_property NAME $n]
                    incr sp_nets
                }
            }
        }
        set ep [pin1 [get_property ENDPOINT_PIN $p]]
        if {[llength $ep] == 1} {
            foreach n [wide_nets_fanin $ep $minfo 2] { lappend seed_names [get_property NAME $n] }
        }
    }
    set seed_names [lsort -unique $seed_names]
    puts "REP $tag seed=[file tail $seed] seed_startpoint_nets=$sp_nets seed_unique_nets=[llength $seed_names]"
    close_design
}

# ================================================================ 打开待优化网表
open_checkpoint $dcp
set clinfo {}
foreach c [get_clocks] { lappend clinfo "[get_property NAME $c]@[format %.3f [get_property PERIOD $c]]" }
puts "REP $tag mode=$mode minfo=$minfo with_rst=$wrst drv_kind=$::drv_kind clocks={$clinfo}"

# ================================================================ 选点
set cand_objs {}
foreach nm $seed_names {
    set n [net1 $nm]
    if {$n eq ""} { continue }
    if {[get_property FLAT_PIN_COUNT $n] >= $minfo} { lappend cand_objs $n }
}
foreach p [get_timing_paths -quiet -max_paths 40 -nworst 1 -setup] {
    set sp [pin1 [get_property STARTPOINT_PIN $p]]
    if {[llength $sp] == 1} {
        set n [out_net_of $sp]
        if {$n ne "" && [get_property FLAT_PIN_COUNT $n] >= $minfo} {
            set drv [get_pins -quiet -leaf -of_objects $n -filter {DIRECTION == "OUT"}]
            if {![is_clock_cell [get_cells -quiet -of_objects $drv]]} { lappend cand_objs $n }
        }
    }
    set ep [pin1 [get_property ENDPOINT_PIN $p]]
    if {[llength $ep] == 1} {
        foreach n [wide_nets_fanin $ep $minfo 2] { lappend cand_objs $n }
    }
}

set cand_names {}
set seen [dict create]
foreach n [lsort -unique $cand_objs] {
    if {![net_ok $n]} { continue }
    set nm [get_property NAME $n]
    if {[dict exists $seen $nm]} { continue }
    dict set seen $nm 1
    lappend cand_names $nm
}

if {$wrst} {
    foreach n [get_nets -quiet -hier -filter "FLAT_PIN_COUNT >= 1000"] {
        set nm [get_property NAME $n]
        set drv [get_pins -quiet -leaf -of_objects $n -filter {DIRECTION == "OUT"}]
        set dc [get_cells -quiet -of_objects $drv]
        if {$dc eq ""} { continue }
        if {[string match "*rst_sync*" $nm] || [string match "*rst_sync*" [get_property NAME $dc]]} {
            if {![dict exists $seen $nm]} { dict set seen $nm 1; lappend cand_names $nm }
        }
    }
}

puts "REP $tag candidates=[llength $cand_names]"
foreach nm $cand_names {
    set n [net1 $nm]
    if {$n eq ""} { puts "  CAND ?? $nm"; continue }
    set drv [get_pins -quiet -leaf -of_objects $n -filter {DIRECTION == "OUT"}]
    set dc [get_cells -quiet -of_objects $drv]
    puts [format "  CAND fo=%-6d %-6s %-9s %s" [get_property FLAT_PIN_COUNT $n] \
          [expr {$dc ne "" ? [get_property REF_NAME $dc] : "?"}] \
          [expr {$dc ne "" ? [get_property LOC $dc] : "?"}] $nm]
}

if {$mode eq "probe"} {
    close_project
    puts "REP $tag PROBE ONLY"
    return
}

# ================================================================ opt（前先冻结等价寄存器）
if {$mode eq "rep"} {
    set ndrv 0
    foreach nm $cand_names {
        set n [net1 $nm]
        if {$n eq ""} { continue }
        set drv [get_pins -quiet -leaf -of_objects $n -filter {DIRECTION == "OUT"}]
        foreach c [get_cells -quiet -of_objects $drv] {
            catch { set_property EQUIVALENT_REGISTER_REMOVAL NO $c }
            incr ndrv
        }
    }
    puts "REP $tag eqreg_frozen=$ndrv"
}

opt_design -directive Explore
place_design -directive Default
report_timing_summary -delay_type max -max_paths 1 -file [file join $repdir place_timing.rpt]
phys_opt_design -directive AggressiveExplore

# ================================================================ 定点复制
if {$mode eq "rep"} {
    set nets {}
    foreach nm $cand_names {
        set n [net1 $nm]
        if {$n eq ""} { continue }
        catch { set_property MAX_FANOUT 128 $n }
        lappend nets $n
    }
    if {[llength $nets] > 0} {
        if {[catch { phys_opt_design -force_replication_on_nets $nets } err]} {
            puts "REP $tag repl_error=$err"
        }
    }
    set reps [get_cells -hier -quiet -filter {IS_SEQUENTIAL && NAME =~ "*_rep*"}]
    puts "REP $tag replica_cells_after_repl=[llength $reps]"
    foreach c $reps { catch { set_property EQUIVALENT_REGISTER_REMOVAL NO $c } }
    foreach nm $cand_names {
        set n [net1 $nm]
        if {$n ne ""} { puts [format "  AFTER fo=%-6d %s" [get_property FLAT_PIN_COUNT $n] $nm] }
    }
}

route_design -directive AggressiveExplore
phys_opt_design -directive AggressiveExplore

report_utilization -file [file join $repdir route_utilization.rpt]
report_timing_summary -delay_type min_max -report_unconstrained -file [file join $repdir route_timing.rpt]
report_timing -delay_type max -max_paths 20 -file [file join $repdir route_paths.rpt]
report_route_status -file [file join $repdir route_status.rpt]
catch { report_high_fanout_nets -fanout_greater_than 256 -max_nets 40 -load_types \
        -file [file join $repdir high_fanout.rpt] }

set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
set whs [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]]
set fpaths [get_timing_paths -quiet -max_paths 100000 -nworst 1 -setup -slack_less_than 0.0]
set tns 0.0
foreach q $fpaths { set tns [expr {$tns + [get_property SLACK $q]}] }
set luts [llength [get_cells -hier -filter {PRIMITIVE_GROUP == "LUT"}]]
set ffs  [llength [get_cells -hier -filter {IS_SEQUENTIAL}]]
set reps [llength [get_cells -hier -quiet -filter {IS_SEQUENTIAL && NAME =~ "*_rep*"}]]
set wp [get_timing_paths -max_paths 1 -nworst 1 -setup]
set fp [open [file join $repdir result.txt] w]
puts $fp "RESULT tag=$tag mode=$mode minfo=$minfo with_rst=$wrst wns=[format %.3f $wns] tns=[format %.3f $tns] failing=[llength $fpaths] whs=[format %.3f $whs] luts=$luts ffs=$ffs rep_cells=$reps cand=[llength $cand_names]"
puts $fp "PATH start=[get_property STARTPOINT_PIN $wp] end=[get_property ENDPOINT_PIN $wp] dp=[format %.3f [get_property DATAPATH_DELAY $wp]] logic=[format %.3f [get_property DATAPATH_LOGIC_DELAY $wp]] net=[format %.3f [get_property DATAPATH_NET_DELAY $wp]] levels=[get_property LOGIC_LEVELS $wp]"
puts $fp "SOURCE dcp=[file tail $dcp] seed=[file tail $seed] tool=[version -short] date=[clock format [clock seconds]] head=[exec git -C $root rev-parse --short HEAD]"
close $fp
puts "REP RESULT tag=$tag mode=$mode wns=[format %.3f $wns] tns=[format %.3f $tns] failing=[llength $fpaths] whs=[format %.3f $whs] reps=$reps cand=[llength $cand_names]"
write_checkpoint -force [file join $workdir ${tag}_routed.dcp]
close_project
puts "REP $tag COMPLETE"

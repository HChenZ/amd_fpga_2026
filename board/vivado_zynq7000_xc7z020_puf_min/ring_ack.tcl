# impl_1 opt_design pre-hook（此时网表存在，XDC 阶段还不存在）：
#  1) 为 256 个物理五级 LUT 环各自确认唯一反馈网，并打开 ALLOW_COMBINATORIAL_LOOPS
#     （逐环确认，不是"整片关 DRC"，也不给 RO 虚构时钟周期）。
#  2) 建立 RO pblock，保证 1280 个环 LUT 全部落在指定区域内。
# 不做的事：define RO clock、全局 false_path、clock_groups、降级 DRC 严重度。
set root [file normalize [file join [file dirname [info script]] ../..]]

# 本脚本作为 impl_1 的 OPT_DESIGN.TCL.PRE 运行时，跑在独立的解释器里，
# 会话里设置的 ::puf_min_out 不可见；改为读取 setup.tcl 落在工程目录里的标记文件。
set projdir [file normalize [get_property DIRECTORY [current_project]]]
set marker [file join $projdir puf_min_out.txt]
if {[info exists ::puf_min_out]} {
    set out $::puf_min_out
} elseif {[file exists $marker]} {
    set f [open $marker r]; set out [string trim [read $f]]; close $f
} else {
    set out $root/data/advanced/puf_min/ring_ack_[clock format [clock seconds] -format %Y%m%d_%H%M%S]
}
file mkdir $out

set gates [get_cells -quiet -hier -filter {NAME =~ */bank/rings*gate0 && REF_NAME == LUT2}]
if {[llength $gates] != 256} {error "Expected 256 PUF ring gates, got [llength $gates]"}
set ro_luts [get_cells -quiet -hier -filter {NAME =~ */bank/rings* && REF_NAME =~ LUT*}]
if {[llength $ro_luts] != 1280} {error "Expected 1280 RO LUTs, got [llength $ro_luts]"}

set fp [open $out/ring_inventory.txt w]
puts $fp "cell\tfeedback_net\tdriver\tallow_loops\tro_clock_defined"
foreach gate $gates {
    # 环内唯一的组合反馈：gate0 的 I1 引脚上挂的那根 net（由 stages[4].inv0/O 驱动）。
    set fb [get_nets -of_objects [get_pins -of_objects $gate -filter {REF_PIN_NAME == I1}]]
    if {[llength $fb] != 1} {error "Ring feedback ambiguity at $gate -> $fb"}
    set driver [get_pins -leaf -of_objects $fb -filter {DIRECTION == OUT}]
    if {[llength $driver] != 1} {error "Ring feedback driver ambiguity at $gate -> $driver"}
    # gate 路径形如 <hier>/bank/rings[n].gate0；同环末级反相器是 rings[n].stages[4].inv0/O。
    # 用 string map 精确去掉 .gate0，避免手工算字符偏移（差一位就会静默匹配错）。
    set base [string map {.gate0 ""} $gate]
    set expected "${base}.stages\[4\].inv0/O"
    if {[get_property NAME $driver] ne $expected} {
        error "Unexpected ring driver at $gate: got [get_property NAME $driver] expected $expected"
    }
    set_property ALLOW_COMBINATORIAL_LOOPS TRUE $fb
    puts $fp "$gate\t$fb\t$driver\t1\t0"
}
puts $fp "RO_TIMING=NOT_MEASURED; no oscillator clock defined; structural implementation only."
close $fp

# 只把环阵列（ro_array_v2 里面的 1280 个 LUT）放进 pblock，不把计数器/AXI 逻辑
# 一起关进去，避免人为制造布线拥塞（pynq_puf 曾把整个 u_puf 关进同一区域）。
# 实例路径不写死：从 ring 门单元名反推 bank 层次，模块参考/包装层次变化时不会失效。
set first_gate [lindex $gates 0]
set bank_name [file dirname [string map {.gate0 ""} $first_gate]]
set bank [get_cells -quiet $bank_name]
if {[llength $bank] != 1} {
    error "Expected exactly one ring bank instance at '$bank_name', found [llength $bank]"
}
create_pblock pb_ro_puf
add_cells_to_pblock pb_ro_puf $bank
resize_pblock pb_ro_puf -add {SLICE_X60Y115:SLICE_X113Y149}

# 可选：把整个采样器也放进同一个区域（收敛性实验用）。区域由环境变量给出，
# 例如 SLICE_X54Y70:SLICE_X113Y149。环阵列仍然全部落在 pb_ro_puf 内。
if {[info exists ::env(PUF_MIN_SAMPLER_REGION)] && $::env(PUF_MIN_SAMPLER_REGION) ne ""} {
    set sampler [get_cells -quiet -hier -filter {NAME =~ */u_regs/sampler}]
    if {[llength $sampler] != 1} {error "Expected one sampler instance, found [llength $sampler]"}
    add_cells_to_pblock pb_ro_puf $sampler
    resize_pblock pb_ro_puf -add $::env(PUF_MIN_SAMPLER_REGION)
    puts "PUF_MIN_SAMPLER_REGION $::env(PUF_MIN_SAMPLER_REGION) cell=$sampler"
}
# 可选：物理层扇出约束。PUF_MIN_MAXFANOUT=<n> 时，对采样器里参与"健康归约"的
# 组合网设置 MAX_FANOUT，让 opt_design 复制驱动，把单个归约节点到 128 个 result 位
# 的长扇出拆开（实测关键路径 74% 是布线）。这**不是**时序例外：不加 false_path、
# 不改时钟、不改 RTL。
if {[info exists ::env(PUF_MIN_MAXFANOUT)] && $::env(PUF_MIN_MAXFANOUT) ne ""} {
    set nf $::env(PUF_MIN_MAXFANOUT)
    set fp2 [open $out/fanout_before.txt w]
    set nets [get_nets -quiet -hier -filter {NAME =~ *sampler*error*}]
    foreach n $nets {puts $fp2 "$n\tfanout=[get_property FANOUT $n]"}
    close $fp2
    set tagged 0
    foreach n $nets {
        if {[get_property FANOUT $n] > $nf} {
            set_property MAX_FANOUT $nf $n
            incr tagged
        }
    }
    puts "PUF_MIN_MAXFANOUT value=$nf nets_seen=[llength $nets] nets_tagged=$tagged"
}

puts "PUF_MIN_RING_ACK_OK ring_gates=256 ro_luts=1280 pblock=pb_ro_puf cell=$bank"

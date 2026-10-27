# 在 opt_design 之前（网表已存在）为 RO 环内的 net 打开 ALLOW_COMBINATORIAL_LOOPS。
#
# 两个坑：
#  1) 不能写在 XDC 里：约束在综合前读入，那时 net 不存在，get_nets 返回空、属性被静默丢弃。
#  2) 不能用层次名过滤：综合后 u_puf 会被打平，net 名变成 u_puf_key/...，
#     "*u_puf_key/u_puf/g_ro*/u_ro/n*" 这类模式匹配不到任何东西。
#     所以这里从 u_ro 实例的 LUT 单元出发、按引脚找 net，对打平免疫。
set n 0
set ros 0
foreach c [get_cells -quiet -hier -filter {NAME =~ "*u_ro/*"}] {
    incr ros
    foreach p [get_pins -quiet -of_objects $c -filter {DIRECTION == "OUT"}] {
        foreach nt [get_nets -quiet -of_objects $p] {
            set_property ALLOW_COMBINATORIAL_LOOPS TRUE $nt
            incr n
        }
    }
}
puts "RO_ALLOW_LOOPS: ro_lut_cells=$ros nets_tagged=$n"

# ============================================================================
# keys_ro_pblock.xdc — 把 RO PUF 阵列隔离到器件右上角，减少对 CPU 时序的扰动
#
# 用法（Vivado）：
#   add_files -fileset constrs_1 build/keys_ro_pblock.xdc
# 或在独立 STA 脚本里 read_xdc（见 build/build_keys_sta.tcl）。
#
# 区域选择依据（xc7z020clg400 实测网格 X0..113 / Y0..149）：
#   CPU 核分布 X32..106 / Y0..113；Y115..149 是上沿 35 行，基本空闲，
#   54 列 × 35 行 ≈ 1890 slice，足够 256 个 RO + 计数器（约 1.8k LUT）且远离 CPU。
# ============================================================================

create_pblock pb_ro_puf
add_cells_to_pblock pb_ro_puf [get_cells -quiet u_soc_axi_top/u_soc_top/u_puf_key/u_puf]
resize_pblock pb_ro_puf -add {SLICE_X60Y115:SLICE_X113Y149}

# RO 的抗优化由 RTL 里的 (* DONT_TOUCH *) 保证（已实测 256 根 × 5 LUT 全部保留）；
# 这里不要再写 get_cells/set_property，约束在综合前读入时 cell 还不存在，属于无效语句。

# 注意：RO 环的 ALLOW_COMBINATORIAL_LOOPS **不能写在这里**（约束在综合前读入，
# 那时 net 还不存在，get_nets 返回空、属性被静默丢弃）。见 build/keys_ro_allow_loops.tcl，
# 由 build_keys_sta.tcl 挂到 STEPS.OPT_DESIGN.TCL.PRE。

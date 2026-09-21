# Kintex 历史工程

这是原 tracked Kintex 工程的唯一入口，通过用户授权的 git mv 归并；此前未跟踪的 XPR/XDC 副本已从工作区移出，原路径不再保留。逐文件比较证明 XPR/XDC 完全一致，rename 不修改它们的字节内容。

目录与原工程同深度，`$PPRDIR/../../src/rtl` 仍指向当前开发 RTL，XDC 的 `$PSRCDIR` 保持内部布局；32 个 File 引用重新核验通过。两个原已跟踪 .cache/.hw 生成元数据已清理，不属于恢复的 579 个资产。

part 为 xc7k325tlffv676-2L，Vivado 文件记录 2025.2，top 为 top_pl_bram；仍缺三个 IP，不能宣称可构建。本目录仅保留历史配置与对比依据，实际 XC7Z020 baseline 在相邻独立目录。

XPR 原有绝对 Project Path 元数据保持原字节；实际活动文件使用相对引用。本轮未增加绝对路径依赖、未启动 Vivado。参见 [工程比较](../../docs/vivado_project_diff.md) 与 [收口检查](../../docs/repository_foundation_closeout.md)。

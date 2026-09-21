# 板级工程与运行

board 下只有两个工程目录：

| 入口 | 角色 |
|---|---|
| [vivado_zynq7000_xc7z020_baseline](vivado_zynq7000_xc7z020_baseline/readme.md) | 真正的 CICC1000023 XC7Z020 baseline；B02 的重建验证入口，XPR/XCI/XDC/COE/imports 已恢复 |
| [vivado_kintex7_legacy](vivado_kintex7_legacy/readme.md) | 原 tracked Kintex 工程经 git mv 归并的唯一历史入口；仍缺三个 IP，不作为目标板构建入口 |

foundation 收口逐文件比较后移出未跟踪副本，再 git mv 原工程；原路径不再存在。XPR/XDC 字节未修改，相对引用仍有效。两项旧 .cache/.hw 生成元数据已清理，不保留第三份工程或生成缓存。

Zynq 目录只包含 37 个源/配置资产和 readme，未放入 bitstream/DCP/runs/cache/临时日志/批量 ELF/HEX。历史报告另存 build/reports/cicc1000023_archive。详见 [收口检查](../docs/repository_foundation_closeout.md) 与 [恢复审计](../docs/cicc1000023_recovery_audit.md)。

B03 的 target part = xc7z020clg400-1 已确认；physical board model / revision / 引脚适用性 / PYNQ image 仍 pending。本轮只完成组织与静态核验，不代表重新综合、实现或上板通过。

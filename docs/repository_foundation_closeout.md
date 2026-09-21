# Repository foundation 收口

日期：2026-09-21。范围：按用户授权归并 Kintex 入口、确认 Zynq 源配置与 579 个资产、同步任务并核验 Git/路径。未新增功能、未改 RTL/XPR/XDC、未运行 Ascon、Vivado 或功能仿真；未 commit/push。之前恢复阶段的结果不冒充本轮测试。

## 1. Kintex 比较与 rename

比较发生在任何文件操作之前；逐文件 SHA-256 存入 [收口核验元数据](../build/metadata/repository_foundation_checks.json)。

| 工程相对路径 | 原 tracked 目录 | 原 untracked 副本 | 判定 |
|---|---|---|---|
| riscv_vivado_project.xpr | 存在 | 存在 | 字节相同，SHA-256 a5f54c758adea1ccbbf6042e3ed6823a46139d57250133a32f2b60943552c6e6 |
| riscv_vivado_project.srcs/constrs_1/new/constrs.xdc | 存在 | 存在 | 字节相同，SHA-256 e13fefdc309c09271ad8780208edaa13fda6d5a290f5c40b08e15ae7b4eae290 |
| riscv_vivado_project.cache/wt/project.wpc | 独有，61 bytes | 无 | 生成元数据，收口清理 |
| riscv_vivado_project.hw/riscv_vivado_project.lpr | 独有，425 bytes | 无 | 生成元数据，收口清理 |
| readme.md | 无 | 独有说明文档 | 保留并更新角色说明 |

没有共同工程文件的内容差异。先把未跟踪副本从仓库移出并在系统临时目录备份，再执行：

```text
git mv board/riscv_vivado_project board/vivado_kintex7_legacy
```

两个生成元数据另从索引和工作区移除，原字节仍可从 Git HEAD 或仓库外备份追溯。它们不属于 579 资产，故清理后资产总数不变。未递归清理其他工作内容。git mv 与删除已暂存；其余新资产/文档仍未暂存。

## 2. 最终 board 结构与角色

```text
board/
├── readme.md
├── vivado_kintex7_legacy/
│   ├── readme.md
│   ├── riscv_vivado_project.xpr
│   └── riscv_vivado_project.srcs/constrs_1/new/constrs.xdc
└── vivado_zynq7000_xc7z020_baseline/
    ├── readme.md
    ├── riscv_vivado_project.xpr
    └── riscv_vivado_project.srcs/
        ├── constrs_1/new/const.xdc
        └── sources_1/
            ├── imports/rtl/             31 RTL/header
            ├── imports/bin_file/       freertos_demo.coe
            └── ip/                     3 XCI
```

Kintex 是唯一 legacy，保留对当前开发 RTL 的相对引用；它仍缺 IP，不作为目标板重建入口。Zynq 是原比赛真实 baseline，内部 imports 为独立原始快照，不自动接入 Ascon。board 与整个非 .git 工作区都只包含两份 XPR，没有第三份工程。

Zynq 恢复资产共 37：XPR 1、XCI 3、XDC 1、必要 COE 1、RTL/header 31，另有一份目录说明。不包含 .cache/.gen/.hw/.runs/.sim、DCP、bitstream、临时日志、批量 ELF/HEX。精选历史证据只在 build/reports/cicc1000023_archive。

## 3. 579 个资产按用途分类

本轮按用户四类口径新增 manifest.foundation_category；原 archive category 仍表示上一轮来源分类，不覆盖历史分类含义。每条记录只归一类。

| 类别 | 数量 | 路径范围与构成 |
|---|---:|---|
| A. source | 485 | Zynq imports RTL/header 31；src/firmware/cicc1000023 411；sim/cicc1000023 的 formal 源 20、unit TB 21、ISA TB 2 |
| B. build/config input | 85 | Zynq XPR/XCI/XDC/COE 6；Kintex XPR/XDC 2；firmware Makefile/linker/转换及构建输入 54；formal Tcl/Makefile/flist/shell 23 |
| C. test/reference data | 3 | data/recovery/cicc1000023/smoke：两个 add HEX、一个 bootloader COE |
| D. historical evidence | 6 | build/reports/cicc1000023_archive：4 rpt、2 runme log |
| 合计 | 579 | 全部哈希保持不变 |

A 包括测试源码及随源许可证/README；测试源码不是 C 类测试数据。B 包括构建与转换脚本，FreeRTOS COE 虽由编译产生，但作为原 IP 必需的初始化输入必须保留。C 的 bootloader COE 只是历史候选，原 BRAM 仍使用 FreeRTOS COE。D 不代表本轮硬件结果。

新增说明文档、manifest/inventory/diff 和本轮检查元数据不计入这 579 个归档/legacy 资产。没有大量生成文件误导入；无 ELF、bitstream、DCP、编译对象或波形进入候选 Git 文件集。

## 4. 任务状态

- B01 = done。
- B02 = Rebuild and verify recovered XC7Z020 CICC baseline，in_progress；源已恢复，后续是重建和验证，不再寻找缺失工程。
- B03：target part = xc7z020clg400-1 confirmed；physical board model pending，实际 revision/引脚/image/上板仍待确认，状态 blocked。

## 5. 收尾核验与提交边界

rename 后重新解析 Kintex 32 个及 Zynq 36 个活动 File 引用，并核验 XCI→COE；源路径均存在。两套 XPR/XDC 与全部 RTL 的本轮前后哈希一致；579 资产哈希校验通过。源码/工程未引入新的绝对路径，文档链接核验通过。

“无绝对路径新增”不等于原归档完全没有旧绝对路径：XPR 的 Project Path/ImportPath、历史日志，以及原 FreeRTOS install-ram 的旧路径保持原件；这些是此前已审计的历史内容。活动 XPR File 相对引用有效，新脚本/配置没有新增机器路径依赖。旧固件路径/依赖仍需 B04 在隔离副本显式适配。

运行 git status、git diff --stat、git diff --check，并额外检查 git diff --cached --stat/--check。普通 diff 不显示已暂存 rename 或未跟踪的新增资产，故结合三者评审。原精确 stdout 和各项核验见 [收口核验元数据](../build/metadata/repository_foundation_checks.json)。

已达到“仓库基础整理与原始资产恢复”提交的可审查状态；提交可记录 foundation 完成，但不能宣称 B02 重建/B03 实物验证完成。用户人工选择暂存与提交；本轮没有 commit/push。

收尾发现：默认 cached diff 检查把原 Kintex XPR/XDC 的 CRLF 判作行尾空白。保持源字节不动，仅在 `.gitattributes` 对这两个文件声明 cr-at-eol，同时保留 blank-at-eol、blank-at-eof、space-before-tab 检查；复核原哈希和检查结果。

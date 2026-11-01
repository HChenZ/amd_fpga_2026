# 工程版本清单与 PUF3 入口一致性审计

日期：2026-11-01；owner TBD；Git HEAD `35fe0a5`（当前本地 main，比 origin/main 领先 8 个提交）。
当前源码包冻结点 `92159b9`；随后 `35fe0a5` 提交了冻结元数据。另有上一轮 P0 复核文档/日志未提交。

> 后续说明收口：本文记录审计时发现的入口/文档问题。当前导航已按用户要求更新，见
> [版本入口速查](version_entrypoints.md)；本文“仍有旧说明”的清单保留作发现记录，不表示这些说明尚未修订。
> 旧程序/默认值没有修改，默认CPU回归缺依赖等程序问题仍保留；历史包没有重新装配。

## 1. 结论与范围

**不是所有脚本都对应 PUF3，也不应该把所有脚本机械改成 PUF3。** 当前仓库同时保存原始资产、历史发布、
独立 DMA/PUF 实验、通用 Skill 和 PUF3 主演示。PUF3 专用构建→固件→Notebook→板测→报告→当前证据包的
核心链路一致；但若按未充分标注的旧入口运行，会进入 PYNQ v1、旧 CPU 自测，或已作废的报告流水线。

本次检查：

- 枚举 `board/` 的 12 个目录（11 个工程家族 + 1 个资料目录）、固件 9 个目录、Git 中 5 个 XPR 和另一个本机 XPR。
- 扫描 493 个跟踪/明确未跟踪的 `.py/.tcl/.sh/.ps1/.bat/.ipynb` 文件，按家族分类，记录路径、哈希、身份/板测路径引用。
  排除证据包重复副本、LLM 会话、原始第三方固件和锁定 reference；不是对 493 个程序逐一做了完整动态测试。
- PUF3 candidate 五项工件、56 个生产输入、12 个固件构建输入和板测绑定核对；报告与当前 ZIP 核对。
- 5 组 Icarus **只编译/elaboration**，2 个模拟寄存器身份检查；D02 和报告现有证据/PDF 复核。
  未运行 Vivado、未下载 bitstream、未重新编译固件、未执行新的板测或完整 RTL 功能回归。
- 机器可读明细：`build/metadata/version_alignment_20261101.json`。

“本次不用”只表示不作为本次主演示/重建入口，不表示授权删除。共享依赖与历史证据不能按名称盲删。

## 2. 名称先分清

- **PUF3 / pynq_puf3**：三模式 SW/MMIO/ISE + PUF 密钥通路的集成 overlay，使用 **PUF v1** RTL；
  **不等于 PUF 第三代 RTL，也不是 keys_v2 的升级版**。
- **keys_rv32 v3**：早期 PUF 自检固件的第三次握手修复版本，仍使用 PUF v1 RTL；不是 PUF3 服务固件。
- **PUF v2 / keys_v2 / puf_soc_v2**：另一套 fail-closed/采样协议/镜像认证实验架构，不能替换 PUF3 的 keys。
- **rtl_p0**：无 PUF 的 SoC/MMIO 固定源快照；这里的 P0 是源集名称，不是“所有 P0 任务已验收”。

## 3. 全部板级工程家族

路径均相对 `board/`。当前“只用”一栏指当前交付职责。

| 名称/目录 | 对应内容与身份 | 当前处理 |
|---|---|---|
| `vivado_zynq7000_xc7z020_pynq_puf3` | **主演示**；top `pynq_puf3_wrapper`，ID **PQF3=0x33465150**，固件 **pynq-svc-puf3**；UART mailbox/Y01 + Y01P/Y01K；三模式 ≤16 B + PUF v1；bit `769ed24c…` | **用：唯一当前 Ascon/PUF 实板主演示入口** |
| `vivado_zynq7000_xc7z020_pynq` | 旧三模式、无 PUF；`pynq_wrapper`，ID PYNQ=0x514e5950，固件 pynq-svc-v1，bit `6e7f9320…`；`rtl_p0` 固定快照；23342/1439/3995 | 本次主性能不用；保留历史 9/9 门禁、Skill L3 Ascon 工件、其他实验共享依赖 |
| `vivado_zynq7000_xc7z020_pynq_puf` | PUF-only PYNQ 迁移；`pynq_puf_wrapper`，ID **PFU1=0x31554650**，keys_rv32 v3 固件，ASCII 自检，不是三模式 Y01 服务；当前候选 `47da0494…` | 不用：PUF3 的前身；有离线证据，未找到独立板测归档；不能套用 PUF3 结果 |
| `vivado_zynq7000_xc7z020_ascon` | 早期 PL-only/JTAG 上板工程，`top_pl_bram`；SW/ISE/MMIO 三份 COE/bit，后又进入 keys3 阶段；真实 CH340 UART | 不作当前演示入口；保留历史 20806/688/2570 与 keys3 证据。**其 BRAM/AXI XCI 被 PUF3 build.tcl 导入，不能整目录删除** |
| `vivado_zynq7000_xc7z020_baseline` | 恢复的原始 CICC XC7Z020 工程，`top_pl_bram`，FreeRTOS COE，不是 Ascon/PUF3 | 不用作演示；保留原始基线/来源与 IP 依赖 |
| `vivado_kintex7_legacy` | 原 Kintex `xc7k325tlffv676-2L` 工程，不是目标 XC7Z020 | 本次不用，历史保存，不应打开后直接改 part 当作当前工程 |
| `vivado_zynq7000_xc7z020_pynq_dma_cpu` | **独立 CPU-DMA 实验**；`cpu_dma_wrapper`、D01/ABI v2、dma_svc 固件；SW/ISE ≤32 B、HW ≤16 B；最终候选实际 FCLK **80 MHz**，bit `0985b762…` | 本次不用作主演示；保留实验证据。全量 CPU 仿真是该版本，不是 PUF3；未板测 |
| `vivado_zynq7000_xc7z020_dma_direct` | **HW_DIRECT**，无 RV32；DMA mode4，PT/AD 各 ≤1024 B，100 MHz；bit `1f378552…`；非 Y01 服务 | 本次不用作主演示；保留多块核/DMA 实验；未板测，PL cycles 不可当 RV32 ISE cycles |
| `vivado_zynq7000_xc7z020_axi_dma_loopback` | 无 Ascon、无 RV32；`dma_loop_wrapper`，simple AXI DMA 纯回环，bit `890add35…` | **保留并使用于 Skill L3 的独立非 Ascon 测试**，不能并入 PUF3 主性能 |
| `vivado_zynq7000_xc7z020_puf_v2` | keys_v2 + RV32 自检 SoC，ID **PFU2=0x32554650**，ASCII 自检；旧候选 hash `05c955cd…` | **禁止上板/交付：INVALID_DO_NOT_PROGRAM**，见 candidate/INVALID.md；PS 引脚约束错误、RO 未签核；capture.py 已有 hash 黑名单 |
| `vivado_zynq7000_xc7z020_puf_min` | **PUF-MIN**：PL 只做物理响应，PS 做注册/重建/派生/密码；ID **PMIN=0x4e494d50**，无 RV32/ISE；`work/`、`work_v2/` 为独立尝试 | 本次不用；探索实现/单测，未见已发布 candidate；不能当 PUF3 或 PUF v2 SoC 的板测版本 |
| `atk_navigator_7020` | 厂家资料、引脚核验、平台/CPU+CLINT 测试交接 | 非 overlay，保留资料；文中旧 pending 仅代表当时状态 |

另有本机未跟踪的 `ascon/ASCON.xpr`（XC7Z020、top_pl_bram，引用恢复 IP 与当前开发 RTL）：
旧本地开发工程，不是 PUF3 BD 入口，不作为当前发布物；不要未经确认删除。

### 重要的历史子版本

| 家族 | 子版本与当时用途 | 当前可用性 |
|---|---|---|
| PL-only Ascon | SW bit `f4233827…`、ISE `f85eb1a6…`、MMIO `2f6f2469…` | 历史三套独立固件/镜像；不同于同一 bit 的 PUF3 三模式 |
| PL-only keys | keys_rv32 初版→v2 握手修复（8623ea3）→v3 先等 idle/确认本次受理（a4ae769）；keys3 bit `edaf8417…` | v2 日志含失败，v3 quality 128/128；不能和 PUF3 quality 127/128 混用 |
| PUF-only PYNQ | 首候选 `59e23742…`；后候选 `47da0494…` | PUF-only，非三模式；旧 1280/1280“物理在 pblock”说法已纠正为 assignment 与 placement 分列 |
| PUF3 | 首候选 `56b3bc45…`：IOPLL/分频假设错误，板上 62.5 MHz；修正版 `769ed24c…`：PLL=30、分频10×1 | **只用修正版**；10-30 的 6 组/289 组及 10-31 的 289 组是运行记录演进，不代表每次都换了 bit |
| CPU-DMA | `vivado_20261030_015408` 未导出 PS 引脚；`025251` 100 MHz WNS −0.046；`040257` 80 MHz +0.601 | 前两版不用；最后一版仅独立离线候选，非 PUF3 |
| HW_DIRECT | `015458` RAM 中间版 +0.242；`024214` 最终 +0.345 | 用于实验复核只认后者；无实板性能 |
| CPU 时序 | key-lifecycle/fix_r1→ACB 双策略→B/C/E 等后续优化、backend placement sweep | 是源码/策略阶段，不是另一个当前应用版本；不能重套其历史周期到 PUF3 |
| Cache 探索 | `src/rtl/dcache_experiments/dcache_aggressive_fsm.v`、`dcache_timing_optimized.v`、`dcache.v.backup_manual` | 不在 PUF3 构建顶层 glob 源集，不替换当前 src/rtl/dcache.v |

## 4. 固件版本：9 个目录不能只按旧名字删

| 路径（相对 src/firmware） | 角色 | PUF3 是否使用 |
|---|---|---|
| `pynq_svc_puf` | 当前 main.c + puf_svc.c/h + build.py；固件身份 pynq-svc-puf3 | **主固件** |
| `pynq_svc` | 旧 v1 的 main.c/build.sh；同时提供 svc_io.c、ascon_modes.c、svc.h、bin2coe.py | **共享文件必须保留**，但不用其 main.c/build.sh 生成主演示固件 |
| `ascon_hw_rv32` | PL-only MMIO 自测 main；另提供 crt0.S、libc_min.c、riscv.ld、bin2vhex.py | **后四项被 PUF3 固件构建直接复用**；其独立 main 不用 |
| `ascon_rv32` | PL-only 纯软件自测 | 当前演示不单独用；算法生产 C 在 ascon/ascon_c/aead，不能混为固件版本 |
| `ascon_ise_rv32` | PL-only ISE 自测 | 当前演示不单独用；用于历史回归/指令研究 |
| `keys_rv32` | PUF v1 的 ASCII 自检固件（v3） | 不作为 PUF3 main；PUF3 协议借鉴其流程，keys_v2 构建还共享其启动/UART支持 |
| `keys_v2` | 独立 PUF v2 自检/驱动 | 不用 |
| `pynq_dma_svc` | 独立 CPU-DMA 固件 | 不用 |
| `cicc1000023` | 恢复 coremark_rv32/coremark_rv64/freertos_demo/riscv_tests 四类原始资产 | 不作为当前固件；保留来源和原 baseline 验收 |

`svc.h` 的 FW_ID_STR 仍是 pynq-svc-v1 **不是 PUF3 固件混版错误**：
PUF3 main.c 在 include 后明确 `#undef FW_ID_STR` / `#define FW_ID_STR "pynq-svc-puf3"`。
本次核对其 build.json 的 12 项输入与当前文件 raw/LF 哈希全部一致。

## 5. 当前 PUF3 的实际依赖链

```text
src/firmware/pynq_svc_puf/build.py
  ├─ pynq_svc_puf/main.c + puf_svc.c
  ├─ pynq_svc/{svc_io.c,ascon_modes.c,svc.h,bin2coe.py}
  ├─ ascon_hw_rv32/{crt0.S,libc_min.c,riscv.ld,bin2vhex.py}
  └─ ascon/ascon_c/aead/ 的生产实现
          → pynq_svc_puf.{bin,elf,hex,coe}
board/..._pynq_puf3/build.tcl
  ├─ 当前公共 CPU / Ascon / keys / pynq RTL
  ├─ 排除 src/rtl/{top_pl_bram.v,soc_top.v} 与 keys/key_mmio.v
  ├─ 换入 ..._pynq_puf3/rtl/{soc_top.v,key_mmio.v}
  ├─ 从 ..._ascon/.../ip 导入 AXI BRAM/blk_mem_gen XCI
  └─ PQF3 + pynq_svc_puf.coe → PUF3 bit/hwh
sim/pynq_puf3/run.py
  └─ 同一固件与变体源 + 自动锁钥 mutant 反例
..._pynq_puf3/package.py → candidate/（已冻结，不要无条件重发）
src/pynq_puf3/pynq_puf3_board_test.ipynb
  ├─ 内嵌 Puf3BridgeRegs / PynqPuf3Transport（覆写 v1 身份与 Y01K 分帧）
  ├─ 共用 src/pynq 的 API/协议/golden 与 benchmark 纯函数
  └─ data/pynq_puf3/notebook_20261031_114512/result.json
最终报告 build_review/review_evidence → output/pdf/final_report.pdf
build_evidence/check_benchmark_tables/assemble → current_evidence.json
freeze_manifest.py → 冻结清单/源码包
```

**不能把 `src/rtl/soc_top.v` 直接当 PUF3 SoC。** 它仍是自动锁定硬件密钥的旧 PUF v1 集成版；
PUF3 变体明确用 `key_hw_sel = key_hwkey_on & key_have_r`，只有软件显式打开 HWKEY 才切换。
直接换回旧文件会使 HW 不能按调用方 key 跑官方 KAT；PUF3 mutant 用例专门证明该差异。

## 6. 哪些程序不是 PUF3，是否正常

| 文件/集合 | 当前选择 | 判断 |
|---|---|---|
| `src/pynq_puf3/pynq_puf3_board_test.ipynb` | candidate/pynq_puf3.bit，PQF3，pynq-svc-puf3 | **正确，当前唯一完整板测入口；没有独立 PUF3 CLI/模块入口** |
| `board/..._pynq_puf3/{build,explore_impl,finalize_run,ro_corner_sta,puf_opt_pre}.tcl`、`package.py` | PUF3 工程与变体源 | 正确；重建/发布会产生新工件，不能未经重测沿用原板测 |
| `sim/pynq_puf3/run.py` | PUF3 normal 与旧 autolock 反例；共用 golden/帧编码 | 正确；引用旧 SoC 是有意的负向测试，不应统一替换 |
| `src/pynq/{ascon_host_api,mailbox_protocol,mailbox_backend,golden_checker}.py` | 算法/协议/后端复用 | 正常共享依赖，不应改成仅 PUF3 |
| `src/pynq/board_benchmark.py` 的 `_run_once/select_kat_case/summarize` | 由 PUF3 Notebook 传入已正确创建的 PUF3 backend | 正常复用；**不等于该文件 CLI 也是 PUF3** |
| `src/pynq/{board_demo,board_benchmark,board_error_gate}.py` CLI | 旧 release，pynq.bit/hwh、pynq_svc.elf、pynq-svc-v1 | **不是 PUF3**；只用于 v1 历史复测。仅换 --release 参数也不够，文件名和身份仍不匹配 |
| `src/pynq/pynq_transport.py` 的直接 BridgeRegs/from_overlay | 默认 ID PYNQ=0x514e5950 | 直接用于 PUF3 会被拒绝；Notebook 子类已正确覆写，不是当前 Notebook 的错误 |
| `src/pynq/make_pynq_profile.py` | HWH 解析有通用性，DESIGN_SOURCE/使用示例仍指 v1 | 不算完整 PUF3 配置生成器 |
| `src/pynq/{pynq_board_demo,pynq_board_error_gate}.ipynb` | v1 release 与两个旧 CLI | 不是 PUF3；其已执行输出保留历史意义 |
| `src/pynq/{jupyter_demo,navigator_demo}.ipynb` | 无板/注入式后端展示 | 不是 PUF3 的板测证据 |
| `src/pynq/dma_transport.py`、CPU-DMA bringup.py | DMA ABI v2 / mode1–4 | 只给 DMA 实验版，不适用于 PUF3 的 UART Y01 |
| `src/pynq/{puf_helper_v2,puf_min}.py` | 独立 PUF v2 helper / PUF-MIN | 不用于 PUF3，不可替换其 PUF 命令驱动 |
| `skill/pynq-overlay-workflow/` | 通用工具，契约/回调/manifest 注入 | 正常，不应硬编码 PUF3 |
| Skill L3 `l3_10_ascon_release.ipynb` | 旧 v1 release，ID 0x514e5950、pynq-svc-v1 | **有意冻结的测试对象**；L3 非 Ascon 还用 Base GPIO 与 DMA 回环。不能把 L3 结果说成 PUF3 Skill 复测 |
| `docs/tech_report/evidence/{build_evidence,check_benchmark_tables,assemble,freeze_manifest}.py` | PUF3 主采样 + 最终报告；v1/PL-only 明确历史分组 | 正确；C 组出现 v1 不意味着主演示错版 |
| `docs/tech_report/amd_fpga_2026_latex_final/.../{build_review,review_evidence}.py` | 当前 PUF3 candidate/10-31 结果 | 正确；PDF 和生成记录相符 |
| `docs/tech_report/{build_report,build_latex,build_site,make_overleaf_zip,verify_report}.py` 等 | 已取代的 Markdown/v0.9 流水线 | **不用生成最终报告**；verify_report 还引用已删除的 10-29 数据目录 |
| `build/` 中 ACB/BCE/dcache/sweep/IO-STA 旧构建，`build/advanced/`、`data/advanced/` 中回放脚本 | 各自历史 top/源集/COE，或独立实验 | 不是当前 PUF3 build，不能不分对象全部重跑 |

### 确认存在的入口/说明问题

1. **旧默认 CPU 回归目前不能按默认源清单展开**：`sim/ascon/run_cpu_regression.py:76–82` 选择当前
   src/rtl/soc_top.v，却不加入 keys/BUFG 模型。复现其源列表编译，exit **4**，缺 BUFG/puf_key/key_mmio；
   加 `--pynq-p0` 的源列表编译 exit **0**，但那是旧无 PUF 源集，**不是 PUF3 修复方案**。
   `run_ascon_sw/hw/ise.sh` 薄包装默认继承该问题；`sim/board/run_tests.py` 也只有 pynq-p0 选择而非 PUF3 选择。
2. **v1 的 CLI/Notebook 很容易被误当当前入口**：身份 mock 实测 v1 BridgeRegs 对 PQF3 抛 NotConfiguredError；
   从 PUF3 Notebook 仅提取其身份子类、注入模拟寄存器则接受。没有加载 overlay，也没有绕过身份门禁。
3. **仍有未更新的入口说明**：README.md 表格第 11–13 行仍写 11-04、S04/S05 待收口、当前 top=pynq_wrapper；
   `board/readme.md` 还称只有三个工程；`src/pynq/readme.md` 推荐 v1 Notebook/CLI；`data/readme.md` 还称没有已验 KAT；
   `src/readme.md`、`build/readme.md` 有未充分标注的早期状态。此前“所有入口已统一”的说法过满。
4. **证据子目录自己的 README 有危险旧命令**：`docs/tech_report/evidence/README.md:11` 仍让人运行
   `build_report.py`，而不是最终报告 build_review.py；应当改入口说明，不能只看脚本已改就认定所有操作步骤一致。
5. **源码并非一个根目录通用源集**：PUF3 的两个关键变体在 board/..._pynq_puf3/rtl/。
   当前生产输入 56 项全部匹配，不代表把 src/rtl 整树任意加入工程就能得到同一版本。

## 7. 报告、证据包、源码包版本

### 报告及 ZIP

| 名称/路径 | 对应版本 | 使用结论 |
|---|---|---|
| `docs/tech_report/report.md`、`index.html`、`latex/main.pdf`、`src/`、`src_template/` | v0.9 旧 PYNQ v1 主叙事 | 历史，不用作最终稿 |
| `docs/tech_report/latex_project.zip` | 旧 Markdown 流水线的 Overleaf 包 | 不用；与最终 52 个编译源仅 2 个相同，38 缺失、12 不同 |
| `docs/tech_report/amd_fpga_2026_latex_final.zip` | 队友最初交付 ZIP，“final”是名称，不是当前构建 | 不用上传；与当前 52 个编译源 11 相同、21 缺失、20 不同，内置 PDF 不是当前 PDF |
| `.../amd_fpga_2026_latex_final/amd_fpga_2026_report.zip` | 11-01 较近的报告快照 | 仍不是当前稿：52 个编译源中 51 相同、fig_2_9.tex 不同，PDF 也不同 |
| `.../amd_fpga_2026_report/output/amd_fpga_2026_report_puf3_review.zip` | 10-31 review 快照 | 不用：52 源中 42 相同、10 不同，PDF 不同 |
| `.../amd_fpga_2026_report/output/pdf/final_report.pdf` | **当前定稿 PDF**：构建 build_20261101_174743，77 页，SHA-256 `603c625a…4825` | **唯一当前报告 PDF**，已入库；LaTeX/原图随证据包，不单独入库 |
| `report/project_explainer.html` | 本机新增的 PUF3 讲解页面 | 已使用 PQF3/PUF3 10-31 路径，未跟踪；不是报告 PDF 或证据包的替代品 |

### 所有现存提交包

目录前缀均为 `submission/`，证据目录一般另有同名 ZIP（`evidence/` 是最早历史包）。

| 名称 | 内容/用途 | 当前使用 |
|---|---|---|
| `evidence/` | 最早历史收集包 | 不用 |
| `evidence_20261101_20261029_233749` | 10-29 原 PYNQ v1/旧报告，63 文件 | 作废/历史，不用 |
| `evidence_20261101_20261031_154020` | 119 文件；加入 10-30 PUF3、Skill，但仍旧报告 | 作废/历史，不用 |
| `evidence_20261101_20261031_163056` | 122 文件；旧报告 D02、视频旧稿等 | 作废/历史，不用 |
| `evidence_20261101_20261101_181751` | 266 文件；首次包含当前 PUF3 PDF/10-31 原件，简介尚未更新 | 已取代，不用作最终提交 |
| **`evidence_20261101_20261101_183826`** | **267 文件；当前 PDF、10-31 PUF3、更新的简介/视频稿等**；ZIP SHA-256 `2a0f0304…ffec` | **当前唯一证据包**，由 current_evidence.json 指向；报告包含明确标注的历史证据，不是纯 PUF3 源码包 |
| `source_af34e65.zip` | 旧源码快照（旧报告/旧路径） | 已取代，不用 |
| `source_92159b9.zip` | 当前冻结源码快照，4881 文件，SHA-256 `0ade4e66…95eb`，含多个历史证据包 | 当前源码留档；不是纯 PUF3 精简部署包，也不含 Git 历史 |

临时包 `evidence_20261101_20261031_153258` 曾含修改中的 Skill，已删除，不属于现存可选版本。
当前 HEAD 比源码冻结点多一个冻结元数据提交；本次复核又新增未提交文档，不把这些假称已在上述 ZIP 内。

## 8. 元数据中看似“混版”但应保留原件的地方

- PUF3 candidate manifest 的 hardware_validation=NOT_RUN 是**打包时**状态；真实板测存在独立 result.json 并绑定
  bit/hwh/manifest。不能直接把 manifest 改成 PASS，否则 10-31 板测记录的 manifest_sha256 会失配。
- manifest 70 项 source_sha256 中只有 **Notebook** 与当前不同；56 个选定生产输入与固件构建 12 项都匹配。
  已追溯：旧 Notebook 哈希对应 `dd0dc25` 的 CRLF 字节；与当前 Notebook 的代码差异只有
  `FULL_KAT=False → True`（另有执行输出/元数据）。这是测试程序从 6 组切到 289 组的历史演进，不是 bit 混版。
  最终报告构建锁定的正是当前 Notebook；不改旧 manifest 来消灭这一差异。
- `data/advanced/current_candidates.json` 只管理 DMA/PUF v2 **独立实验**候选，并非项目全局当前版本指针。
  全局提交包看 submission/current_evidence.json；当前主 bit 看 PUF3 candidate。

## 9. 本次执行检查的精确结果

| 检查 | 结果 | 意义 |
|---|---|---|
| PUF3 五项 bit/hwh/bin/coe/elf | 全部大小/hash 匹配 manifest | 当前候选配套 |
| 生产 RTL/固件/约束输入 | 56/56 raw 或 LF 哈希匹配 | 当前生产源与候选记录一致 |
| 固件 build.json 输入 | 12/12 匹配 | 共享旧目录不是误链接旧 main |
| PUF3 10-31 result.json | real、PQF3、pynq-svc-puf3、bit/hwh/manifest 绑定一致 | 当前报告对应这次实板 |
| 最终报告 `review_evidence.py --pdf ... --output <temp>` | **194/194 PASS** | 当前源、证据、PDF 的该脚本核对通过 |
| D02 `check_benchmark_tables.py --output <temp>` | **64/64 PASS** | 当前 PUF3 数字与配套材料的该脚本核对通过 |
| `assemble.py --check-only` | **PASS，267 件，报告构建 build_20261101_174743** | 未写新包；不是全仓脚本版本自动一致性证明 |
| 当前证据 ZIP/hash 与冻结指针 | 一致 | current_evidence 指向 18:38 包 |
| 默认 CPU runner 源列表 elaboration | **exit 4**，缺 BUFG/puf_key/key_mmio | 确认旧入口源集已漂移，不可直接当当前回归 |
| 加 pynq-p0 的源列表 elaboration | exit 0 | 只证明旧 v1 源集可展开，不是 PUF3 |
| PUF3 专用源列表 elaboration | exit 0 | 只证明 PUF3 TB 层次可展开，未重新执行 54 步 |
| 当前 ISE 单元源列表 elaboration | exit 0 | 未重跑 1502 个检查 |
| 旧 MMIO 生命周期 TB elaboration | exit 0 | 不能误称端口增加就一定编译失败；旧位置连接可留空末尾硬件 key 输入，不证明覆盖 HWKEY 场景 |
| v1 BridgeRegs + PQF3 模拟寄存器 | 明确拒绝 | 默认身份并不兼容 |
| PUF3 Notebook 身份子类 + PQF3 模拟寄存器 | 接受 | PUF3 的覆写正确 |

另纠正此前 P0 复核的广义表述：**CPU-DMA 实验已有目标 CPU 的 SW1089 + ISE1089 + HW289 仿真**，
原件 `data/advanced/dma_cpu/full_20261030_002958_293520/verified_full.json`；vendor-memory XSim 7418/7418
见 `xsim_20261030_014606_238543/verified.json`。当前 PUF3 板端仍只支持每模式 289 组；不能跨版本转记。

## 10. 现在到底用什么、不用什么

1. **主演示只用 PUF3 candidate + pynq_svc_puf + PUF3 Notebook + 10-31 result + 当前 PDF + 18:38 证据包。**
2. **Skill 单独用通用 Skill 与冻结的 L3 工件**（旧 v1、Base GPIO、非 Ascon DMA 回环），清楚标明不是 PUF3 重测。
3. 原 baseline/Kintex/PL-only/PUF-only、CPU-DMA/HW_DIRECT/PUF v2/PUF-MIN、旧报告/旧 ZIP 均不作为本次主入口，
   但保留来源、共享依赖和失败证据；PUF v2 INVALID 候选尤其不能上板。
4. 若要进一步收口，应先加一张明确的版本入口索引，并修复默认 CPU runner/过时 README；
   不要简单改共享驱动 ID、统一所有默认路径或删除旧目录，以免破坏历史复现、Skill 与 PUF3 本身的共享依赖。

本轮只审计并记录，未修改生产脚本/RTL/固件/Notebook/已发布 manifest，未重新打包、未 commit/push。

## 附：本地分支名称（不是可互换工程版本）

| 分支 | 当前指针 | 含义 |
|---|---|---|
| `main` | 35fe0a5 | 当前集成工作版本 |
| `backup/pre_remote_refresh_20261101_174818` | b748a82 | 合并远端前的本地备份，旧报告/旧板测路径 |
| `feat/board-bringup` | bd10697 | 早期领航者起板/验证接手点 |
| `feat/keys-puf` | 53eab05 | 早期 PL-only keys3 原型冻结索引 |
| `feat/pynq-overlay` | 0f5d49c | 早期 PYNQ overlay 工作点，不是 PUF3 |
| `fix/ascon-key-lifecycle` | 3c6f134 | 早期密钥生命周期/时序修复工作点，不是当前完整发布 |

未因本轮审计自动切换、合并、删除分支。

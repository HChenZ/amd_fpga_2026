# 从零复现：当前 PUF3 工程

更新：2026-11-02；任务 D08；owner TBD。

本指南按当前仓库布局编写，默认**在新克隆中操作**。先读 [README 目录说明](../README.md#仓库结构)、
[项目看板](../project_board.md)、[接口契约](design/interfaces.md)；协作约定见 [AGENTS.md](../AGENTS.md)。
不要把 `archive/history/` 的旧 CPU / DMA / PUF v2 工具当作当前入口，也不要直接照搬旧截图里的路径和状态。

## 0. 先选复现目标

| 目标 | 执行步骤 | 能证明什么 |
|---|---|---|
| 先运行已发布的 PUF3 | 1、2 中的最小环境、3、8 | 使用匹配 candidate 完成**本次**板端测试；不代表已从源码重建 |
| 从源码重建当前 PUF3 | 1～8 | 逐段验证软件、RTL、固件、实现和本次板测；必须保存自己的新结果 |
| 检查四个交付 ZIP | 1、2、9 | 包完整性、独立解包、固件 / host / Skill 与 elaboration；不运行 Vivado 或实板 |

**不是“一键全部验收通过”承诺**。既有记录证明过离线验证、固件 BIN 一致、源码包装配和一次 PUF3 板测；
完整干净机器硬件端到端复现（D05）、PUF 跨上电 / PVT / BER / 熵 / 唯一性、RO 计数器域签核等仍未闭合。
本次新增的是操作指南，不是新的硬件验收记录。

## 1. 克隆并记录版本

在空的新目录运行；若已有开发副本，另选目录克隆，不覆盖别人的改动或旧构建。

```sh
git clone https://github.com/HChenZ/amd_fpga_2026.git
cd amd_fpga_2026
git rev-parse HEAD
git status --short
```

保存 HEAD、工作区状态和后续工具版本。以下命令都从**仓库根目录**运行；失败时先查看退出码与日志，不继续“凑齐结果”。

- 完整仓库包含已发布 candidate 和原始记录归档，是本指南推荐的入口。
- [PUF3 源码 ZIP](../delivery/puf3_project.zip)只带源码 / 配置，不带可直接下载的 bit / hwh。
  其中的 `known_artifact_manifest.json` 是参考清单，不是 overlay；还应阅读包内 `source_package.md`。
- 四个冻结 ZIP 的源码版本是 `124f5c7`，身份以 [delivery/manifest.json](../delivery/manifest.json)为准。
  仓库后续文档更新不会自动改写 ZIP；不要据最新 README 推断旧 ZIP 已重新打包。

## 2. 准备环境

| 项目 | 需要的环境 | 说明 |
|---|---|---|
| 工件身份检查 | 主机 Python 3.10+、Git | 不需要 Vivado、交叉编译器或目标板 |
| Final host / 参考向量 | Python 3.10+、主机 GCC | 推荐 Linux / WSL；不是 RISC-V 编译器 |
| RTL / PUF3 elaboration 与仿真 | `iverilog`、`vvp` | 既有主机记录使用 Icarus 14.0 devel；行为模型不等于物理 PUF |
| RV32 固件 | `riscv-none-elf-gcc` 及同套 binutils | 对照工具链是 xPack GCC 15.2.0，目标 `rv32im_zicsr` / `ilp32` |
| 综合 / 实现 | Vivado **2025.2** | 器件 `xc7z020clg400-1`，top `pynq_puf3_wrapper`，不要静默升级 IP |
| host / Skill 单测、交付包校验 | `pytest`、`PyMuPDF` | PyMuPDF 只用于读取报告 PDF，不是板端运行依赖 |
| 实板 | 正点原子领航者 ZYNQ7020 + 匹配的 PYNQ 镜像 | 已测环境为 PYNQ 2.7 / Python 3.8.2；不保证其他板型 / 镜像通用 |

Linux / WSL 可先创建独立主机环境；Python / GCC / Icarus / Vivado / 交叉工具链须自行安装：

```sh
python3 -m venv .venv
source .venv/bin/activate
python -m pip install pytest PyMuPDF
python --version
gcc --version
iverilog -V
vvp -V
riscv-none-elf-gcc --version
```

Windows 也可使用原生 Python、Icarus、xPack 和 Vivado；用该 Python 执行 `python -m pip install pytest PyMuPDF`。
**Windows 和 WSL 的 Python / PATH 是两套环境**。每条命令所调用的编译器必须能从同一环境找到；
尤其 `verify_delivery.py` 内部直接调用固件构建，要求 `riscv-none-elf-gcc` 在该环境的 PATH 中。
不要依赖固件脚本中仅适用于开发机的 Windows 兜底路径。

## 3. 最小检查：当前源集、候选与共享依赖

```sh
python -X utf8 tools/verify_puf3_sources.py
```

应得到 `status: PASS`、`source_mismatches: []`、完整仓库的五项 `artifacts: MATCH`、`build_support.missing: []`。
当前门禁核对 56 项候选生产输入、7 项候选构建支持 hash，并检查共享 RO hook 与两个 XCI 路径。
它不是对所有历史工程的验证，也不比较全部 Notebook 执行输出。

装好 Icarus 后再做 PUF3 专用源集 elaboration，输出写入新的忽略目录：

```sh
python -X utf8 tools/verify_puf3_sources.py --compile --output build/local/reproduce/run_01/source_check.json
```

应有 `elaboration.exit_code: 0`。这只证明源集可以展开，**不证明 CPU 执行正确、时序满足或板测通过**。
后续重复实验把 `run_01` 换成新的目录名；不要覆盖已跟踪的 `build/metadata/` 验证快照。

## 4. Final host 与认证失败验证

推荐在 Linux / WSL 从根目录执行，`python` 指第 2 步准备的主机解释器：

```sh
python -X utf8 sim/ascon/run_validation.py --report build/local/reproduce/run_01/host_validation.json
python -X utf8 sim/ascon/check_failure_contract.py --report build/local/reproduce/run_01/failure_contract.json
python -X utf8 sim/ascon/test_harness.py
```

Windows PowerShell 若使用已安装的 Ubuntu WSL，可在同一仓库目录执行以下等价命令；
`python3` 必须能在该发行版中找到 GCC，发行版名称不同则替换 `Ubuntu`：

```powershell
wsl -d Ubuntu -- python3 -X utf8 sim/ascon/run_validation.py --report build/local/reproduce/run_01/host_validation.json
wsl -d Ubuntu -- python3 -X utf8 sim/ascon/check_failure_contract.py --report build/local/reproduce/run_01/failure_contract.json
wsl -d Ubuntu -- python3 -X utf8 sim/ascon/test_harness.py
```

- `run_validation.py` 默认检查四个 C / Python 后端，每个后端都覆盖锁定的 1,089 个官方 KAT，另有固定补充与置换测试。
  预期退出码 0、JSON 中 `summary.failed=0`；只选 Python 后端属于部分验证，不是 C 也已通过。
- `check_failure_contract.py` 检查生产 C 的认证失败、输出擦除、长度与边界保护；预期退出码 0、无失败项。
- `test_harness.py` 刻意注入错误输出、错误认证接受和 hash 错误，检查测试器确实拒绝；预期 unittest `OK`。
  子进程的预期 FAIL 是反例，不是绕过正常失败。

JSON 及同名 `.log` 写入上面指定的新目录；临时 C 库在 `build/local/ascon_kat/`。
这些是 host 结果，不能转记成 RV32 执行或实板 KAT。详细范围见 [sim/ascon/readme](../sim/ascon/readme.md)。

## 5. 独立 RTL 向量与仿真

仍在有主机 GCC 的环境先准备新向量目录，再运行 Icarus；使用与第 4 步相同的环境即可：

```sh
python -X utf8 sim/ascon/prepare_rtl_vectors.py --output build/local/reproduce/run_01/rtl_vectors
python -X utf8 sim/ascon/run_rtl_regression.py --vectors build/local/reproduce/run_01/rtl_vectors --report build/local/reproduce/run_01/rtl_regression.json
python -X utf8 sim/ascon/test_rtl_harness.py --vectors build/local/reproduce/run_01/rtl_vectors --report build/local/reproduce/run_01/rtl_harness.json
```

Windows 也可用 `wsl -d Ubuntu -- python3 ...` 准备向量，再用原生 `python ...` 运行后两条；
保持同一实际仓库 / 向量目录，不混用两套 checkout。后两条会查询 Git，需保留 `.git` 与 `origin/main` 引用。

预期三个顶层命令均退出 0，回归报告 `summary.status=PASS`，反例报告 `summary.failed=0`。
覆盖 round / P8 / P12、独立 AEAD 和 Ascon 生产源集；容量内官方 KAT 为 289 组，**不是**目标硬件已跑完整 1,089 组。
这一步不运行 PUF3 CPU 固件；其整机协同仿真在下一步。

## 6. RV32 固件与 PUF3 真实 CPU 协同仿真

在专用于复现的新克隆中，保证交叉工具链和 Icarus 位于本环境 PATH：

```sh
python -X utf8 src/firmware/pynq_svc_puf/build.py --prefix riscv-none-elf-gcc
python -X utf8 sim/pynq_puf3/run.py
```

`--prefix` 可填写本机 **gcc 可执行文件的完整路径**，不是单纯工具链目录。
构建默认输出 `build/local/pynq_svc_puf/` 的 ELF / BIN / HEX / COE / 反汇编 / `build.json`；
`build.json` 记录编译器、flags、输入 hash 与 custom-0 指令检查。后续仿真和 Vivado 使用这个默认输出位置。

仿真默认输出 `build/local/pynq_puf3/sim/`，预期总退出码 0、`summary.json` 中：

```text
result = PASS
normal_pass = true
mutant_autolock_detected = true
```

正常用例应通过；自动锁钥的历史 RTL 反例应被检测为非零退出，不能把它改成正常路径。
这一步使用真实 RV32 固件与 AXI / UART，但 RO / DNA / BRAM 等含行为模型，不证明物理 PUF 可靠性。

**停止条件**：固件构建或任一协同仿真门禁不通过，不继续 Vivado / 发布。
COE 是构建时 BRAM 初值；只替换 ELF / BIN 不会更新已有 bitstream。

## 7. Vivado 2025.2 从源码综合、实现与新候选

仅在第 6 步通过、工具版本匹配后，从同一新克隆运行：

```sh
vivado -mode batch -source board/vivado_zynq7000_xc7z020_pynq_puf3/build.tcl -notrace -tclargs Performance_ExtraTimingOpt 4
```

脚本自动创建 `pynq_puf3_wrapper` / `xc7z020clg400-1` 工程；不要另开旧 XPR 或把所有 RTL 一次性导入。
它会换入 board-local `soc_top.v` / `key_mmio.v`，导入保留的 Ascon XCI，并读取共享 RO hook。
已存在同名 `build/local/pynq_puf3/vivado/pynq_puf3.xpr` 时会拒绝覆盖：另用新克隆，不盲删旧构建。

输出 bit / hwh 位于 `build/local/pynq_puf3/vivado/`，报告位于其 `reports/`。
预期脚本退出 0 并输出 `PYNQ_PUF3_BUILD_PASS`；核对 setup / hold、DRC、PS 引脚和 RO 结构门禁，
不能只看“bit 已生成”。历史候选的 WNS +0.104 ns 不是新实现必须逐位重现的数值。

再对**本次** post-route checkpoint 进行 RO 分析：

```sh
vivado -mode batch -source board/vivado_zynq7000_xc7z020_pynq_puf3/ro_corner_sta.tcl -notrace -tclargs build/local/pynq_puf3/vivado/pynq_puf3.runs/impl_1/pynq_puf3_wrapper_postroute_physopt.dcp build/local/pynq_puf3/ro_sta
```

`RO_CORNER_STA_DONE` 只表示完成分析，**不表示 RO 计数器时序通过**；当前设计此域未签核，必须保留限制。

### 可选：将新工件组装为供 Notebook 使用的候选

**发布脚本会替换 `board/.../candidate/`。不要在保留交付物的工作区直接运行。**
仅在这个专用重建克隆中，先保存随 Git 提供的候选；已有同名备份时下面命令会停止，不覆盖：

```sh
python -c "import shutil; from pathlib import Path; p=Path('build/local/reproduce/published_candidate'); p.parent.mkdir(parents=True, exist_ok=True); shutil.copytree('board/vivado_zynq7000_xc7z020_pynq_puf3/candidate', p)"
python -X utf8 board/vivado_zynq7000_xc7z020_pynq_puf3/package.py
```

脚本会检查新实现门禁、54 步协同仿真及反例、固件 BIN / COE / MIF 一致性和 RO 分析对应的 DCP。
成功应输出 `PYNQ_PUF3_PACKAGE_PASS`；还必须执行下一步取得本次板测，不允许把旧板测结果绑定到新 bit。
若只是验证源码可构建，可停在分析完成，不运行发布脚本。

## 8. 在匹配的 PYNQ 板端运行 Notebook

1. 准备已验证板型和匹配镜像，确认能进入有 Overlay / MMIO 权限的板端 Jupyter。
   板卡资料见 [board/atk_navigator_7020](../board/atk_navigator_7020/)；镜像准备不是“在普通 PC 上 pip 安装 PYNQ”。
2. 将完整仓库放到板端 `/home/xilinx/jupyter_notebooks/amd_fpga_2026`。先跑现成候选时直接使用仓库 candidate；
   测新构建时传递**同一套**新 candidate、源码、manifest，使用独立板端目录，不混用新 bit 和旧 hwh / 固件。
3. 用 Jupyter 的复制 / 另存功能将 [PUF3 Notebook](../src/pynq_puf3/pynq_puf3_board_test.ipynb)
   放到新建的 `build/local/reproduce/run_01/` 后执行，保留原已执行 Notebook。
   仓库不在默认位置时，在新副本第一格之前设置 `os.environ['ASCON_REPO']` 为实际路径；不要绕过身份 / hash 检查。
4. Restart Kernel，顺序 Run All。默认 `FULL_KAT=True`、`WARMUP=5`、`REPETITIONS=30`、`KAT_COUNT=529`。
5. 检查四段结果：身份 / 时钟、SW / HW / ISE 各 289 KAT 与坏 Tag 拒绝、基准、PUF 会话内流程。
   控制身份须为 `PQF3=0x33465150`，固件为 `pynq-svc-puf3`。原 PYNQ 读数显示 150 MHz 不作为真实频率判定，
   使用 Notebook 的 SLCR 推算和 mcycle / PS 时间交叉检查，不手工改分频“修正显示”。
6. 本次输出自动保存至新的 `data/pynq_puf3/notebook_<时间>/result.json` 和 `mailbox_log.txt`。
   核对整体状态 / 退出码、工件绑定、各段与实际采样，下载保存原件；不要覆盖 10-31 主采样。

只跑旧 `src/pynq/board_demo.py` / `board_benchmark.py` / `board_error_gate.py` 不等于运行 PUF3；
这些兼容入口仍绑定旧 v1 身份。基准比较 CPU `mcycle`，PS 墙钟另列；PUF 功能不外推成跨上电或保密性验收。
详细板端限制见 [Notebook 说明](../src/pynq_puf3/readme.md)与 [PUF3 工程说明](../board/vivado_zynq7000_xc7z020_pynq_puf3/readme.md)。

## 9. 可选：主机 / Skill 单测与四包校验

在完整新克隆中，host 的一项样本追溯测试需要历史周期 fixture，先从归档恢复本机忽略副本，再执行：

```sh
python -X utf8 tools/restore_records.py
python -m pytest -q -p no:cacheprovider
```

恢复工具不测量硬件；已有不同字节时拒绝覆盖。冻结时的离线基线为 **122 passed / 3 skipped**，
其中 3 项是依赖另一个工程实物工件的可选 Skill 测试。Skip 不等于新的实板 PASS。
只测独立 Skill 可直接运行 `python -m pytest skill/pynq-overlay-workflow/tests -q -p no:cacheprovider`，无需恢复原件。

有第 2 步列出的 pytest / PyMuPDF / Icarus / 交叉工具链后，校验正式四个 ZIP：

```sh
python -X utf8 tools/verify_delivery.py --output build/local/reproduce/run_01/delivery_check.json
```

它在仓库外解包，校验 ZIP / 成员 hash、主机与独立 Skill、固件重编译 BIN 和 elaboration；
不执行综合 / 实现或真实板测。BIN 对照要求匹配既有工具链；不一致时调查编译器 / flags / 源码，不伪造 hash。
**不要用 `package_delivery.py` 代替校验：它会重写四个 ZIP 与清单；本次只增文档，不修改冻结交付。**

## 完成后留下什么

保存本次 HEAD / dirty 状态、工具版本、所有退出码、日志 / JSON、新工件 hash，以及仍未测的项目。
将“通过 host / RTL / 固件 / 实现 / 实板”的范围分别记录；任一层失败都保留原件与原因。
不要把静态 elaboration、历史结果或截图当作完整端到端复现证据，也不把 D05 自动标成 done。

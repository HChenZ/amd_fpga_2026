# RISC-V轻量密码加速SoC

全国大学生嵌入式芯片与系统设计竞赛2026，FPGA创新设计赛道，AMD自主选题初级组。
平台为正点原子领航者ZYNQ7020（XC7Z020CLG400-1）。本包以 `delivery_manifest.json` 记录的 Git 提交为源码版本，包含当前 PUF3 工程、配套已验证候选、85页最新技术报告和独立 PYNQ Skill。
这是材料装配与完整性校验，**没有重新综合、生成bitstream或进行新的实板测试**。

## 1. 系统与创新点

RV32五级流水CPU在PL内执行标准NIST SP 800-232 Ascon-AEAD128，提供软件、MMIO硬件加速、P8/P12定制指令（ISE）三条路径。PS侧PYNQ通过AXI-Lite控制窗口和FIFO/UART mailbox与CPU协同；使用 `mcycle` 比较相同输入的CPU周期。
同一PUF3 overlay集成RO-PUF/Device DNA密钥通路，展示会话内注册、重建和HWKEY切换。

- 密码加速：用RISC-V定制指令降低置换热点开销，与软件/MMIO在同一平台比较。
- 软硬件协同：Notebook编排身份检查、黄金比对、负例、基准与结果采集；通用Skill支持工件校验、寄存器契约、DMA有界等待和报告。
- 器件绑定密钥原型：结合RO物理响应与DNA展示派生密钥通路；不作生产级密钥保密或安全启动声明。

## 2. 目录

```text
RISC-V轻量密码加速SoC/
├── README.md / LICENSE
├── delivery_manifest.json         # 源提交、来源映射、共享依赖和范围
├── SHA256SUMS.txt                 # 除自身外全部文件的SHA-256
├── verify_checksums.py            # 不依赖第三方包的完整性校验
├── code/                         # 内部层级保持原工程结构
│   ├── README.md / AGENTS.md / LICENSE
│   ├── src/                      # CPU/Ascon/PUF、固件、PYNQ驱动与Notebook
│   ├── board/                    # PUF3 Tcl/变体RTL/candidate及必要IP/板卡支持
│   ├── sim/ / ascon/ / build/ / data/ / tools/
│   └── report/design/            # 接口、架构、标准、指令与密钥约定
├── technical_report/
│   ├── final_report.pdf          # 最新85页；长命令排版修复后版本
│   ├── README.md
│   └── latex/                    # 正式报告包原样提取的编辑源、图件和编译脚本
└── skill/
    ├── pynq-overlay-workflow/     # 可独立安装，含许可证
    └── pynq_overlay_workflow_skill.zip
```

先打开 [技术报告](technical_report/final_report.pdf)，再看 [代码说明](code/README.md) 和 [完整性清单](delivery_manifest.json)。
`code/` 是原脚本所说的“仓库根目录”；所有 `src/`、`board/`、`build/` 等相对路径以它为基准。
建议把整个 `code/` 复制到无中文、无空格的短路径（如 `E:/fpga/puf3`），再使用Vivado；其内部层级不能拆散。

## 3. 环境

| 用途 | 环境 |
|---|---|
| 静态/host验证 | Python 3.10+、Git、主机GCC；主机测试推荐Linux/WSL |
| RTL展开/仿真 | Icarus `iverilog`/`vvp`；既有记录为14.0 devel |
| RV32固件 | xPack RISC-V GCC 15.2.0及配套binutils；`rv32im_zicsr`、`ilp32` |
| FPGA重建 | Vivado **2025.2**、`xc7z020clg400-1`、top=`pynq_puf3_wrapper` |
| 板端 | 匹配领航者ZYNQ7020的PYNQ镜像；既有实测PYNQ2.7.0、Python3.8.2、Linux5.4.0-xilinx-v2020.2 |
| 单测 | pytest；Skill工具本身用Python3.8+标准库，板端另需pynq |
| 报告编译 | XeLaTeX/latexmk或Tectonic0.15.0，ctex/Fandol及DejaVu Sans Mono字体；PDF读取用PyMuPDF |

工具链、Vivado、PYNQ镜像、TeX发行版不随包分发。Windows与WSL的Python/PATH相互独立。
原源码中的历史开发机兜底路径和原始报告里的路径只作来源记录；本README命令使用PATH或明确指定工具链，不依赖那些个人目录。

## 4. 快速开始与复现

以下检查不会下载硬件。先在本包根目录运行：

```sh
python -B verify_checksums.py
cd code
python -B -X utf8 tools/verify_puf3_sources.py
python -B -X utf8 tools/verify_puf3_sources.py --compile --output build/local/reproduce/run_01/source_check.json
python -B -m unittest discover -s src/pynq -p "test_*.py"
```

预期源集PASS、candidate工件MATCH、共享依赖无缺失；`--compile`另需Icarus且展开退出0。
展开不是功能仿真，更不是实板验收。主机单测使用模拟后端，保留了其依赖的六份历史周期fixture，不能当成当前PUF3性能。

部分原脚本查询Git的HEAD及origin/main。RAR按要求不含`.git`；在需要完整host/RTL验证或Vivado重建时，先在**解压后的code目录**建立本地来源记录：

```sh
git init -b main
git add .
git -c user.name="Local Reproduction" -c user.email="reproduction@example.invalid" commit -m "Local extracted source snapshot"
git update-ref refs/remotes/origin/main HEAD
```

这是本地快照，**不是原上游提交**，也不连接或写入远程仓库；原上游SHA仍以包内manifest为准。随后从 `code/` 运行：

```sh
python -B -X utf8 sim/ascon/run_validation.py --report build/local/reproduce/run_01/host_validation.json
python -B -X utf8 sim/ascon/check_failure_contract.py --report build/local/reproduce/run_01/failure_contract.json
python -B -X utf8 sim/ascon/test_harness.py
python -B -X utf8 sim/ascon/prepare_rtl_vectors.py --output build/local/reproduce/run_01/rtl_vectors
python -B -X utf8 sim/ascon/run_rtl_regression.py --vectors build/local/reproduce/run_01/rtl_vectors --report build/local/reproduce/run_01/rtl_regression.json
python -B -X utf8 sim/ascon/test_rtl_harness.py --vectors build/local/reproduce/run_01/rtl_vectors --report build/local/reproduce/run_01/rtl_harness.json
```

GCC、Icarus须在同一环境PATH中；Windows设置 `PYTHONUTF8=1`（PowerShell：`$env:PYTHONUTF8='1'`）后再运行。
输出写到新目录；失败时停止，不覆盖已归档结果。原件校验所需的官方KAT、参考实现和来源哈希已包含，无需旧证据ZIP或restore_records。

### 固件与Vivado（用户自行复现时执行）

从 `code/`：

```sh
python -B -X utf8 src/firmware/pynq_svc_puf/build.py --prefix riscv-none-elf-gcc
python -B -X utf8 sim/pynq_puf3/run.py
vivado -mode batch -source board/vivado_zynq7000_xc7z020_pynq_puf3/build.tcl -notrace -tclargs Performance_ExtraTimingOpt 4
```

固件输出 `build/local/pynq_svc_puf/`；协同仿真应有normal通过且mutant_autolock反例被检出。
Vivado脚本创建工程并综合/实现，输出 `build/local/pynq_puf3/vivado/`；已有同名工程会拒绝覆盖。
PUF3使用board目录中的soc_top/key_mmio变体，不能将所有RTL递归加入工程；保留的两项XCI及ascon_keys.coe来自共享Ascon目录。
构建脚本读取共享RO hook，必须通过setup/hold、DRC和RO结构等门禁；新bit不保证与已有candidate逐位一致。
不要执行 `board/vivado_zynq7000_xc7z020_pynq_puf3/package.py` 覆盖已验证candidate；新实验请在独立副本中保存新工件和新结果。
本次打包未运行上述固件重编、联合仿真或Vivado。

### 加载已有bitstream与Jupyter

1. 使用与领航者ZYNQ7020匹配的PYNQ2.7镜像；镜像不在包内，既有采样未记录镜像hash。不能用其他板型镜像代替。
2. 把整个 `code/` 放到板端，例如 `/home/xilinx/jupyter_notebooks/amd_fpga_2026`。核对candidate下 `sha256sums.txt`（Linux可在candidate目录执行 `sha256sum -c sha256sums.txt`）。
3. 用Jupyter复制 `src/pynq_puf3/pynq_puf3_board_test.ipynb` 到新的运行副本，保留原已执行Notebook。
4. 路径不同则在副本最前面添加并执行：

```python
import os
os.environ['ASCON_REPO'] = '/home/xilinx/jupyter_notebooks/amd_fpga_2026'
```

5. Restart Kernel、Run All。Notebook会检查配套bit/hwh/manifest并用PYNQ加载已有overlay；身份须为 `PQF3=0x33465150` / `pynq-svc-puf3`。默认FULL_KAT=True、WARMUP=5、REPETITIONS=30。
6. 检查身份/时钟、三模式KAT与坏Tag、benchmark、PUF会话流程，保存新生成的 `data/pynq_puf3/notebook_<时间>/`，不覆盖10-31主采样。

Notebook会改变PL状态，板卡同一时刻只由一个进程控制。默认PYNQ时钟读数的晶振假设不适用于本板，使用Notebook已有SLCR和mcycle校验，不手动调整分频绕过门禁。
公共 `src/pynq/` 中旧v1 CLI、旧Notebook为共享API单测兼容支持，**不能代替上述PUF3入口**。

## 5. 已有性能与验证结果

唯一当前主采样：[result.json](code/data/pynq_puf3/notebook_20261031_114512/result.json)，对应 [candidate manifest](code/board/vivado_zynq7000_xc7z020_pynq_puf3/candidate/manifest.json)。
报告完整说明见 [final_report.pdf](technical_report/final_report.pdf)。

| 当前板级实测 | 软件SW | MMIO/HW | ISE |
|---|---:|---:|---:|
| 加密周期中位数 | 21862 | 1369 | 3895 |
| 解密周期中位数 | 22562 | 1213 | 4288 |
| 加密相对SW加速比 | 1 | 15.969 | 5.613 |
| 解密相对SW加速比 | 1 | 18.600 | 5.262 |

条件：KAT#529，PT16B/AD0，HWKEY关闭，预热5、采样30；CPU周期不含PS/UART，墙钟另列，墙钟原始数组未归档。
三模式分别289/289容量内KAT及289次坏Tag拒绝；PUF只有同会话127/128有效位、重建5/5和HWKEY功能证据。
Vivado原报告（不是新板测）：LUT18674、FF32002、BRAM34.5、DSP4；已约束路径WNS+0.104ns，DRC0 Error/0 Critical；RO计数器域未签核。
host官方KAT覆盖1,089组；报告记录四后端28,661/0、认证失败契约23,965/0。这些是已有主机验证，不等同板上支持超16B。
`code/data/ascon/results/key_lifecycle/` 六份fixture仅为历史仿真样本；旧PL-only、v1 release和Skill L3结果均不转记为当前PUF3。

## 6. 独立Skill

完整安装目录：[pynq-overlay-workflow](skill/pynq-overlay-workflow/README.md)，另有 [独立ZIP](skill/pynq_overlay_workflow_skill.zip)。
将完整目录复制到所用Agent支持的skills目录；Codex通常为用户目录下 `.codex/skills/pynq-overlay-workflow/`。保留SKILL.md/scripts/references/examples/tests/LICENSE。
在支持技能的Agent中调用 `pynq-overlay-workflow`，提供bit/hwh、manifest、寄存器契约和目标操作；工具不会自动知道PUF3的寄存器语义。
不安装Agent也可独立运行：

```sh
cd skill/pynq-overlay-workflow
python -B scripts/pynq_skill_cli.py --help
python -B scripts/pynq_skill_cli.py gen examples/axi_gpio.contract.json -o generated_gpio
python -B -m pytest tests -q -p no:cacheprovider
```

这些命令从**本包根目录**开始；若当前位于code，先 `cd ..`。测试需要pytest；CLI生成文件写入新目录，Skill原API/测试未改。
独立环境中依赖另一工程实物工件的3项可选测试会skip，不能把skip视为板测通过。

## 7. 技术报告源码与已知限制

PDF和latex均取自同一最新版正式报告包；SHA可用根目录校验工具检查。编译入口与依赖见 [报告说明](technical_report/README.md)。

- 当前板端PT/AD各≤16B；host长消息通过不代表硬件具备通用多块能力。
- PUF跨上电、温压/PVT、BER、熵、唯一性和长期稳定性未验收；诊断量可读，不能声称完整保密隔离或量产密钥安全。
- RO计数器时序未签核；已约束路径通过不能代替RO域签核。
- 当前PUF3完整错误矩阵、完整RV64/异常抢占、小时级稳定性等未完成；不把旧v1的9/9错误门禁移用。
- 未完成由第三方在干净环境从Vivado到实板的全流程复现；本包测试只证明记录的装配、身份与轻量检查范围。
- 原维护文档中的archive/delivery旧包及完整报告证据复核依赖完整Git仓库；本包不伪装为整仓副本。当前可执行入口以本README为准。

源仓库：https://github.com/HChenZ/amd_fpga_2026 。许可证及第三方文件头按原样保留；无须真实用户密钥。

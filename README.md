# RISC-V Ascon SoC — PUF3

当前工程采用 RV32 五级流水线 CPU，集成 Ascon-AEAD128 的软件、MMIO、定制指令三条路径，
并在同一 PUF3 overlay 中提供 RO-PUF/Device DNA 密钥通路。本文只描述架构与已验证结果，不作未经核实的独占原创或安全性声明。

## 三分钟找到项目

| 想了解什么 | 入口 |
|---|---|
| **项目总看板、当前/历史与交付清单** | [项目看板](project_board.md) |
| 第一次接手，从克隆到验证、重建与上板 | [从零复现指南](report/reproduce_from_zero.md) |
| 当前 PUF3 工程 | [board 工程入口](board/readme.md) |
| 板上操作 | [PUF3 Notebook](src/pynq_puf3/readme.md) |
| 当前源码/构建依赖 | [源码说明](src/readme.md)、[构建说明](build/readme.md) |
| 独立 Skill | [Skill](skill/readme.md) |
| 技术报告、海报与材料状态 | [材料入口](report/readme.md) |
| 独立历史工程 | [archive/history](archive/history/README.md) |
| 原始测试/实现证据 | [archive/evidence](archive/evidence/README.md) |
| 三类交付的分别压缩 | [delivery](delivery/README.md) |

当前目录只放 PUF3、其共享依赖和维护文档；独立 DMA/PUF v2/MIN、原型和旧工具集中隔离。
历史源码的旧相对路径属于当时布局，不应直接当成当前构建命令；物理原件与 Git 历史保留，不改写失败为通过。

## 仓库结构

仅列主要维护入口；Vivado 缓存、临时构建和本机恢复副本不在下列交付结构中。

```text
amd_fpga_2026/
├── README.md                       # 项目简介与导航
├── project_board.md                # 总看板：当前工程、交付物、证据和未测边界
├── board/                          # 当前板级工程与真实依赖
│   ├── vivado_zynq7000_xc7z020_pynq_puf3/  # PUF3 Tcl、变体 RTL、已验证 candidate
│   ├── vivado_zynq7000_xc7z020_ascon/      # PUF3 复用的 XCI / 存储初始化配置来源
│   └── atk_navigator_7020/                # 板卡资料与引脚说明
├── src/                            # 当前工程源码与共享支持
│   ├── rtl/                        # RV32 CPU、Ascon、PUF v1 与 PYNQ 桥
│   ├── firmware/                   # pynq_svc_puf 主固件及必要共享依赖
│   ├── pynq/                       # 公共 Python API / 协议；含保留的旧 v1 兼容入口
│   └── pynq_puf3/                  # 当前完整板测 Notebook
├── ascon/                          # C / Python 算法实现及说明
├── sim/                            # Final host、独立 RTL、PUF3 协同仿真
├── build/                          # 共享 RO 约束 / hook、精选校验元数据
├── data/                           # 锁定 KAT / 向量、分版本的原始板测
├── tools/                          # 源码打包、独立解包校验、原件恢复工具
├── skill/pynq-overlay-workflow/     # 可独立安装的 Skill、示例与测试
├── report/                         # 设计报告 + 大模型协作记录
│   ├── technical/                  # 技术报告 PDF（可编辑 LaTeX 另见 delivery/technical_report.zip）
│   ├── llm_collab/                 # 大模型协作原始会话：提示词、回答、自我纠错轨迹
│   ├── design/                     # 架构、接口、版本入口和工程约定
│   ├── reproduce_from_zero.md      # 环境准备 → 离线验证 → 固件 / Vivado → 上板
│   └── poster/                     # 双语海报；另有演示脚本 demo_video_script.md
├── image/pynq/                     # 已保留的 PYNQ / Skill 界面截图，辅助展示
├── tasks/                          # 任务看板与阶段交付计划
├── project_log/                    # 实际进度、开发记录、踩坑与失败
├── archive/
│   ├── history/                    # 隔离的独立历史工程和源码，不参与当前默认构建
│   └── evidence/                   # 原始日志 / 报告 / 历史快照的可校验归档
├── delivery/                       # 当前源码、历史源码、Skill、技术报告四个独立 ZIP
└── submission/                     # 旧提交流程说明；当前下载入口是 delivery/
```

### 与比赛推荐目录的对照

赛题 3.3.5.4 推荐 `README.md / src / sim / build / board / data / skill / report` 八项，本仓库全部采用；
其余目录为补充，对照如下：

| 推荐项 | 本仓库位置 | 说明 |
|---|---|---|
| README.md | `README.md` | 项目简介、复现入口；完整步骤见 `report/reproduce_from_zero.md` |
| src/ | `src/`、`ascon/` | RTL / 固件 / PS 侧 Python；`ascon/` 是 C / Python 算法参考实现 |
| sim/ | `sim/` | Final host、独立 RTL、PUF3 协同仿真脚本与结果 |
| build/ | `build/`、PUF3 工程目录 | `build/` 放共享 RO 约束 / hook 与校验元数据；PUF3 的 `build.tcl` 和综合/实现报告（`candidate/reports/`）在 `board/vivado_zynq7000_xc7z020_pynq_puf3/` |
| board/ | `board/` | 上板工程、Notebook 运行入口（`src/pynq_puf3/`）与已验证 candidate |
| data/ | `data/` | KAT / 向量与分版本原始板测 |
| skill/ | `skill/` | 独立 Skill 与 README |
| report/ | `report/` | 设计报告（`technical/`、`design/`）+ 大模型协作记录（`llm_collab/`） |
| — | `tools/` | 源码打包、解包校验、原件恢复脚本 |
| — | `tasks/`、`project_log/` | 任务看板、实际进度、开发记录与踩坑 |
| — | `archive/` | 隔离的历史工程（`history/`）与原始记录归档（`evidence/`） |
| — | `delivery/`、`submission/` | 四个独立交付 ZIP；旧提交流程说明 |
| — | `image/` | 界面截图 |

2026-11-02 起原 `docs/` 已并入 `report/`：`docs/tech_report/` → `report/technical/`，其余说明 → `report/design/`，
`docs/reproduce_from_zero.md` → `report/reproduce_from_zero.md`。历史日志、任务看板旧条目、旧提交流程、原始记录和此前生成的 ZIP
仍保留旧路径；其中此前已隔离的 `docs/<name>.md` / `docs/tech_report/<旧流水线>` 在 `archive/history/docs/` 下。

**依赖不要误删：**PUF3 仍使用 `src/firmware/pynq_svc/`、`src/firmware/ascon_hw_rv32/`、
公共 `src/pynq/` 和保留的 Ascon 工程 IP 配置；名称较旧不等于无用。
PUF3 的 `soc_top.v` / `key_mmio.v` 用 `board/` 下变体，不是把所有 RTL 递归加入 Vivado。

## 从零复现入口

先在新的工作目录克隆，记录版本；不要在已有工作区执行强制同步或覆盖候选。

```sh
git clone https://github.com/HChenZ/amd_fpga_2026.git
cd amd_fpga_2026
git rev-parse HEAD
git status --short
```

按[从零复现指南](report/reproduce_from_zero.md)选择：

- **先验证现成候选：**检查源码 / 工件身份 → 在匹配的 PYNQ 板端执行 Notebook。
- **从源码重建：**环境准备 → Final host / RTL 验证 → 固件 → PUF3 协同仿真 → Vivado → 新候选上板。

每步的依赖、命令、输出位置和停止条件均在指南中。离线 PASS 不等于实板 PASS；
完整干净机器硬件端到端复现和 PUF 未测项目仍保留边界，不因新增教程而改成通过。

## 当前版本身份与实测范围

- 器件：正点原子领航者 ZYNQ7020，`xc7z020clg400-1`；Vivado 2025.2；top `pynq_puf3_wrapper`。
- 控制身份 **PQF3=0x33465150**，固件 **pynq-svc-puf3**；bit/hwh/固件配套位于 PUF3 candidate。
- 主采样：`data/pynq_puf3/notebook_20261031_114512/result.json`，三模式各289/289 KAT与289次坏Tag拒绝。
- KAT #529，PT16B/AD0，HWKEY关闭，预热5次/采样30次：加密 **21862/1369/3895 cycles**，HW/ISE为 **15.969×/5.613×**；
  解密22562/1213/4288，**18.600×/5.262×**。CPU周期不含PS/UART，墙钟另列。
- LUT18674/FF32002/BRAM34.5/DSP4；已约束路径WNS+0.104 ns，DRC0 Error/0 Critical；**RO计数器域未签核**。
- PUF只有会话内注册127/128、重建5/5、HWKEY切换与KAT恢复证据；跨上电/PVT/BER/熵/唯一性未测，诊断量可读。
- 旧v1的9/9错误门禁与Skill L3 Ascon不是PUF3完整错误矩阵；完整RV64/异常抢占、clean-clone等不冒充已验收。

交付为源码/Skill/报告，不再生成“证据包”作为比赛附件；仓库仍保存可追溯的原始记录归档。
源码、物理工件、历史记录、说明与交付ZIP的版本各自独立，以看板及交付清单定位。

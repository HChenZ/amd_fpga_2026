# 项目总看板

第一次接手先看 [README 目录说明](README.md#仓库结构) 和 [从零复现指南](report/reproduce_from_zero.md)。

## 先看这三项

| 交付类别 | 当前内容 | 仓库入口 | 独立交付 |
|---|---|---|---|
| **工程源码** | 当前PUF3及其依赖，与独立历史源码分开 | [当前工程](board/readme.md)、[历史工程](archive/history/README.md) | puf3_project.zip、historical_projects.zip |
| **Skill** | 通用pynq-overlay-workflow，独立于工程 | [Skill说明](skill/readme.md) | pynq_overlay_workflow_skill.zip |
| **技术报告** | 当前PDF与可编辑LaTeX源、大模型协作记录、设计说明，另保留双语海报 | [报告与材料](report/readme.md)、[协作记录](report/llm_collab/index.md) | technical_report.zip |

交付ZIP与SHA-256以 [delivery清单](delivery/README.md) 为准。交付不使用旧“证据包”作为附件；
仓库原始测试/实现资料仍在 [证据归档](archive/evidence/README.md) 中，不能把归档视为新测量。

## 当前PUF3究竟是什么

- RV32五级流水线CPU，Ascon-AEAD128软件/MMIO/ISE三模式，另集成PUF v1/DNA密钥通路。
- top=pynq_puf3_wrapper，器件xc7z020clg400-1，Vivado2025.2，控制ID PQF3=0x33465150，固件pynq-svc-puf3。
- 板端入口：[PUF3 Notebook说明](src/pynq_puf3/readme.md)，不要使用旧v1 CLI替代。
- 主采样：[10-31板测](data/pynq_puf3/notebook_20261031_114512/result.json)。三模式各289 KAT和289坏Tag拒绝。
- #529、PT16/AD0、HWKEY关、预热5/采样30：加密21862/1369/3895 cycles，15.969×/5.613×；
  解密22562/1213/4288，18.600×/5.262×。PS墙钟不参与加速比。
- 只有会话内PUF功能，RO计数器域未签核、跨上电/PVT/BER等未测，诊断量可读。

## 状态与边界

| 项目 | 状态 |
|---|---|
| 当前三模式功能、容量内KAT、benchmark、PUF会话内流程 | 已有原件与已验证candidate，不因整理新增硬件PASS |
| 当前实现 | LUT18674/FF32002/BRAM34.5/DSP4；已约束路径WNS+0.104；RO未签核 |
| 当前代码整理 | 只隔离历史、补导航/打包与元数据；当前RTL/固件算法不改 |
| Skill | 工具/示例独立；既有L3 Ascon是旧v1，不转记PUF3 |
| 报告/海报 | 当前报告另包交付，双语PUF3海报已从远端合并保留 |
| 仍未关闭 | PUF3完整错误矩阵、完整RV64/异常抢占、clean-clone硬件端到端、PUF环境可靠性；实机视频未归档 |

## 本次交付整理验证（不是新板测）

- 当前56项生产输入、7项候选构建支持hash与已验证candidate一致，额外检查共享hook/XCI路径齐全；五项现成工件hash未变。
- 当前源码包解压到仓库外：elaboration通过，主机61项测试通过；重新编译固件BIN与原candidate完全相同。
- Skill独立解包：61 passed/3个工程实物工件相关可选测试skip，安装不依赖本工程。
- 当前报告已重新编译，77页，性能数据保持PUF3；CPU措辞中的内部编号不再出现在报告文本/交付源码。
- 原始证据和Git历史不篡改，保留当时标识。具体ZIP/member/hash及验证范围见delivery/manifest.json和build/metadata/source_delivery_check.json。
- 讲解网页在历史日志中有记录，但当前工作区/已有备份未找到原件，不列入交付；待原制作会话补交，不重造内容冒充保留。

详细任务与历史状态见 [任务看板](tasks/task_board.md)。任务状态、已测试子项、原始FAIL与未测范围分开，不靠整理改成全绿。

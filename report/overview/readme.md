# 作品全貌图

任务 D03（报名全貌图子项），owner TBD，2026-11-02。

交付：`ascon_soc_overview.png`，1920×1080、16:9、RGB PNG、约 0.8 MB，适合报名系统上传。
新排版使用浅色蓝紫配色、开发板实拍、简化架构、三项特点和六项结果；未复制整张旧海报。
原海报、技术报告、RTL、固件和原始板测证据均未修改，接口无变化。

## 使用素材与取舍

| 素材 | 用法 |
| --- | --- |
| `docs/tech_report/figs/board_photo.jpg` | 左侧开发板实拍，裁去多余桌面，保持比例，无生成式替换。照片不证明当前镜像身份。 |
| `image/pynq/PixPin_2026-10-30_22-46-53.png` | 裁取真实 Notebook 的 kat / benchmark / puf 三项 PASS 输出；截图为 10-30 历史运行，仅示意交互界面，不作为 10-31 数值来源。 |
| `report/poster/ascon_soc_poster.png`、`ascon_soc_poster_en.png` | 已检查现有双语海报；复用其架构语义、创新说明和最新 PUF3 数据口径，未直接拼贴整张海报。 |
| `docs/tech_report/figs/fig_2_1.tex`、`docs/tech_report/report.md` §2.1–2.3、`docs/interfaces.md` | 以现有总体框图和接口约定简化重绘 PS/PL、五级 RV32、SW/MMIO/ISE。PUF3 单列为独立变体，其自身 overlay 已集成密钥通路，不表示 PYNQ release ABI 已集成。 |
| `data/pynq_puf3/notebook_20261031_114512/result.json` | 唯一数值来源，实板 `physical_board_pynq_puf3`，非仿真；原始记录时间 2026-10-31T11:45:13.863864+00:00。 |
| `data/skill/l3_20261031_063709/40_summary.json`、`report/poster/readme.md` | 通用 Skill 已有实现和 L3 实板功能证据；不宣称任意板卡均可直接复用。 |

## 数据复核与报告版本差异

三模式各 289/289 容量内 KAT；PT/AD 各 0–16 B。固定 KAT #529、PT=16 B、AD=0、
HWKEY 关闭，预热 5 次，每模式 30 次加密采样中位数为 SW 21,862、MMIO 1,369、ISE 3,895 cycles。
由原始采样重算：21862/1369 = 15.969×、21862/3895 = 5.613×（三位小数）。
范围是固件 AEAD CPU mcycle，不含 PS/UART；不是整机端到端调用加速，也不是硬件密钥模式加速比。
PUF `reconstructs_stable=5`，只支持同次上电会话内功能结论。

**现有报告并未全部与最新海报同步。** `report.md` / 报告 README 仍描述 PYNQ release
23,342/1,439/3,995 cycles 与 16.221×/5.843×；实际渲染检查的 `技术报告_提交版.pdf`
摘要还包含更早 PL-only 的 20,806/688/2,570 cycles 和 30.24×/8.10×。
它们与本图的 PUF3 是不同版本，不混算、不声称数字一致。本次优先采用用户指定且已获原始 JSON 支持的最新海报数据。
下一接收 D06 应统一最终报告的版本说明；本任务不修改或重建报告生成物。

PUF 跨上电、温度、BER、熵、唯一性未测；密钥保密隔离及 RO 域时序未验收。
三模式和板级实测完成不表示整个项目冻结门禁已全部通过。

## 验证与交接

- Python 3.14.3 / Pillow 12.2.0，2 倍画布绘制后降采样；原始 JSON 断言、30 次原始周期中位数与加速比复算、68 段文字画布边界/关键区域宽度检查，以及 PNG 格式/1920×1080/小于 10 MB 检查均通过，生成命令 exit 0。
- 命令：`python -X utf8 build/tmp/project_overview_20261102/render_overview.py`。
- 临时生成脚本及验证 JSON 在上述本地 ignored 目录；交付目录只保留 PNG 与本说明。
- 已逐块视觉检查实拍比例、架构关系、字体、数值和缩略截图；只输出一张最终全貌图 PNG。
- 本次为素材复用与排版，未重新执行板测、RTL 或 Vivado；报名系统实际上传/压缩效果未验证，无图片制作阻塞。
- D03 此子项完成、整体仍 `in_progress`；下一接收 D06 最终归档与报告版本对齐，owner TBD。不自动 commit/push。

## 最终图片文字（按阅读顺序）

- RISC-V 轻量密码加速 SoC
- 基于 AMD Zynq-7000 FPGA 的软硬件协同设计
- 面向嵌入式数据安全场景
- Ascon-AEAD128
- 硬件平台
- HARDWARE
- 系统全貌
- SYSTEM
- 核心特点
- HIGHLIGHTS
- 开发板实拍
- 硬件平台：AMD Zynq-7000
- XC7Z020 · 正点原子领航者 ZYNQ7020
- 基于现成开发板设计与验证，无自制 PCB
- Jupyter 实机运行
- KAT / 基准 / PUF 通过
- PYNQ / Jupyter 交互
- Zynq PS · Python API · 黄金参考比对
- AXI-Lite FIFO ↔ UART mailbox
- PL：RV32 五级流水 RISC-V CPU
- IF 取指
- ID 译码
- EX 执行
- MEM 访存
- WB 写回
- SW
- 纯软件执行
- MMIO
- 总线外设加速
- ISE
- EX 级定制指令
- Ascon-AEAD128 · 三路径板级验证 / 周期采集
- 独立扩展 PUF3 · 自身 overlay 集成密钥通路
- RO-PUF + Device DNA
- Ascon P12
- 128-bit 密钥
- 01
- RISC-V 定制指令
- 密码加速
- custom-0 · P8 / P12 置换
- 02
- PYNQ 软硬件协同
- 与通用 Skill
- 交互验证 · 可复用工作流
- 03
- RO-PUF 器件绑定
- 密钥原型
- 物理响应 + DNA · 会话内重建
- 标准算法实现
- 3 种模式
- SW / MMIO / ISE
- 容量内 KAT · 每模式
- 289/289
- PT / AD 各 0–16 B
- MMIO 加密周期加速
- 15.969×
- 相对 SW 软件实现
- ISE 加密周期加速
- 5.613×
- 相对 SW 软件实现
- PUF 会话内重建
- 5/5
- 仅同次上电功能验证
- 板级运行验证
- 已完成
- PYNQ / Jupyter
- 数据：PUF3 · KAT #529 · PT=16 B / AD=0 · HWKEY OFF · 预热 5 次 / 采样 30 次中位数 · CPU mcycle，不含 PS/UART。
- PUF 为独立扩展原型：跨上电、温度、BER、熵与唯一性未测；保密隔离及 RO 域时序未验收。

PNG SHA-256：`d38a111279b4f7371d0e04cbfeb4ae80b5547b942944e0554ec847811a2c0088`；文件大小 792598 bytes。

# 拿到板卡后的分步推进清单（上板 bring-up）

> 2026-11-01 版本补注：下面已完成的 V03 9/9 属旧 PYNQ v1，不能转记到当前 PUF3。
> PUF3 已有10-31容量内三模式/PUF会话内板测和99.9723 MHz时基估测；不等于示波器/Fmax测量。
> 旧快照/复选框保留，当前入口见 version_entrypoints.md。

2026-10-20 起草；owner TBD。下方是原始分步操作清单，保留历史。当前已实际完成：
正点原子领航者 ZYNQ7020 起板、100 MHz PYNQ overlay、SW/HW/ISE 容量内 KAT、
Python/Notebook、warm benchmark 和 V03 错误/恢复门禁。尚未完成 B03 完整实物照片/
丝印速度等级、板上 ISA 抽样、重复上电和独立 FCLK 测量。最新状态见
[current_status_20261029](current_status_20261029.md)。

复选框保留原计划语义，不代表 2026-10-29 当前状态。

配套文档：[时序余量方案](timing_margin_plan.md)、[借板清单](ascon_board_checklist.md)、
[冻结检查点](freeze_checkpoint_20261018.md)、[任务看板](../tasks/task_board.md)。

---

## 阶段 0 — 板卡到手前（10-20 ~ 10-22，不依赖板卡）

- [ ] **T0.1 时序余量收口**：结论见 [timing_margin_plan](timing_margin_plan.md) ——
      P&R 空间已关闭（33 策略 + 4 变体，WNS 只在 +0.001~+0.020 ns 之间），
      不改架构无法把 100 MHz 余量提到 +1 ns。默认动作：**上板频率定 80 MHz**
      （估算 WNS ≈ +2.5 ns，cycles/cpb/加速比不变）；若坚持 100 MHz 则先做 L1 断链（防翻负）。
      门禁：频率决定落字（改 `clk_wiz_0` XCI 走独立入口）+ 重新 STA。
- [ ] **T0.2 Ascon 固件 COE**：`bash src/firmware/ascon_ise_rv32/build.sh`
      → `build/local/ascon_ise/ascon_ise.hex` → 转 COE（`memory_initialization_radix=16;` + 32-bit 行）。
      放进**新建**的 `board/vivado_zynq7000_xc7z020_ascon/`（复制 baseline，`freertos_demo.coe` 原件不动）。
- [ ] **T0.3 板级自检固件**（新增 `src/firmware/board_smoke_rv32/`）：LED 心跳、UART 打印
      版本/复位向量/固件 hash、mcycle 递增、BRAM 读写、icache/dcache 一致性、1 组 Ascon 短 KAT。
      理由：一上板就跑完整 Ascon，出错无法区分“板子不对”还是“算法不对”。
- [ ] **T0.4 板上测试框架** `sim/board/run_board_regression.py`：串口解析 PASS/FAIL、
      失败非零退出、原始日志 + JSON 落 `data/ascon/results/board/`。
- [ ] **T0.5 两套约束草案**：a) 裸机（clk/reset/uart/led/button，异步项 false_path，
      同步项补 IO delay）；b) PS7 + AXI。都必须是独立 constrs 文件，不改 baseline `const.xdc`。
- [ ] **T0.6 板卡身份记录模板** `docs/board_identity_template.md`（见阶段 1 字段）。

**门禁**：T0.1~T0.6 完成才允许动板卡。

---

## 阶段 1 — 板卡身份确认（D0，半天）

- [ ] 拍照记录：品牌、型号、PCB revision、芯片完整丝印（是否 `xc7z020clg400-1`）、
      供电方式、启动跳线（JTAG/QSPI/SD）、JTAG 接口类型。
- [ ] 取得对应版本**原理图 + 官方 XDC + 手册**。
- [ ] 逐项核对引脚与电气：板载时钟**引脚与频率**、复位极性、UART 引脚/电平、LED、按键、DDR 型号。
      ⚠ 现 `const.xdc` 假定 `clk` = **50 MHz @ U18**；PYNQ-Z2 是 125 MHz（另一引脚），
      两者不通用，**照抄会把 MMCM 打成 250 MHz**。
- [ ] Vivado Hardware Manager auto-connect → 读 chip ID/DNA，证明链路通。
- [ ] **判定平台路线**（影响 Y01~Y05 全部工作，必须当天定）：
      - 是 PYNQ-Z2 → PYNQ image 路线（P1 加分项可拿）；
      - 不是 PYNQ → Vitis 裸机 + 串口上位机 + `pyserial` 脚本，P1 降级为“通用 Python 上位机 + Skill”。

**证据**：`docs/board_identity_<model>.md` + 截图/日志。板型未确认前不烧录。

---

## 阶段 2 — 最小点亮（D0 ~ D1，B03 前半）

- [ ] 新建 `board/vivado_<board>_bringup/`（从 baseline 复制；只改 XDC 引脚/时钟，不改 RTL）。
- [ ] 先烧**最小固件**（T0.3 里 LED 心跳 + 串口 hello 那一半），不要直接跑 Ascon。
- [ ] 综合→实现→bitstream，记录 WNS/TNS/DRC/bitstream hash。
- [ ] JTAG 烧录 → 看心跳 → 串口 hello。
- [ ] 时钟不对的排查顺序：引脚 → 板载频率 → MMCM 参数 → 复位极性 → 供电/跳线。

**验收**：串口稳定打印，心跳可观测，bitstream hash 记录在案。

---

## 阶段 3 — Ascon 固件上板 + 板级 KAT（D1 ~ D2，B04 / C03 target）

- [ ] 换 COE → 重生成 `blk_mem_gen_0` → 重跑实现（时序重算，记录 WNS）。
- [ ] 串口打印复位向量、mcycle 原值、CPI，与仿真对照。
- [ ] 官方 6 组 KAT（空/1B/16B/16B+AD/17B/32B）+ tag 篡改拒绝，**三套实现分别跑**
      （软件 / MMIO / ISE）。
- [ ] 与锁定黄金参考**逐字节**比对；日志落 `data/ascon/results/board/`。
- 失败回退：卡在启动 → 查 `0x10000000` 复位向量 / 128 KiB BRAM 映射 / cache 使能；
  KAT 错 → 先用同一 `bin` 在仿真重跑，区分固件问题与板级问题。

**验收**：三套全 PASS，日志 + 固件 hash + bitstream hash 齐全。这是 P0 的真正上板门禁。

---

## 阶段 4 — 板级回归与安全（D2 ~ D4，V01 / V06 板级部分）

- [ ] ISA 回归在板上抽样（含既有已知失败 `rv32ui_ma_data`，不得掩盖）。
- [ ] 错误 key / 错误 tag / 错误密文拒绝；MMIO ZEROIZE；ISE 计算中复位；连续请求；超长拒绝。
- [ ] mcycle 溢出检查、`cpi_cnt` 事件计数交叉核对。

**验收**：一个脚本跑完、失败非零退出、JSON + 原始日志留档。

---

## 阶段 5 — 板上 benchmark（D4 ~ D6，C04 / I07 / V01）

- [ ] 同输入、同频率、同 cache/中断配置：enc/dec 16B、32B，软件 / MMIO / ISE 三套。
- [ ] 记录 mcycle 原始值 + 端到端墙上时间；与仿真值（16840 / 664 / 2559 cyc）对照，
      差异 > 5% 必须解释（cache 命中、中断、UART 主导）。
- [ ] 明确写入“计时范围是否包含软件擦除 / MMIO ZEROIZE”。

**验收**：原始 CSV/JSON 可复算，禁止手填性能值。

---

## 阶段 6 — PS / PYNQ 集成（D6 ~ D9，Y01 ~ Y04）

- [ ] 加 PS7 + AXI（GP 或 HP → SoC 的 AXI slave），`FCLK_CLK0` 替代外部时钟+MMCM。
- [ ] **重跑时序**：时钟源与 PS 硬块占位都会改变布局，现 +0.007 ns 作废。
- [ ] Y01 寄存器/邮箱/缓冲区协议冻结（地址、端序、长度、所有权、一致性、超时、错误码）。
- [ ] Y02 overlay（`.bit` + `.hwh` + hash）→ Y03 Python API → Y04 notebook demo。

**验收**：PYNQ 上调用 Python API 得到与 C 参考一致的 CT/tag，并打印 cycles。

---

## 阶段 7 — 冻结与材料（D9 ~ D11，V03 / V04 / D01~D05）

- [ ] V03 PS/PL 端到端自动回归（含错误场景）。
- [ ] V04 冻结回归清单 + 哈希（RTL/固件/bitstream/XDC/工具版本）。
- [ ] D02 数据表（每个数字可追溯到原始结果）、D03 报告、D04 视频、D05 clean-clone 复现。
- [ ] 10-27 功能冻结 → 10-28 code freeze → 11-01 材料 → 11-04 只提交（用户执行）。

---

## 时间线与硬门禁（今天 10-20）

| 日期 | 硬门禁 | 不达标的处置 |
|---|---|---|
| 10-22 | 时序结论（WNS ≥ +1.0 或 80 MHz 兜底定稿） | 直接切 80 MHz，停止优化 |
| 10-24 | 板卡到手并点亮到串口 | P1 降级：PYNQ 改为仿真 + 文档化，P2(PUF) deferred |
| 10-25 | 板级 KAT 三套 PASS | 只报“仿真 PASS + 板上部分目测”，材料如实写 |
| 10-27 | 功能冻结 | 冻结后只修 blocking bug |
| 10-28 | code freeze | — |
| 11-04 | 提交 | 只改材料，不动代码 |

---

## 上板纪律（违反即返工）

- 不在未核对板型的 XDC 上烧录；不套用别的板的引脚/时钟。
- 不用未通过 KAT 的 COE 上板；不复用 FreeRTOS COE 冒充 Ascon 镜像。
- 串口打印不算 KAT，必须逐字节比对黄金参考。
- 仿真 cycle 不得写成板上实测；未测项写 `not_measured`。
- 生成物（`.bit/.dcp/.elf/.hex/日志`) 不进 git，只留 hash。
- 同一 Vivado 工程/dir 不双开；两人并行时按 `<board>_bringup` / `<board>_pynq` 分目录。

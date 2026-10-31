# RISC-V Lightweight Cryptography SoC 演示视频脚本

更新：2026-10-31  
对应任务：D04（脚本已完成；实机视频仍待录制）  
建议成片：5 分 20 秒；另附 3 分钟压缩版剪法  
画幅：16:9，1920×1080，30 fps；实板特写可用 4K 拍摄后缩至 1080p  
语言：中文旁白，中英术语用字幕辅助  
主证据：2026-10-29 PYNQ 实板 Notebook 与 warm benchmark

## 1. 一句话定位

这不是“只展示一次加密成功”的演示，而是让观众看到：同一个 NIST Ascon-AEAD128
标准输入，在自研 RV32 SoC 上分别经过纯软件、MMIO 加速器和定制指令加速，
通过 KAT 正确性检查后，再用 CPU `mcycle` 比较真实执行成本，并在真实 PYNQ
板上演示错误拒绝与恢复。

核心叙事：

```text
短消息安全需求
  → 自研 RV32 CPU
  → NIST Ascon-AEAD128
  → 三种实现路径
  → 同一 KAT
  → 同一板卡、同一输入、同一计时口径
  → 正确性、性能、错误恢复
```

## 2. 录制原则

1. 优先录当前板卡和 Jupyter 的实时画面。静态架构动画只作解释，不冒充实机运行。
2. 主性能表只使用 2026-10-29 同一次 PYNQ run 的数据，不混入历史 PL-only 的
   `20806 / 688 / 2570` cycles。
3. 明确 `mcycle` 只测 RV32 固件 AEAD 调用边界，不包含 PS、Python 和 UART 传输；
   PS wall time 不参与加速比。
4. 讲清当前板端接口的 PT/AD 上限均为 16 bytes。不要把 host 的 1,089 组 KAT
   说成板端 1,089 组通过。
5. PUF 是独立扩展原型，不与当前 PYNQ 三模式 overlay 混为同一镜像。若加入，
   必须口播“单次上电功能证据，跨电源周期稳定性未测”。
6. 使用锁定官方 KAT 中的公开输入，不在镜头中显示真实密钥或私人数据。

## 3. 主版分镜与旁白（约 5 分 20 秒）

### 00:00–00:18｜冷开场

画面：

- 0–5 秒：ZYNQ7020 板卡正面上电特写，LED 点亮，镜头缓慢推近。
- 5–12 秒：笔记本画面切到 PYNQ Jupyter，再叠标题。
- 12–18 秒：三行大字依次出现：`SW`、`MMIO`、`ISE`。

标题字幕：

```text
面向短消息的轻量级密码 SoC
RISC-V + Ascon-AEAD128 + FPGA 加速
```

旁白：

> 一条 16 字节的短消息，加密应该占用处理器多久？
> 我们在自研 RISC-V SoC 上，用同一套标准输入，比较纯软件、MMIO 硬件加速和
> 定制指令三种实现。

剪辑提示：

- 首帧不要加过长的团队片头，尽快让板卡和标题同时出现。

### 00:18–00:48｜问题与目标

画面：

- 左侧出现短消息、密钥、Nonce、关联数据与密文标签的示意。
- 右侧出现两个关键词：`机密性`、`完整性`。
- 下方给出标准名称：`NIST SP 800-232 Final / Ascon-AEAD128`。

屏幕字幕：

```text
短消息也要同时保证机密性与完整性
标准：NIST SP 800-232 Final
算法：Ascon-AEAD128
```

旁白：

> Ascon-AEAD128 是 NIST SP 800-232 最终版中的认证加密算法。它不只生成密文，
> 还生成 16 字节认证标签；只要密文、关联数据或标签被修改，解密就必须拒绝。
> 我们关注的不是只让算法“算出一个结果”，而是让它在嵌入式 SoC 上可验证、
> 可比较，也能在真实硬件上稳定演示。

### 00:48–01:36｜系统架构

画面：

- 用简洁动画展示：

```text
PC / Jupyter
    ↓
Zynq PS：Python API、黄金参考
    ↓  AXI-Lite 控制 + byte FIFO
PL：RV32 CPU ← UART mailbox
    ├─ 纯软件 AEAD
    ├─ Ascon MMIO
    └─ custom-0 ISE
    ↓
ciphertext / tag / mcycle
```

- 动画经过 `PS → AXI-Lite → mailbox → RV32` 时逐级高亮。
- 最后把镜头切到 `docs/architecture.md` 或实际 Vivado block design 截图，停留 2 秒。

屏幕字幕：

```text
PS 负责控制与参考比对
PL 中自研 RV32 完成受控执行
UART mailbox 使用 uncached MMIO
```

旁白：

> 演示平台是正点原子领航者 ZYNQ7020，目标器件为 XC7Z020，
> PYNQ overlay 配置为 100 MHz。
> PS 端运行 Python 和 Jupyter，负责输入、比对与展示；PL 中运行自研五级流水线
> RV32 CPU。两者通过 AXI-Lite 控制窗口、字节 FIFO 和 RV32 原有 UART 邮箱交换
> 请求与响应。这里使用的是 uncached MMIO，不依赖共享 cacheable buffer，
> 因此每次输入、密文、标签、状态和 mcycle 都有明确的所有权和返回路径。

### 01:36–02:18｜三种实现

画面：

- `SW`：显示 RV32 运行 Ascon C 代码；旁边标注 `通用、灵活`。
- `MMIO`：显示整段 AEAD 卸载到硬件加速器；旁边标注 `短消息路径短`。
- `ISE`：显示 CPU 用 custom-0 指令执行 P8/P12 置换；旁边标注 `保留 CPU 控制流`。
- 三段结束后并排出现：`同一输入`、`同一 KAT`、`同一 mcycle 口径`。

屏幕字幕：

```text
SW：CPU 执行标准软件实现
MMIO：整段 AEAD 卸载
ISE：定制指令加速置换热点
```

旁白：

> 第一种是纯软件。它在 RV32 上执行标准 Ascon 软件实现，灵活性最好，
> 也作为性能基线。
>
> 第二种是 MMIO 全卸载。CPU 写输入、启动加速器并读取结果，整个 AEAD 运算
> 由专用硬件完成，因此在当前 16 字节短消息场景中路径最短。
>
> 第三种是定制指令扩展。我们不改变 GCC backend，而是通过 inline assembly
> 发出 custom-0 指令，让 CPU 在保留原有控制流和软件上下文的同时加速
> Ascon 的 P8、P12 置换热点。三种实现最终处理的是同一个标准请求，
> 也必须给出同样的密文和标签。

### 02:18–03:28｜真实板卡演示

画面：

- 先拍板卡全景，再切 Jupyter。
- 显示 Notebook 标题：`领航者7020：真实 PYNQ Ascon 验证`。
- 点击 `Restart Kernel and Run All Cells`。
- 快速但真实地保留以下运行节点：
  1. release 身份与服务握手；
  2. `simulated=false`；
  3. `firmware_id=pynq-svc-v1`；
  4. `selftest_mask=7`；
  5. SW/HW/ISE 各 `6/6` KAT 与 `6/6` 坏标签拒绝。
- 如果完整 289 组 KAT 录像耗时过长，可单独录一段从命令启动到 `289/289 PASS`
  的画面，并在剪辑中明确标注“2026-10-28 同版本 release”；不要把 6 组 smoke
  画面伪装成 289 组全过程。
- 在板上叠加醒目标记：`REAL BOARD / NOT SIMULATED`。

屏幕字幕：

```text
真实 overlay，无模拟回退
firmware: pynq-svc-v1
simulated: false
selftest_mask: 7
```

旁白：

> 现在直接在真实板卡上从头运行 Notebook。Overlay 加载后，先核对 bitstream、
> HWH、固件和服务身份。服务返回 firmware ID 为 pynq-svc-v1，
> simulated 为 false，三项自检掩码为 7，说明软件、MMIO 和 ISE 路径都来自
> 真实硬件。
>
> 接着运行官方容量内 KAT。三种模式都要逐字节匹配标准密文和标签；
> 对篡改标签还必须返回认证失败，不能发布明文。当前板上接口的明文与关联数据
> 上限都是 16 字节；在这个接口范围内，三模式各通过 289 组官方 KAT，
> 并各自拒绝 289 个坏标签。

### 03:28–04:16｜性能结果

画面：

- 运行 `warm benchmark`，显示固定 KAT `#529`。
- 屏幕上先显示条件，再出现表格：

| 模式 | 加密中位 cycles | cycles/byte | 相对软件 |
|---|---:|---:|---:|
| SW | 23,342 | 1,458.875 | 1.000× |
| MMIO | 1,439 | 89.938 | **16.221×** |
| ISE | 3,995 | 249.688 | **5.843×** |

- 表格下方固定一行小字：

```text
PT=16 B, AD=0, warmup=5, n=30; mcycle excludes PS/UART
```

- 切到原始 JSON 中的 `raw_cycles` 数组，滚过重复采样值，证明不是手填柱状图。

旁白：

> 性能测试固定使用官方 KAT 529：明文 16 字节，关联数据为空。
> 每种模式先预热 5 次，再用 CPU 的 mcycle 计数器采样 30 次。
> 软件加密中位数为 23,342 个周期；MMIO 降到 1,439 个周期，
> 相对软件为 16.221 倍；ISE 为 3,995 个周期，相对软件为 5.843 倍。
>
> 解密方向同样通过：MMIO 为 1,388 个周期，相对软件 17.295 倍；
> ISE 为 4,385 个周期，相对软件 5.474 倍。这里的加速比只使用 CPU 周期。
> PS 调用的一次 wall time 约为 4.96 到 5.22 毫秒，包含 Python、MMIO 和 UART，
> 只作端到端开销说明，不混入加速比。

解释镜头：

- 画面用两条路径动画解释结果：

```text
MMIO：整段 AEAD 一次卸载 → 短消息优势最大
ISE：CPU 保持控制流，热点改用定制指令 → 更易与通用软件协同
```

旁白补充：

> 这组结果也说明两种硬件加速的定位不同。MMIO 把整段 AEAD 交给外设，
> 对当前短消息吞吐最有利；ISE 保留 CPU 的软件执行结构，只替换高成本置换，
> 更适合需要通用控制逻辑、逐步扩展指令集的处理器路线。

### 04:16–04:50｜错误与恢复

画面：

- 切到 `PYNQ V03 错误与恢复门禁` Notebook。
- 依次显示：

```text
17-byte PT / AD      → LENGTH
tampered tag         → REJECT
partial frame        → timeout + reset
duplicate request_id → INTERNAL
wrong epoch          → INTERNAL
RX FIFO overflow     → reset recovery
```

- 最后停在：

```text
9/9 checks PASS
7/7 recovery PASS
50 encrypt + 50 decrypt per mode PASS
```

- 板卡与成功状态同框 2 秒。

旁白：

> 一个只显示成功路径的加速器演示并不够。我们主动注入超长输入、半帧、
> 超时、重复请求、错误 epoch 和接收 FIFO 溢出。系统必须显式报错，
> 再通过 reset 和新的 epoch 恢复，并在恢复后重新跑三种模式的 KAT。
> 最终 9 项错误检查全部通过，7 次故障后的恢复全部成功；
> 三种模式各连续执行 50 次加密和 50 次解密，结果仍与 KAT 一致。

### 04:50–05:20｜实现结果与收束

画面：

- 3 秒 Vivado timing/DRC 摘要：

```text
part: xc7z020clg400-1
configured FCLK0: 100 MHz
WNS: +0.034 ns
TNS: 0
DRC: 0 Error / 0 Critical Warning
```

- 然后回到板卡、Jupyter 和三模式结果同框。
- 最后出现项目标题与一行结论。

结论字幕：

```text
从标准算法，到 CPU 执行，再到可复核的 FPGA 实测
```

旁白：

> 最终 PYNQ 发布版在 100 MHz 配置下实现通过，WNS 为正、TNS 为零，
> DRC 为零错误、零关键警告。普通警告和很小的时序余量仍然保留在证据中，
> 不把它外推为跨温度、跨电压的长期稳定性结论。
>
> 这个项目的核心，是把标准算法、RISC-V 软件、两种硬件加速路径、
> 可追溯的周期数据和真实板级错误恢复，连成一条可以复现的演示链。
> 我们的目标不是只追求一个漂亮数字，而是让每一个数字都能回到同一组输入、
> 同一版 bitstream 和同一套 KAT。

片尾字幕：

```text
RISC-V Lightweight Cryptography SoC with ASCON ISE
NIST SP 800-232 Final · Ascon-AEAD128
Zynq-7000 XC7Z020 · PYNQ · Vivado 2025.2
```

## 4. 3 分钟压缩版剪法

| 时间 | 内容 | 必须保留 |
|---|---|---|
| 00:00–00:15 | 板卡上电 + SW/MMIO/ISE | 标题、真实板卡 |
| 00:15–00:40 | Ascon-AEAD128 与系统架构 | PS、RV32、mailbox、三模式 |
| 00:40–01:15 | 板端身份 + 三模式 KAT | `simulated=false`、6/6 或 289/289 |
| 01:15–01:55 | 16 B 性能表与原始 cycles | 23,342 / 1,439 / 3,995 和三个加速比 |
| 01:55–02:25 | 坏标签与错误恢复 | 9/9、7/7、恢复后 KAT |
| 02:25–02:45 | Vivado、边界、结论 | WNS/DRC、16 B 上限、可复现 |

压缩版旁白可删去 P8/P12 细节、PS wall time、MMIO 与 ISE 的设计取舍说明；
不要删除“16 字节接口上限”“mcycle 范围”和“simulated=false”。

## 5. 可选 PUF 扩展段落（15–25 秒）

仅当比赛材料需要展示扩展研究时加入；若正片已接近时限，建议不入正片。

画面：

- 使用独立的 PUF3 overlay/Notebook，画面角落持续显示：

```text
独立扩展原型 / 非当前 PYNQ 三模式 overlay
```

- 展示 enroll、reconstruct、HWKEY 开关和恢复后的标准 KAT。
- 不展示诊断原始响应、真实设备 DNA 或任何敏感值。

旁白：

> 项目还保留了一个独立的 RO-PUF 与 Device DNA 密钥通路原型。
> 它已在单次上电流程中完成注册、重建、HWKEY 切换和标准 KAT 恢复。
> 该结果不等同于跨电源周期稳定、密钥可保密或完整安全启动；
> 相关可靠性与安全边界仍单列为未测项，也不混入当前三模式 overlay。

不要使用以下说法：

- “PUF 已完全稳定”
- “已完成安全启动”
- “PUF 与当前性能演示运行在同一 overlay”
- “密钥不可提取，因此系统一定安全”

## 6. 录制清单

### 录前

- 确认板卡型号、overlay、bit/HWH/固件与 `release/manifest.json` 匹配。
- 只使用仓库中的公开 KAT 输入，不把个人或真实业务密钥放进镜头。
- Jupyter 字号至少 16–18 px；终端命令和 PASS 行必须可读。
- 关闭通知、聊天软件和其他会显示私人信息的窗口。
- 记录录制时间、板卡照片、bit/HWH SHA-256 和当前 Git commit。

### 录制中

- 第一遍完整录“Notebook 从头执行”，避免中途只截成功单元格。
- 板端身份、三模式 smoke、benchmark 和错误门禁分别留完整屏幕录像或日志。
- 所有动画图只引用 JSON 中的真实值；轴从零开始时避免夸大差异，
  同时保留精确 cycles 表。
- 坏标签拒绝镜头中要能看到“失败/拒绝”语义，而不是只有绿色 PASS 字样。

### 录后

- 成片至少完整看两遍，核对口播与字幕数字一致。
- 对每个数字回查：
  - `data/pynq/notebook_20261029_130920/pynq_warm_benchmark.json`
  - `board/vivado_zynq7000_xc7z020_pynq/validation_20261029.md`
  - `data/pynq/error_gate_20261029_134023/pynq_board_error_gate.json`
- 将最终视频、脚本和证据文件 SHA-256 索引放入同一提交材料目录。
- 只有实机录像与脚本都归档后，才把 D04 改为 `done`。

## 7. 事实卡

录制时以本表为准：

| 项目 | 当前可陈述事实 |
|---|---|
| 平台 | 正点原子领航者 ZYNQ7020，part `xc7z020clg400-1` |
| PYNQ 配置 | FCLK0 配置 100 MHz；独立频率测量未完成 |
| 标准 | NIST SP 800-232 Final，Ascon-AEAD128 |
| CPU | RV32 五级流水线；当前板上演示使用 RV32 |
| 板端接口 | PT ≤16 B，AD ≤16 B |
| 板端 KAT | SW/HW/ISE 各 289/289；坏 Tag 各 289/289 拒绝 |
| smoke | SW/HW/ISE 各 6/6；坏 Tag 各 6/6 拒绝 |
| benchmark | KAT #529；PT=16 B、AD=0；预热 5 次，采样 30 次 |
| SW 加密 | 23,342 cycles；1,458.875 cycles/B |
| MMIO 加密 | 1,439 cycles；89.938 cycles/B；16.221× |
| ISE 加密 | 3,995 cycles；249.688 cycles/B；5.843× |
| SW 解密 | 24,005 cycles；1,500.312 cycles/B |
| MMIO 解密 | 1,388 cycles；86.750 cycles/B；17.295× |
| ISE 解密 | 4,385 cycles；274.062 cycles/B；5.474× |
| 周期口径 | RV32 固件 AEAD `mcycle`；不含 PS/UART/Python |
| 错误门禁 | 9/9 checks PASS；7/7 次 reset/epoch 恢复 PASS |
| 连续请求 | 每模式 50 次加密 + 50 次解密全部匹配 KAT |
| 实现 | Vivado 2025.2；WNS +0.034 ns、TNS 0；DRC 0 Error / 0 Critical Warning |

必须同时说明的边界：

- 未把 host 的 1,089 组 KAT 全部搬到板端；超过当前 16-byte 接口的 800 组为
  `NOT_RUN`。
- 未完成跨电源周期、长时间运行、跨板、完整 RV64/异常矩阵和独立板级频率测量。
- PUF3 只是独立扩展原型；跨电源周期、温度、BER、熵、唯一性和 RO timing
  signoff 仍为 `not_measured`。
- 当前时序余量很小，不能表述为跨工艺角、温度、电压的长期稳定性保证。

# RISC-V Lightweight Cryptography SoC 演示视频脚本

- 更新：2026-11-01（10-31 初版基于 PYNQ v1 release；本版按最终报告改为 PUF3 主演示）
- 对应任务：D04（脚本已完成；实机视频仍待录制）
- 建议成片：5 分 20 秒；另附 3 分钟压缩版剪法
- 画幅：16:9，1920×1080，30 fps；实板特写可用 4K 拍摄后缩至 1080p
- 语言：中文旁白，中英术语用字幕辅助
- 主证据：PUF3 overlay 2026-10-31 实板 Notebook `src/pynq_puf3/pynq_puf3_board_test.ipynb`，
  结果 `data/pynq_puf3/notebook_20261031_114512/result.json`；数字与最终报告
  `report/technical/amd_fpga_2026_latex_final/amd_fpga_2026_report/output/pdf/final_report.pdf` 一致

## 1. 一句话定位

这不是“只展示一次加密成功”的演示，而是让观众看到：同一个 NIST Ascon-AEAD128
标准输入，在自研 RV32 SoC 上分别经过纯软件、MMIO 加速器和定制指令加速，
通过 KAT 正确性检查后，再用 CPU `mcycle` 比较真实执行成本；同一 overlay 还提供
RO-PUF/Device DNA 派生的硬件密钥通路，并在真实 PYNQ 板上演示注册、重建与切换。

核心叙事：

```text
短消息安全需求
  → 自研 RV32 CPU
  → NIST Ascon-AEAD128
  → 三种实现路径（SW / MMIO / ISE）
  → 同一 KAT、同一板卡、同一输入、同一计时口径
  → 正确性、性能
  → 同一 overlay 内的 PUF 硬件密钥通路
```

## 2. 录制原则

1. 优先录当前板卡和 Jupyter 的实时画面。静态架构动画只作解释，不冒充实机运行。
2. 主性能表只使用 2026-10-31 同一次 PUF3 run 的数据。不混入 PYNQ v1 release 的
   `23342 / 1439 / 3995`，也不混入历史 PL-only 的 `20806 / 688 / 2570` cycles。
3. 明确 `mcycle` 只测 RV32 固件 AEAD 调用边界，不包含 PS、Python、UART 传输，
   也不包含响应后的收发缓冲擦除；PS 墙钟只有 summary 中位，不参与加速比。
4. benchmark 时 HWKEY 关闭，使用官方 KAT 的公开密钥；不要把性能数字说成“PUF 密钥下的性能”。
5. 讲清当前板端接口的 PT/AD 上限均为 16 bytes。不要把 host 的 1,089 组 KAT
   说成板端 1,089 组通过。
6. PUF 段必须口播“会话内功能证据；跨上电、温度/电压、BER、熵与唯一性未测；
   RO 计数器域时序未签核”。不展示真实设备 DNA、RAW/REF/MASK 原始响应或派生密钥。
7. 错误恢复 9/9 门禁属于旧 PYNQ v1 release（固件 `pynq-svc-v1`），不能作为 PUF3 的通过项；
   如需展示，只能放在第 5 节的历史对照段并加标注。
8. 使用锁定官方 KAT 中的公开输入，不在镜头中显示真实密钥或私人数据。

## 3. 主版分镜与旁白（约 5 分 20 秒）

### 00:00–00:18｜冷开场

画面：

- 0–5 秒：ZYNQ7020 板卡正面上电特写，LED 点亮，镜头缓慢推近。
- 5–12 秒：笔记本画面切到 PYNQ Jupyter，再叠标题。
- 12–18 秒：四个词依次出现：`SW`、`MMIO`、`ISE`、`PUF KEY`。

标题字幕：

```text
面向短消息的轻量级密码 SoC
RISC-V + Ascon-AEAD128 + FPGA 加速 + PUF 密钥通路
```

旁白：

> 一条 16 字节的短消息，加密应该占用处理器多久？密钥又从哪里来？
> 我们在自研 RISC-V SoC 上，用同一套标准输入，比较纯软件、MMIO 硬件加速和
> 定制指令三种实现，并在同一个 FPGA 镜像里接入 PUF 派生的硬件密钥。

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
    ↓  AXI-Lite 控制 + byte FIFO（控制 ID PQF3 = 0x33465150）
PL：RV32 CPU ← UART mailbox（固件 pynq-svc-puf3）
    ├─ 纯软件 AEAD
    ├─ Ascon MMIO ← 密钥选择：调用者密钥 / HWKEY
    │                     ↑
    │              RO-PUF + Device DNA → key_mmio
    └─ custom-0 ISE
    ↓
ciphertext / tag / mcycle
```

- 动画经过 `PS → AXI-Lite → mailbox → RV32` 时逐级高亮，再高亮 `RO-PUF → key_mmio → Ascon MMIO`。
- 最后切到最终报告图 2-10 的真实 Vivado Block Design 截图，停留 2 秒。

屏幕字幕：

```text
PS 负责控制与参考比对
PL 中自研 RV32 完成受控执行
同一 overlay：三模式 AEAD + PUF/DNA 密钥通路
```

旁白：

> 演示平台是正点原子领航者 ZYNQ7020，目标器件为 XC7Z020，
> PUF3 overlay 的 FCLK0 配置为 100 MHz。
> PS 端运行 Python 和 Jupyter，负责输入、比对与展示；PL 中运行自研五级流水线
> RV32 CPU。两者通过 AXI-Lite 控制窗口、字节 FIFO 和 RV32 的 UART 邮箱交换请求与响应，
> 使用 uncached MMIO，每次输入、密文、标签、状态和 mcycle 都有明确的返回路径。
> 同一个镜像里还集成了 256 路 RO-PUF 和 Device DNA：注册后可由固件打开 HWKEY，
> 让 MMIO 加速器改用硬件派生密钥，调用者写入的密钥将不再生效。

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
ISE：定制指令加速置换热点（固件内 22 条 custom-0）
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

### 02:18–03:20｜真实板卡演示

画面：

- 先拍板卡全景，再切 Jupyter。
- 显示 Notebook 标题：`pynq_puf3 实板测试`，运行 `执行完整上板测试`。
- 快速但真实地保留以下运行节点：
  1. 下载前核对 SLCR 的 IO PLL 参数与 HWH 一致，加载后 bit/HWH/manifest 哈希匹配；
  2. 控制 ID `0x33465150`（PQF3）、`firmware_id=pynq-svc-puf3`；
  3. `simulated=false`、`selftest_mask=7`；
  4. 时钟：寄存器推导 99.999999 MHz，mcycle/PS 时基估测 99.9723 MHz；
  5. SW/HW/ISE 各 `289/289` KAT 与 `289/289` 坏标签拒绝。
- 289 组 KAT 若录像过长，可加速播放但保留起止画面与计数，不要剪成只剩 PASS。
- 在板上叠加醒目标记：`REAL BOARD / NOT SIMULATED`。

屏幕字幕：

```text
真实 overlay，无模拟回退
control ID: PQF3 (0x33465150)
firmware: pynq-svc-puf3
simulated: false   selftest_mask: 7
```

旁白：

> 现在直接在真实板卡上运行 Notebook。下载前先核对时钟寄存器，加载后核对 bitstream、
> HWH 和 manifest 哈希，再握手确认控制 ID 为 PQF3、固件为 pynq-svc-puf3，
> simulated 为 false，三项自检掩码为 7。
> PYNQ 自带的频率显示会给出 150 MHz，那是它假设了错误的参考时钟；
> 按寄存器推导是 100 MHz，用 mcycle 与 PS 时基估测为 99.97 MHz。
>
> 接着运行官方容量内 KAT。三种模式都要逐字节匹配标准密文和标签；
> 对篡改标签还必须返回认证失败，不能发布明文。当前板上接口的明文与关联数据
> 上限都是 16 字节；在这个范围内，三模式各通过 289 组官方 KAT，
> 并各自拒绝 289 个坏标签。

### 03:20–04:05｜性能结果

画面：

- 显示 benchmark 条件，再出现表格：

| 模式 | 加密中位 cycles | cycles/byte | 相对软件 |
|---|---:|---:|---:|
| SW | 21,862 | 1,366.3750 | 1.000× |
| MMIO | 1,369 | 85.5625 | **15.969×** |
| ISE | 3,895 | 243.4375 | **5.613×** |

- 表格下方固定一行小字：

```text
KAT #529, PT=16 B, AD=0, HWKEY off, warmup=5, n=30; mcycle excludes PS/UART
```

- 切到 `result.json` 中的 `raw_cycles` 数组，滚过 30 个采样值，证明不是手填柱状图。

旁白：

> 性能测试固定使用官方 KAT 529：明文 16 字节，关联数据为空，HWKEY 关闭。
> 每种模式先预热 5 次，再用 CPU 的 mcycle 计数器采样 30 次。
> 软件加密中位数为 21,862 个周期；MMIO 降到 1,369 个周期，
> 相对软件为 15.969 倍；ISE 为 3,895 个周期，相对软件为 5.613 倍。
>
> 解密方向：软件 22,562 个周期，MMIO 为 1,213 个周期，相对软件 18.600 倍；
> ISE 为 4,288 个周期，相对软件 5.262 倍。这里的加速比只使用 CPU 周期。
> PS 调用一次的墙钟中位约为 4.1 到 5.1 毫秒，包含 Python、MMIO 和 UART，
> 只作端到端开销说明，不混入加速比。

解释镜头：

```text
MMIO：整段 AEAD 一次卸载 → 短消息优势最大
ISE：CPU 保持控制流，热点改用定制指令 → 更易与通用软件协同
```

旁白补充：

> 两种硬件加速的定位不同。MMIO 把整段 AEAD 交给外设，对当前短消息最有利；
> ISE 保留 CPU 的软件执行结构，只替换高成本置换，更适合逐步扩展指令集的处理器路线。

### 04:05–04:45｜PUF 硬件密钥通路

画面：

- Notebook 的 PUF 段依次显示（只显示状态与判定，不显示 DNA/RAW/REF/MASK 原始值）：

```text
ENROLL            → quality 127/128
RECONSTRUCT ×5    → stable
HWKEY ON          → caller key rejected
after reconstruct → same ciphertext
HWKEY OFF         → official KAT restored
```

- 画面角落持续显示：`会话内功能证据 / 跨上电未测 / RO 域未签核`。

旁白：

> 同一个镜像里，RO-PUF 先完成注册，质量为 128 位中 127 位可用，
> 随后在同一会话内连续 5 次重建都稳定。打开 HWKEY 后，MMIO 加速器改用硬件派生密钥，
> 调用者写入的密钥被拒绝；重建后同一输入得到相同密文；关闭 HWKEY 后，
> 官方 KAT 重新通过。
> 需要说明边界：这是会话内的功能证据，helper 数据不跨上电保存；
> 跨上电、温度电压、误码率、熵和唯一性都还没有测，RO 计数器域时序也没有签核，
> 原始响应在调试接口上可读，因此不能把它说成已经保密可靠的密钥。

### 04:45–05:20｜实现结果与收束

画面：

- 3 秒 Vivado 摘要（最终报告图 2-11/图 3-2 的真实截图）：

```text
part: xc7z020clg400-1   top: pynq_puf3_wrapper
LUT 18674 / FF 32002 / BRAM 34.5 / DSP 4
constrained paths: WNS +0.104 ns, TNS 0, WHS +0.041 ns, 0/73907 failing
DRC: 0 Error / 0 Critical Warning
RO counter domain: NOT signed off
```

- 然后回到板卡、Jupyter 和三模式结果同框。
- 最后出现项目标题与一行结论。

结论字幕：

```text
从标准算法，到 CPU 执行，再到可复核的 FPGA 实测
```

旁白：

> PUF3 overlay 在 100 MHz 配置下实现通过：已约束路径 WNS 为正 0.104 纳秒、
> TNS 为零，DRC 零错误、零关键警告。RO-PUF 的振荡计数器域不属于同步时序签核范围，
> 我们把它单独列为未签核项，不外推为跨温度、跨电压的稳定性结论。
>
> 这个项目的核心，是把标准算法、RISC-V 软件、两种硬件加速路径、PUF 密钥通路、
> 可追溯的周期数据连成一条可以复现的演示链。
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
| 00:00–00:15 | 板卡上电 + SW/MMIO/ISE/PUF KEY | 标题、真实板卡 |
| 00:15–00:40 | Ascon-AEAD128 与系统架构 | PS、RV32、mailbox、三模式、PUF 通路 |
| 00:40–01:15 | 板端身份 + 三模式 KAT | PQF3、`simulated=false`、289/289 |
| 01:15–01:55 | 16 B 性能表与原始 cycles | 21,862 / 1,369 / 3,895 和加速比 |
| 01:55–02:25 | PUF 注册/重建/HWKEY | 127/128、5 次稳定、KAT 恢复、边界口播 |
| 02:25–02:45 | Vivado、边界、结论 | WNS/DRC、RO 未签核、16 B 上限 |

压缩版旁白可删去 P8/P12 细节、PS 墙钟、MMIO 与 ISE 的设计取舍说明；
不要删除“16 字节接口上限”“mcycle 范围”“simulated=false”和 PUF 的未测边界。

## 5. 可选历史对照段（10–15 秒）

仅当需要说明错误恢复设计时加入；若正片已接近时限，建议不入正片。

画面角落持续显示：`旧 PYNQ v1 release（pynq-svc-v1），非 PUF3`。

- 来源：`data/pynq/error_gate_20261031_112812/pynq_board_error_gate.json`（2026-10-31 重测）。
- 可展示：17-byte 输入 → LENGTH、半帧/超时/RX 溢出 → reset 恢复、重复 request_id/错误 epoch →
  INTERNAL；9/9 checks、7/7 次 reset/epoch 恢复。

旁白：

> 在上一版 PYNQ 发布镜像上，我们还做过错误注入与恢复门禁，9 项检查全部通过。
> 这组结果属于旧固件，PUF3 镜像尚未完整重跑该门禁。

不要使用以下说法：

- “PUF 已完全稳定”“密钥不可提取，因此系统一定安全”
- “已完成安全启动”
- “PUF3 已通过 9/9 错误门禁”
- “性能数字是在 PUF 密钥下测得”

## 6. 录制清单

### 录前

- 确认板卡型号、overlay，bit/HWH/固件与
  `board/vivado_zynq7000_xc7z020_pynq_puf3/candidate/manifest.json` 匹配
  （`pynq_puf3.bit` 4,045,693 B）。
- 只使用仓库中的公开 KAT 输入，不把个人或真实业务密钥放进镜头。
- Jupyter 字号至少 16–18 px；终端命令和 PASS 行必须可读。
- 关闭通知、聊天软件和其他会显示私人信息的窗口。
- 记录录制时间、板卡照片、bit/HWH SHA-256 和当前 Git commit。

### 录制中

- 第一遍完整录“Notebook 从头执行”，避免中途只截成功单元格。
- 身份/时钟、三模式 KAT、benchmark 和 PUF 段分别留完整屏幕录像或日志。
- 所有动画图只引用 JSON 中的真实值；轴从零开始时避免夸大差异，同时保留精确 cycles 表。
- 坏标签拒绝镜头中要能看到“失败/拒绝”语义，而不是只有绿色 PASS 字样。
- PUF 段遮挡 DNA、RAW/REF/MASK 与派生密钥相关输出。

### 录后

- 成片至少完整看两遍，核对口播与字幕数字一致。
- 对每个数字回查：
  - `data/pynq_puf3/notebook_20261031_114512/result.json`
  - `board/vivado_zynq7000_xc7z020_pynq_puf3/candidate/reports/`（utilization、timing_summary、drc）
  - 最终报告 `final_report.pdf` 表 1-1、表 3-13/3-14
- 若录制时重新运行 Notebook，新 run 的数值必须与上表一致或改用新 run 并同步更新报告；不能混用。
- 将最终视频、脚本和证据文件 SHA-256 索引放入同一提交材料目录。
- 只有实机录像与脚本都归档后，才把 D04 改为 `done`。

## 7. 事实卡

录制时以本表为准（来源：PUF3 2026-10-31 run 与 candidate 报告，已与最终报告核对）：

| 项目 | 当前可陈述事实 |
|---|---|
| 平台 | 正点原子领航者 ZYNQ7020，part `xc7z020clg400-1` |
| overlay | PUF3：`pynq_puf3_wrapper`，控制 ID PQF3 `0x33465150`，固件 `pynq-svc-puf3` |
| 时钟 | FCLK0 配置 100 MHz；寄存器推导 99.999999 MHz；mcycle/PS 估测 99.9723 MHz（非示波器/Fmax）；PYNQ 显示 150 MHz 不是真实频率 |
| 标准 | NIST SP 800-232 Final，Ascon-AEAD128 |
| CPU | RV32 五级流水线 |
| 板端接口 | PT ≤16 B，AD ≤16 B |
| 板端 KAT | SW/HW/ISE 各 289/289；坏 Tag 各 289/289 拒绝 |
| benchmark | KAT #529；PT=16 B、AD=0；HWKEY 关闭；预热 5 次，采样 30 次 |
| SW 加密 | 21,862 cycles；1,366.3750 cycles/B |
| MMIO 加密 | 1,369 cycles；85.5625 cycles/B；15.969× |
| ISE 加密 | 3,895 cycles；243.4375 cycles/B；5.613× |
| SW 解密 | 22,562 cycles；1,410.1250 cycles/B |
| MMIO 解密 | 1,213 cycles；75.8125 cycles/B；18.600× |
| ISE 解密 | 4,288 cycles；268.0000 cycles/B；5.262× |
| PS 墙钟中位 | 加密 5.130/4.403/4.385 ms，解密 4.874/4.160/4.137 ms（仅 summary，无原始数组） |
| 周期口径 | RV32 固件 AEAD `mcycle`；不含 PS/UART/Python，也不含响应后的缓冲擦除 |
| PUF | 注册 quality 127/128；会话内重建 5/5 稳定；HWKEY 下调用者密钥被拒；关闭后 KAT 恢复 |
| 实现 | Vivado 2025.2；LUT 18674、FF 32002、BRAM 34.5、DSP 4；已约束路径 WNS +0.104 ns、TNS 0、WHS +0.041 ns，0/73907 失败端点；DRC 0 Error / 0 Critical Warning |

必须同时说明的边界：

- 未把 host 的 1,089 组 KAT 全部搬到板端；超过当前 16-byte 接口的 800 组为 `NOT_RUN`。
- PUF：跨上电、温度/电压、BER、熵、唯一性 `not_measured`；RO 计数器域未签核
  （5120 个无时钟引脚、15360 个未约束引脚、256 个组合环，Slow/Fast 角均有负 slack）；
  REF/MASK/RAW/DNA 调试可读，未证明保密隔离。
- PUF3 未完整重跑错误注入门禁；9/9 属于旧 `pynq-svc-v1`。
- HW 驱动不发送每次调用的硬件 ZEROIZE；只有软件缓冲擦除，且在 mcycle 计时区间之外。
- 未完成长时间运行、跨板、完整 RV64/异常矩阵和独立板级频率测量。

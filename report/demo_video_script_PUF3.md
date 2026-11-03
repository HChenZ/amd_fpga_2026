# RISC-V Lightweight Cryptography SoC｜3 分钟演示视频脚本（PUF3）

- **目标时长**：03:00（成片控制在 02:58—03:00，避免平台卡边）
- **演示版本**：`pynq_puf3`，同一 overlay 集成 SW / MMIO / ISE / PUF v1
- **画面规格**：16:9，1920×1080，30 fps；旁白全程配逐句实时字幕
- **证据基准**：2026-10-31 实板记录
  - `data/pynq_puf3/notebook_20261031_114512/result.json`
  - `board/vivado_zynq7000_xc7z020_pynq_puf3/candidate/`
- **制作原则**：实板运行画面用于证明结果；动画和图表只解释结构、流程与对比，不冒充实机运行。若正式录制结果变化，以新 `result.json` 为准更新数值。

## 一、3 分钟时间轴总览

素材标记：

- **R｜实机录屏**：必须在目标板 + PYNQ/Jupyter 上现场运行或从本次现场原始录屏中剪取。
- **P｜实拍**：板卡、接口、供电或板卡与屏幕同框的真实拍摄。
- **A｜动画**：用于解释算法和系统结构，不代表实板波形。
- **C｜图表**：由原始 JSON 数据或 Vivado 报告制作，必须标数据来源和口径。
- **S｜静态证据**：现场报告、JSON 字段或代码文件截图，可高亮，不得改动原值。

| 时间 | 段落 | 需要准备的核心素材 |
|---|---|---|
| 00:00—00:10 | 开场 | P：板卡与 Jupyter 同框；A：片名和四个模块 |
| 00:10—00:27 | 认证加密任务 | A：Key/Nonce/AD/PT → Ascon → CT/Tag；坏 Tag 拒绝动画 |
| 00:27—00:46 | 系统结构 | A：PS→AXI-Lite/邮箱→PL RV32→SW/MMIO/ISE/PUF |
| 00:46—01:20 | 实板身份与 KAT | R：PUF3 Notebook 从头运行；P：板卡与屏幕同框；S：关键输出 |
| 01:20—01:47 | 性能对比 | S：原始 `result.json`；C：加密/解密中位周期柱状图 |
| 01:47—02:13 | PUF 流程 | R：同一 Notebook 的 PUF 输出；A：流程状态条 |
| 02:13—02:25 | 错误标签 | R：坏标签聚合结果；可选 R：单例 `AUTH_FAILED` 补拍 |
| 02:25—02:37 | FPGA 实现 | S：PUF3 timing/utilization 报告；C：关键数字卡片 |
| 02:37—02:50 | PYNQ Skill | R/S：`SKILL.md` 和 L3 四段 PASS 汇总 |
| 02:50—03:00 | 收束 | P：板卡；R：PASS/性能短切；A：项目名与边界说明 |

## 二、逐镜完整脚本：画面、旁白、字幕与视频标注

以下三部分严格分开：

- **画面**：观众看到的镜头。
- **旁白字幕**：配音时说出的原文，也是逐句实时字幕。
- **视频标注**：固定在画面上的技术参数、状态值或图示文字，不用来重复旁白。

### 00:00—00:10｜开场

**画面**

1. 0.0—3.5 s：板卡工作状态特写，随后拉远到板卡与 Jupyter 同框。
2. 3.5—7.0 s：标题和四个模块依次出现：`RISC-V CPU`、`Ascon SW`、`MMIO/ISE`、`RO-PUF`。
3. 7.0—10.0 s：只保留项目名与副标题，切下一镜。

**素材要求**

- 板卡实拍至少 10 s，环境光稳定，避免拍到与项目无关的桌面信息。
- 标题用项目统一字体和配色；不要用一个纯软件动画冒充板卡运行。

**旁白与逐句字幕原文**

1. 我们在 Zynq FPGA 上构建了自研 RISC-V 轻量密码 SoC。
2. 它集成了 Ascon 加速与 PUF 原型。

**视频中必须标注**

- 主标题：`RISC-V Lightweight Cryptography SoC`
- 副标题：`Ascon-AEAD128 · SW / MMIO / ISE · PUF3`
- 四个模块标签：`RISC-V CPU`、`Ascon SW`、`MMIO / ISE`、`RO-PUF`
- 左下角小字：`实板画面 + 结构示意`

### 00:10—00:27｜认证加密任务

**画面**

- 左侧固定展示四个输入块：`Key`、`Nonce`、`AD`、`Plaintext`。
- 它们进入 `Ascon-AEAD128` 后，右侧依次出现 `Ciphertext` 和 `Tag`。
- 8—11 s：高亮 `Tag` 中的一个 bit 并将其翻转；随后出现红色 `AUTH_FAILED / REJECT`。
- 11—17 s：显示“候选明文不发布”的锁闭图标；不要展示真实密钥。

**素材要求**

- 纯动画 15 s；使用简洁节点和箭头，避免整屏代码。
- `PT/AD ≤ 16 B` 用小字角标保留，防止把项目接口边界误解为标准算法上限。

**旁白与逐句字幕原文**

1. Ascon-AEAD128 是 NIST 标准化的认证加密算法。
2. 它同时生成密文和认证标签。
3. 标签被修改时，解密拒绝，并且不发布未认证明文。

**视频中必须标注**

- 输入块：`Key`、`Nonce`、`AD`、`Plaintext`
- 处理块：`Ascon-AEAD128`
- 输出块：`Ciphertext`、`Tag`
- 容量角标：`当前板端 PT ≤ 16 B · AD ≤ 16 B`
- 篡改结果：`AUTH_FAILED / REJECT`
- 拒绝后的状态：`Plaintext not released`
- 画面角标：`算法流程示意`

### 00:27—00:46｜系统结构

**画面**

```text
PYNQ / Jupyter（Zynq PS）
          │ AXI-Lite + UART mailbox
          ▼
自研 RV32 SoC（Zynq PL，≈100 MHz）
          ├─ SW：C 软件实现
          ├─ MMIO：AEAD 硬件卸载
          ├─ ISE：custom-0 加速 P8/P12
          └─ RO-PUF + HWKEY
```

- 先出现 PS→PL 数据通路，再依次点亮 SW、MMIO、ISE。
- 最后 4 s 将 RO-PUF 与三模式并列，强调“同一 PUF3 overlay”。

**素材要求**

- 用矢量图或 PPT 动画制作；结构依据 `docs/architecture.md` 和 PUF3 工程 readme。
- 需要两条版本字幕：`PUF3 演示变体`、`PUF 可靠性边界见片尾`。

**旁白与逐句字幕原文**

1. Jupyter 通过 AXI-Lite 和 UART 邮箱控制 PL 中的 RV32。
2. 软件、MMIO 和定制 ISE 共享同一 PUF3 overlay。

**视频中必须标注**

- `PYNQ / Jupyter`
- `Zynq PS`
- `AXI-Lite + UART mailbox`
- `自研 RV32 / PL`
- `SW`、`MMIO`、`ISE`
- `custom-0: P8 / P12`
- `RO-PUF + HWKEY`
- `same PUF3 overlay`
- 器件角标：`xc7z020clg400-1`
- 时钟角标：`CPU/Ascon ≈100 MHz`
- 接口角标：`UART MMIO: uncached`

### 00:46—01:20｜实板运行：身份、时钟与全量容量内 KAT

**画面**

1. 0—5 s：板卡与 Jupyter 同框，打开 `src/pynq_puf3/pynq_puf3_board_test.ipynb`。
2. 5—10 s：展示第一个代码单元中的 `FULL_KAT = True`，再切到 `Kernel → Restart Kernel and Run All Cells`。
3. 10—23 s：保留身份和时钟输出；可对等待段做 2—4 倍速，并显示“真实执行，过程加速”。
4. 23—34 s：连续展示三行 KAT 结果和 `PASS`，不要插旧版本日志。

**必须保留/标注的关键实拍字段**

```text
repository: /home/xilinx/jupyter_notebooks/amd_fpga_2026
control identity: PQF3
firmware_id: pynq-svc-puf3
simulated: false
selftest_mask: 7
FCLK0 register-derived: 100.000 MHz
FCLK0 measured by mcycle: 99.972 MHz

kat sw 289
kat hw 289
kat ise 289

PASS
```

其中身份、固件和 `selftest_mask` 可由本次 `result.json` 的安全字段卡或临时单元展示；不要伪造 Notebook 控制台没有实际打印的字符串。

**旁白与逐句字幕原文**

1. 现在从头运行 PUF3 实板 Notebook，先核对 bit、HWH、固件和时钟。
2. 三种模式都通过 289 组容量内 KAT，并拒绝 289 组坏标签。
3. 等待段做了剪辑加速，但结果来自这次真实运行。

**必须叠加的说明**

```text
每种模式：289/289 容量内 KAT + 289/289 篡改标签拒绝
当前板端接口：PT ≤ 16 B、AD ≤ 16 B
本轮仅覆盖项目定义的 289 组容量内 KAT
```

**视频中必须标注**

- 运行方式：`Restart Kernel and Run All Cells`
- `FULL_KAT = True`
- overlay 标识：`PQF3`
- 证据类型：`simulated = false`
- `firmware_id = pynq-svc-puf3`
- `selftest_mask = 7`
- 时钟：`SLCR 推算 99.999999 MHz · mcycle 实测 99.9723 MHz`
- 三模式结果：`SW 289/289`、`MMIO 289/289`、`ISE 289/289`
- 坏标签：`289/289 REJECT`（三种模式分别统计）
- 剪辑状态：`真实执行画面 · 过程加速`

**剪辑要求**

- 完整原始录屏另存，不丢开头、Notebook 输出和结尾 `PASS`。
- 加速只用于长时间等待段；不要删掉 `simulated=false`、固件 ID 和计数结果后只用结论字卡替代。
- PYNQ 2.7 可能显示 `150 MHz`，但该值是 50 MHz 参考时钟假设造成的派生显示；视频采用 SLCR 推算和 `mcycle` 实测，不把 150 MHz 当真实频率。

### 01:20—01:47｜性能对比

**画面**

1. 0—8 s：展示本次 `result.json` 中 `benchmark.modes.*.*.summary.median` 的实际字段。
2. 8—20 s：切两组柱状图，加密和解密分别显示“相对 SW”倍数。
3. 20—27 s：回到原始周期表，明确这是 CPU 内部 AEAD 调用周期，不是 Jupyter 端到端响应时间。

| 模式 | 加密中位周期 | 加密相对 SW | 解密中位周期 | 解密相对 SW |
|---|---:|---:|---:|---:|
| SW | 21,862 | 1.000× | 22,562 | 1.000× |
| MMIO | 1,369 | 15.969× | 1,213 | 18.600× |
| ISE | 3,895 | 5.613× | 4,288 | 5.262× |

**固定注释**

```text
KAT #529 · PT 16 B · AD 0 B · warmup=5 · n=30
加速比 = SW 中位周期 / 对应模式中位周期
范围：RV32 固件 AEAD mcycle；不含 PS、Python、AXI-Lite/UART 主机路径
```

**素材要求**

- 柱状图从原始 JSON 生成，纵轴从 0 开始并标单位 `cycles`。
- 不要用 PS 墙钟时间计算或替换加速比。
- 若正式运行数值改变，图表和旁白全部使用同一次新结果。

**旁白与逐句字幕原文**

1. KAT #529 使用 16 字节明文和 0 字节关联数据，预热 5 次、测量 30 次。
2. MMIO 加密约快 15.969 倍，ISE 约快 5.613 倍；解密分别为 18.600 倍和 5.262 倍。
3. 所有数字都是 RV32 AEAD `mcycle`，不包含 PS、Python 和 UART 开销。

**视频中必须标注**

- 图中常驻：`加密中位周期`、`解密中位周期`、`相对 SW 加速比`
- SW：`加密 21,862 cycles`、`解密 22,562 cycles`
- MMIO：`加密 1,369 cycles / 15.969×`、`解密 1,213 cycles / 18.600×`
- ISE：`加密 3,895 cycles / 5.613×`、`解密 4,288 cycles / 5.262×`
- 测试条件：`KAT #529 · PT 16 B · AD 0 B · warmup=5 · n=30`
- 口径警示：`RV32 AEAD mcycle only · 不含 PS/Python/UART`
- 画面来源：`本次 result.json`

### 01:47—02:13｜PUF 注册、重建和 HWKEY

**画面**

1. 0—4 s：未注册时 `hwkey_on` 返回 `NO_PUF_KEY`。
2. 4—7 s：`enroll OK`，仅显示 `quality 127`。
3. 7—12 s：连续五次 `reconstruct OK`，叠加 `5/5`。
4. 12—18 s：`HWKEY_ON`，硬件加密成功；官方密文在 PUF 密钥下被拒绝。
5. 18—26 s：`HWKEY_OFF` 后官方 KAT 恢复。

**安全画面要求**

- 可显示：`quality`、重建次数、`HWKEY ON/OFF`、`KAT restored: true`。
- 必须遮挡或裁掉：`DNA`、`REF`、`MASK`、`RAW`、`DITHER` 以及任何密钥、helper 或原始响应值。
- `quality=127` 只表示当前会话质量指标，不能配音成“127 位熵”或“跨上电成功率 127”。

**旁白与逐句字幕原文**

1. 同一 overlay 中，未注册时 HWKEY 被拒绝。
2. ENROLL 后 quality 为 127，连续 5 次重建一致。
3. 打开 HWKEY 使用派生密钥，关闭后标准 KAT 恢复。
4. 这里只验证同次上电功能，quality 不是熵或跨上电成功率。

**视频中必须标注**

- 流程条：`STATUS → ENROLL → RECONSTRUCT ×5 → HWKEY ON → HWKEY OFF`
- 未注册结果：`NO_PUF_KEY`
- `enroll_quality = 127`
- `reconstructs_stable = 5/5`
- `caller_key_rejected_under_puf_key = true`
- `same_ciphertext_after_reconstruct = true`
- `kat_restored_after_hwkey_off = true`
- 常驻边界：`same overlay · same power session`
- 常驻边界：`quality=127 是当前会话质量指标，不是熵`
- 原始诊断字段：一律遮挡或裁切

**边界字幕**

```text
同一 PUF3 overlay、同一次上电会话
helper 为易失数据；跨断电、温度、BER、熵和唯一性未测
```

### 02:13—02:25｜错误标签

**首选画面**

- 展示主 Notebook 的真实聚合结果：`kat_pass=289`、`tag_reject=289`。
- 若需要更直观的单例，在主 Notebook 跑完后补录一个**不保存进仓库**的临时实板单元，输出 `AUTH_FAILED / REJECT`。

**素材边界**

- 单例补拍用于视觉解释，不能替代主 Notebook 的 289 次聚合证据。
- 不使用旧 PYNQ release 或其他版本的拒绝截图冒充本次 PUF3 结果。

**旁白与逐句字幕原文**

1. 认证失败也必须正确处理：三种模式各拒绝 289 个坏标签。
2. 板上返回 AUTH_FAILED，调用方拿不到未认证明文。

**视频中必须标注**

- 主证据：`SW / MMIO / ISE: 289/289 bad-tag reject`
- 单例结果：`AUTH_FAILED / REJECT`
- 安全状态：`plaintext not released`
- 补拍说明：`补充单例演示 · 聚合数据来自主 Notebook`

### 02:25—02:37｜FPGA 实现与验证边界

**画面**

- 左侧放 PUF3 `timing_summary.rpt` 的摘要截图。
- 右侧放 `utilization.rpt` 中的资源数据。
- 底部持续显示 RO 限制，不要只做全屏绿色 `PASS`。

```text
Vivado 2025.2 · xc7z020clg400-1
CPU/Ascon/总线已约束时钟域：WNS +0.104 ns
WHS +0.041 ns · TNS/THS 0 · DRC Error 0
LUT 18,674 · FF 32,002 · BRAM 34.5 · DSP 4
RO 振荡环计数器域：NOT SIGNED OFF
```

**旁白口径**

- 只能说“CPU 与 Ascon 的已约束时钟域通过”。
- 不能把正 WNS 扩展成“整个设计所有时钟域均已签核”。

**旁白与逐句字幕原文**

1. CPU 与 Ascon 的已约束时钟域满足百兆时序。
2. 但 RO 计数器域仍未签核，不能声称整个设计全部通过。

**视频中必须标注**

- `Vivado 2025.2 · xc7z020clg400-1`
- `CPU / Ascon / bus @ 100 MHz`
- `WNS +0.104 ns`
- `WHS +0.041 ns`
- `TNS 0 · THS 0`
- `DRC Error 0`
- `LUT 18,674 · FF 32,002 · BRAM 34.5 · DSP 4`
- 黄色警示条：`RO oscillator counter domain: NOT SIGNED OFF`
- 证据类型：`post-route implementation report`

### 02:37—02:50｜PYNQ Skill

**画面**

1. 0—5 s：展示 `skill/pynq-overlay-workflow/SKILL.md` 的目录和命令入口。
2. 5—10 s：打开 `data/skill/l3_20261031_063709/40_summary.json`。
3. 10—13 s：四段结果逐个点亮 `PASS`。

```text
00_preflight        PASS
10_ascon_release    PASS
20_non_ascon_gpio   PASS
30_non_ascon_dma    PASS
```

**边界说明**

- DMA 是非 Ascon 的独立样例，不说它属于 PUF3 内部功能。
- L2 是 `simulated`，L3 才是本次实板汇总；成片不扩展成跨平台或长期稳定性已证明。

**旁白与逐句字幕原文**

1. 这些检查已整理成可复用 PYNQ Skill。
2. 实板验证覆盖工件、Ascon、GPIO 和非 Ascon DMA。

**视频中必须标注**

- 流程：`工件核验 → 加载 overlay → 寄存器访问 → 黄金比对 → 报告收集`
- `00_preflight: PASS`
- `10_ascon_release: PASS`
- `20_non_ascon_gpio: PASS`
- `30_non_ascon_dma: PASS`
- 证据级别：`L3 hardware_measured`
- DMA 角标：`独立非 Ascon 示例，不属于 PUF3 内部功能`

### 02:50—03:00｜收束

**画面**

- 2 s 板卡实拍，3 s Jupyter `PASS`，2 s 性能表，3 s 末屏。
- 末屏只保留项目名和一行边界，不重复整段数据。

```text
RISC-V Lightweight Cryptography SoC
Ascon-AEAD128 · SW / MMIO / ISE · RO-PUF

当前 PUF 为同次上电功能结果；
跨上电、BER、温度、熵、唯一性及 RO 计数器域时序仍待验证。
```

**旁白与逐句字幕原文**

1. 从标准算法到 RISC-V，再到三模式加速和 PUF，实板结果与原始记录构成完整证据链。

**视频中必须标注**

- 项目名：`RISC-V Lightweight Cryptography SoC`
- 技术路径：`Ascon-AEAD128 · SW / MMIO / ISE · RO-PUF`
- 末屏边界：`当前 PUF 为同次上电功能结果`
- 末屏边界：`跨上电 / BER / 温度 / 熵 / 唯一性 / RO 时序仍待验证`

## 三、实机素材获取步骤

### A. PUF3 主运行录屏（对应 00:46—01:20、01:47—02:13、02:13—02:25）

这是最重要的一组素材，争取一次录全，后期再切成三段。

1. **准备板卡**
   - 使用正点原子领航者 ZYNQ7020、`xc7z020clg400-1`，接入 PYNQ 2.7 镜像和以太网。
   - 在浏览器打开实际板卡的 Jupyter 地址（常见默认入口是 `http://192.168.2.99:9090`，以现场网络为准）。
   - 确认仓库位于 `/home/xilinx/jupyter_notebooks/amd_fpga_2026`。若路径不同，只能在 Notebook 第一单元设置 `ASCON_REPO`，不要移动 candidate 或改其它文档。

2. **核对待测工件**
   - 打开 `src/pynq_puf3/pynq_puf3_board_test.ipynb`。
   - 确认其指向：
     - `board/vivado_zynq7000_xc7z020_pynq_puf3/candidate/pynq_puf3.bit`
     - `board/vivado_zynq7000_xc7z020_pynq_puf3/candidate/pynq_puf3.hwh`
     - `board/vivado_zynq7000_xc7z020_pynq_puf3/candidate/manifest.json`
   - 当前参考哈希前缀为 bit `769ed24c…`；正式录制仍应以现场 `manifest.json` 和 Notebook 自检结果为准。

3. **启动录屏**
   - 1080p 录屏从 Notebook 页面顶部开始，包含文件名、第一代码单元和菜单。
   - 同时用相机拍摄板卡与屏幕同框 10—15 s；板卡和 Jupyter 应在同一镜内出现一次。
   - 录屏不要弹出浏览器书签、账号密码或无关聊天窗口。

4. **确认参数**
   - 第一单元应包含 `FULL_KAT = True`、`WARMUP = 5`、`REPETITIONS = 30`、`KAT_COUNT = 529`、`RECONSTRUCTS = 5`。
   - 不要为了缩短视频把 `FULL_KAT` 改成 `False` 后仍声称 289/289。

5. **从头执行**
   - 点击 `Kernel → Restart Kernel and Run All Cells`。
   - 持续录到最后一个单元返回：

   ```text
   status: PASS
   sections:
   - kat: PASS
   - benchmark: PASS
   - puf: PASS
   ```

   - 中途会先测量 3 s CPU 时钟，再运行 289 组 KAT 和 benchmark；等待段可后期加速，但必须标注“真实执行，过程加速”。

6. **确认结果**
   - 终端中应出现三行：`kat sw 289`、`kat hw 289`、`kat ise 289`。
   - benchmark 应给三模式加密/解密中位周期和相对 SW 加速比。
   - PUF 段应出现 `enroll OK`、五次 `reconstruct OK`、`hwkey_on`、`hwkey_off`。
   - 第一代码单元打印的 `OUT` 就是本次证据目录，通常是 `data/pynq_puf3/notebook_<时间>/`。

7. **补录结果特写**
   - 在同一 Jupyter 会话新开**临时单元**，只打印可公开字段，不修改 Notebook 文件：

   ```python
   bench = result["sections"]["benchmark"]
   for mode in ("sw", "hw", "ise"):
       print(mode, {
           "encrypt_median": bench["modes"][mode]["encrypt"]["summary"]["median"],
           "decrypt_median": bench["modes"][mode]["decrypt"]["summary"]["median"],
       })
   print("speedup", bench["speedup_median_vs_sw"])
   ```

   - 再用另一个临时单元单独展示 PUF 结论字段：

   ```python
   puf = result["sections"]["puf"]
   print({
       "enroll_quality": puf["enroll_quality"],
       "reconstructs_stable": puf["reconstructs_stable"],
       "caller_key_rejected_under_puf_key": puf["caller_key_rejected_under_puf_key"],
       "same_ciphertext_after_reconstruct": puf["same_ciphertext_after_reconstruct"],
       "kat_restored_after_hwkey_off": puf["kat_restored_after_hwkey_off"],
   })
   ```

   - 以上两个临时单元只用于拍摄；录制结束后删除或留作未保存，不要并入正式仓库文件。

8. **保存与导出证据**
   - 从 `OUT` 目录下载 `result.json` 和 `mailbox_log.txt`。
   - 视频文件名建议使用录制日期；另存原始完整录屏、剪辑工程、字幕文件、成片和最终 `result.json`。
   - 在复制到 Windows 后计算哈希：

   ```powershell
   Get-FileHash -Algorithm SHA256 .\result.json
   Get-FileHash -Algorithm SHA256 .\mailbox_log.txt
   ```

9. **隐私保护**
   - 不要打开或展示 PUF 帧中的 `DNA / REF / MASK / RAW / DITHER` 原始值。
   - 不要展示 PYNQ 登录密码、终端历史中的个人路径、真实业务密钥或网络上无关信息。

### B. 单个坏标签拒绝补拍（对应 02:13—02:25，可选）

主 Notebook 已经实际执行 289 次坏标签拒绝，但只打印聚合数量。若必须让观众看到一次明确的 `AUTH_FAILED`，可在主 Notebook 全部执行完成后，在同一 Jupyter 会话新开临时单元运行下面的补拍代码。它使用同一 candidate 和同一 PUF3 bitstream，不改变正式 Notebook 的 289 次聚合结果。

```python
import pynq
from ascon_host_api import AsconHost, AuthenticationError
from mailbox_backend import MailboxBackend
from board_benchmark import select_kat_case

overlay = pynq.Overlay(str(CANDIDATE / "pynq_puf3.bit"), download=True)

def mmio(name):
    d = overlay.ip_dict[name]
    return pynq.MMIO(d["phys_addr"], d["addr_range"])

transport = PynqPuf3Transport(
    Puf3BridgeRegs(mmio("pynq_ctl_0"), mmio("pynq_mbox_0")),
    expected_firmware_id=FIRMWARE_ID,
)
backend = MailboxBackend(transport, mode="hw", timeout_s=30)
host = AsconHost(backend)

c = select_kat_case()
k, n, ad, pt, ct = (c[x] for x in ("Key", "Nonce", "AD", "PT", "CT"))
bad_tag = ct[-16:-1] + bytes([ct[-1] ^ 1])

try:
    host.decrypt(k, n, ad, ct[:-16], bad_tag, timeout_s=10)
except AuthenticationError:
    print("AUTH_FAILED / REJECT: plaintext not released")
else:
    raise RuntimeError("bad tag unexpectedly accepted")
```

拍摄时先展示临时单元代码，再展示实际输出的 `AUTH_FAILED / REJECT`。字幕注明“补充单例演示；289/289 聚合结果来自主 Notebook”。

### C. 性能图表（对应 01:20—01:47）

1. 从本次 `result.json` 读取 `sections.benchmark`，不要手工抄旧稿。
2. 制作两张柱状图：
   - 加密：SW 21,862、MMIO 1,369、ISE 3,895 cycles。
   - 解密：SW 22,562、MMIO 1,213、ISE 4,288 cycles。
3. 在图上同时标 `raw median` 与 `speedup vs SW`。
4. 所有图统一加：`KAT #529 · PT 16 B · AD 0 B · warmup=5 · n=30 · RV32 AEAD mcycle`。
5. 图表角落加：`不含 PS/Python/UART 开销`。
6. 若新录像结果与上表不同，删除上表数值，以新 JSON 重建图表和重配旁白。

### D. FPGA 实现截图（对应 02:25—02:37）

1. 截图来源：
   - `board/vivado_zynq7000_xc7z020_pynq_puf3/candidate/reports/timing_summary.rpt`
   - `board/vivado_zynq7000_xc7z020_pynq_puf3/candidate/reports/utilization.rpt`
   - 边界说明可引用 `ro_corner_sta.txt`
2. 只截取 WNS/WHS/TNS/THS、DRC 状态和资源摘要，避免铺满整屏长日志。
3. 加标签：`Vivado 2025.2 post-route report · xc7z020clg400-1`。
4. RO 域使用明显的黄色告警条：`RO oscillator counter domain not signed off`。
5. 这一段是静态实现报告素材，不需要重新跑 Vivado；不得把截图称为新的板级测量。

### E. Skill 片段（对应 02:37—02:50）

1. 直接打开并录屏：`skill/pynq-overlay-workflow/SKILL.md`。
2. 打开现存实板汇总：`data/skill/l3_20261031_063709/40_summary.json`。
3. 高亮四条 `PASS` 和 `claim_level=hardware_measured`。
4. 若需要重跑以生成新素材，按顺序在 PYNQ 上执行：
   - `skill/ab_eval_pynq/test_board/l3_00_preflight.ipynb`
   - `l3_10_ascon_release.ipynb`
   - `l3_20_gpio.ipynb`
   - `l3_30_dma.ipynb`
   - `l3_40_summary.ipynb`
5. Skill 重跑不是本 3 分钟视频的必要前提；使用现有原始记录可减少正式录制风险。

## 四、录制前检查清单

- [ ] 板卡、PYNQ 镜像、网络和 Jupyter 正常，仓库路径为 `/home/xilinx/jupyter_notebooks/amd_fpga_2026`。
- [ ] 使用 PUF3 工程的 `candidate/pynq_puf3.bit` 和同名 `.hwh`，不是旧 `pynq/release/`。
- [ ] 记录正式录制时的 Git commit、`manifest.json`、bit/HWH SHA-256 和现场时间。
- [ ] Notebook 第一单元为 `FULL_KAT=True`、`WARMUP=5`、`REPETITIONS=30`、`RECONSTRUCTS=5`。
- [ ] 从头执行，保留 `control identity=PQF3`、`simulated=false`、`firmware_id=pynq-svc-puf3`。
- [ ] 保留三模式各 `289/289` KAT 和 `289/289` 坏标签拒绝。
- [ ] 性能表取自同一次 `result.json`，明确单位是 RV32 `mcycle`。
- [ ] PUF 原始诊断值全部裁掉或打码；不把 `quality=127` 解释成熵。
- [ ] 实现截图明确区分“CPU/Ascon 已约束域通过”和“RO 计数器域未签核”。
- [ ] 所有旁白配逐句实时字幕，字幕不遮挡终端核心数字。
- [ ] 保存原始录屏、板卡实拍、`result.json`、`mailbox_log.txt`、剪辑工程、成片和 SHA-256 清单。

## 五、片内口径与证据索引

| 项目 | 本次可使用的口径 | 来源 |
|---|---|---|
| 板卡与器件 | 正点原子领航者 ZYNQ7020；`xc7z020clg400-1` | `candidate/manifest.json` |
| overlay 身份 | `PQF3`；`firmware_id=pynq-svc-puf3`；`simulated=false`；`selftest_mask=7` | `notebook_20261031_114512/result.json` |
| 板端 KAT | SW、MMIO、ISE 各 289/289；坏标签各 289/289 拒绝 | 同上 |
| 接口边界 | PT ≤ 16 B；AD ≤ 16 B；只称“289 组容量内 KAT” | `result.json`、notebook |
| benchmark | KAT #529；PT 16 B；AD 0 B；warmup 5；n=30 | `result.json` |
| 加密周期 | SW 21,862；MMIO 1,369；ISE 3,895 cycles | 同上 |
| 解密周期 | SW 22,562；MMIO 1,213；ISE 4,288 cycles | 同上 |
| 加速比 | 加密：MMIO 15.969×、ISE 5.613×；解密：MMIO 18.600×、ISE 5.262× | 同上 |
| 时钟 | 寄存器推算 99.999999 MHz；`mcycle` 实测 99.9723 MHz | 同上 |
| FPGA 实现 | WNS +0.104 ns；WHS +0.041 ns；TNS/THS 0；DRC Error 0 | PUF3 candidate reports |
| 资源 | LUT 18,674；FF 32,002；BRAM 34.5；DSP 4 | `utilization.rpt` |
| PUF 单次上电 | `quality=127`；重建 5/5；HWKEY ON/OFF；KAT 恢复 | `result.json` |
| PUF 未完成项 | 跨上电、温度、BER、熵、唯一性未测；RO 计数器域未签核 | `result.json`、`ro_corner_sta.txt` |
| Skill | L3 实板 preflight/Ascon/GPIO/DMA 四段 PASS | `data/skill/l3_20261031_063709/40_summary.json` |

**成片禁止使用的表述**

- 不说“已通过全部 1,089 组板端 KAT”；板端当前只覆盖 289 组容量内 KAT。
- 不说“MMIO/ISE 加速 16×/5.6× 是 Jupyter 端到端加速”；该数字仅指 RV32 AEAD `mcycle`。
- 不说“PUF 已完成、可跨上电稳定重建、可用于安全启动”。
- 不说“整个 FPGA 设计 Timing 全部 PASS”；RO 振荡环计数器域未签核。
- 不说“PUF 密钥、RAW、DNA 不可读”；DNA/REF/MASK/RAW/DITHER 是设计中可读的诊断量。

> 本文件是拍摄与剪辑脚本，不代表已完成新视频或新的上板复测。正式录制后应以当天原始录屏、`result.json`、`mailbox_log.txt` 和工件哈希为准。

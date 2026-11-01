# 留出任务 T5（`t5_bram`）设计说明与"夹带"审计

状态：**已实现、已通过判分器自检，未跑正式实验（`not_run`）**。
按方案第 4 节，这个任务只用于检验泛化，**不得**用来改进 Skill；跑一次即冻结。

## 0. 先说被否掉的第一版

第一版做的是 **AXI GPIO 回环**（方向寄存器 + 通道 + 延迟）。做完自检（good 7/7、naive 0/7）之后
才发现：`skill/pynq-overlay-workflow/examples/axi_gpio.contract.json` 里正好有 AXI GPIO 的寄存器契约，
而且直接写着 `GPIO_TRI ... 1 = input` —— 也就是那道题最核心的陷阱。`examples/` 下三份契约分别是
`axi_dma_simple`、`axi_gpio`、`hls_vadd`，正好对应 T3、GPIO、T2。所以**只要题目涉及这三种 IP，
就不可能是干净的留出任务**。第一版因此作废（代码已删除，`fake_pynq` 里的 GPIO 模型也一并删除）。

## 1. 为什么换成 AXI BRAM

- BRAM 控制器（PG078）**没有寄存器表**：整段窗口就是内存，语义与"寄存器读写"完全不同。
- 在 Skill 的 `SKILL.md`、`references/`、`examples/`、`scripts/` 里检索 `bram`、`read-modify-write`、
  `byte` 均无对应内容（唯一的 `read-modify-write` 出现在 `tests/test_regmap.py`，讲的是寄存器字段的
  RMW，与字节粒度内存访问不是一回事）。
- 风险可控：只用已经验证过的 MMIO 通路，不引入中断/asyncio/新总线模型。

## 2. 任务

- IP：`xilinx.com:ip:axi_bram_ctrl:4.1`，容量 16 KiB 或 32 KiB，基址在 hwh 里给出。
- 工作区：`hw/bram.bit`、`hw/bram.hwh`、`hw/bram_window.h`（说明这不是寄存器堆、只有 32 位对齐访问、
  容量 = `C_HIGHADDR - C_BASEADDR + 1`）。
- 交付接口：

  ```python
  def poke_block(overlay, offset: int, data: bytes) -> None: ...
  def peek_block(overlay, offset: int, length: int) -> bytes: ...
  ```

- 提示词要求（三组相同）：按 VLNV 找 IP（基址/容量不写死）；只改被覆盖的字节、区间外字节保持原值；
  越界抛 `ValueError`；`peek_block` 返回长度正确的 `bytes`；可连续调用、写入后立即可读。

## 3. 隐藏场景（7 个）

| 场景 | 设定 | 判据 | 考什么 |
|---|---|---|---|
| `aligned_word` | 16 KiB，offset 0，16 字节 | 前 16 字节等于期望值 | 基本路径是否真的写进 PL |
| `unaligned_rmw` | 16 KiB，offset 5，3 字节 | 整个 16 字节窗口的 sha256 匹配 | 是否做读-改-写，且不碰同一字里的邻居字节 |
| `odd_length` | 16 KiB，offset 3，13 字节 | 前 20 字节 sha256 匹配 | 头尾不对齐时的字节级处理 |
| `hierarchical_32k` | IP 在 `io/bram_0`、基址 `0x42000000`、32 KiB，offset 0x1000，16 字节 | 前 0x1010 字节 sha256 匹配 | 是否按 VLNV 查 IP、容量从 hwh 取 |
| `past_the_end` | 4 KiB，offset 0xFFE，8 字节 | 必须抛 `ValueError` 且 BRAM 不变 | 越界写是否被拦下 |
| `read_past_the_end` | 4 KiB，offset 0xFFC，8 字节 | 必须抛 `ValueError` | 越界读是否被拦下 |
| `sequence` | 16 KiB，四次连续写入（0、2、4、0x1FFF） | 每步整窗 sha256 匹配 | 连续调用、重叠区间、写 0 覆盖 |

判分用窗口 sha256 而不是逐字节比较，原因：期望值整段塞进 `python -c` 命令行会超过 Windows 的
命令行长度上限（第一版就踩到了 `WinError 206`）。摘要比较仍是精确判等。

假 PYNQ 侧新增 `Bram`（`harness/fake_pynq/pynq/__init__.py`）：整段地址就是内存、按小端 32 位字读写、
未初始化区可预填、`span` 支持大于 64 KiB 的窗口（原来的 `_bus` 固定按 64 KiB 路由）。

## 4. 判分器自检（已跑）

```
t5_bram/good  -> 7/7
t5_bram/naive -> 3/7
```

- `good`：按 PG078 语义写的参考解（VLNV 查 IP、容量取 `addr_range`、字内做读-改-写、越界抛 `ValueError`）。
- `naive`：典型捷径（基址/容量写死 `0x40000000`/`0x1000`、按整字写不做 RMW、无范围检查）。
  失败在 `unaligned_rmw`、`odd_length`、`hierarchical_32k`、`sequence`。
- **已知弱点**：`past_the_end` 与 `read_past_the_end` 两个场景，`naive` 也"通过"了——因为假 PYNQ 的
  `MMIO` 本身就会对未对齐/越界访问抛 `ValueError`，与正确解法自行校验的效果相同。这两个场景因此只验证
  "错误会以 `ValueError` 形式暴露"，区分度有限，不能当作主要证据。
- 新增 `harness/tests/test_fake_pynq_api.py` 中的 2 个 BRAM 用例（小端字读写、邻居字节不被破坏、
  未对齐被拒、32 KiB 窗口可路由）；全套 7 个 API 用例通过。
- 其余四题的 good/naive 分数未变（T1 6/6·3/6、T2 6/6·0/6、T3 6/6·3/6、T4 8/8·0/8），变异测试仍 13/13。

## 5. 夹带审计

前提：**我读过 Skill 的 `SKILL.md`**（写作本文时为了核对重叠，还检索了它的 `references/` 与 `scripts/`）。
所以"干净房间"不存在。逐条列出判据出处：

| 判据 | 出处 | 与 Skill 重合？ |
|---|---|---|
| 按 VLNV 在 `ip_dict` 找 IP | PYNQ `Overlay.ip_dict` 的 `type` 字段 | **是**（Skill 第 41/50 行有同类规则；与 T1 要求 2 同类） |
| 4 字节对齐访问 | 提示词第 0 段已写明（硬件事实）+ Skill R5 | 部分：提示词本身已给出，Skill 不增加信息 |
| 越界抛 `ValueError` | 提示词第 3 条 | 部分：Skill R5 也讲"偏移 < addr_range"，但 `ValueError` 的约定来自提示词 |
| 时间/容量从 hwh 取 | 提示词第 1 条 + PG078 | 部分：Skill 也讲"从 `ip_dict` 的 `phys_addr`/`addr_range` 取" |
| 字节粒度读-改-写、保留邻居字节 | PG078（AXI4-Lite 只有 32 位字）| **否**（Skill 只讲寄存器字段 RMW） |
| 奇长度头尾处理 | 同上 | **否** |
| 连续调用、重叠区间、写 0 | 通用正确性 | 否 |
| 32 KiB 窗口/层级实例名 | hwh 元数据 | 部分是"不写死"的通用要求 |

结论：**7 个场景中，3 个（unaligned_rmw、odd_length、sequence）与 Skill 没有对应关系**；4 个属于
"通用良好实践 + 提示词已明说的硬件事实"的重合。没有任何一个场景对应 Skill 的具体门禁（clear-on-read、
64 位寄存器拆写、DMA flush/invalidate、golden 比对、报告收集），因为这些在 BRAM 题里根本用不到。

## 6. 正式实验（待批准）

```powershell
python skill/ab_eval_pynq/harness/make_trials.py --root C:\Nebula\HChenZ\Projects\ab_trials\run3 `
  --tasks t5_bram --reps 5 --model deepseek/deepseek-flash
powershell -ExecutionPolicy Bypass -File C:\Nebula\HChenZ\Projects\ab_trials\run3\run_all.ps1
python skill/ab_eval_pynq/harness/grade.py --root C:\Nebula\HChenZ\Projects\ab_trials\run3
python skill/ab_eval_pynq/harness/stats.py C:\Nebula\HChenZ\Projects\ab_trials\run3\results.csv
```

- 规模：3 组 × 5 次 = 15 次，约 1.75 小时。
- 单独报告，不并进 T1–T3 主指标；只回答"效果能否推广到一道新题"。
- 一次为限：跑完不改 Skill、不改题；若结果异常，先用 good/naive 复验仪器，再下结论。

## 7. 已知局限

- 设计者读过 Skill，夹带风险不为零；审计是缓解，不是证明。
- 两个越界场景区分度有限（见第 4 节）。
- 假 PYNQ 的 BRAM 是行为模型：没有 AXI 突发、没有总线延迟、没有位宽转换。
- n=5/组，只能发现"明显的"泛化失败。

## 8. 是否需要写 T5 的真实硬件工件（bit/hwh）？

**L2 不需要，写了也用不上。** 理由：

- `t5_bram` 的工件由 `harness/tasks.py:_t5_files()` 在判分时**确定性生成**：bit 是固定 seed 的 2048 字节，
  hwh 是按 `make_hwh()` 拼的 XML；假 PYNQ 用 **bit 文件的 sha256** 去找对应的硬件行为模型
  （`FAKE_PYNQ_SCENARIO` 里的 `hardware` 字典以 sha 为键）。换成真实 Vivado 产出的 bit/hwh，它的 sha 不在
  字典里，判分器根本不会加载任何设备，场景会全部失败。
- 也就是说：这一层测的是"主机代码在给定行为模型下是否正确"，工件本身只要满足结构（同名 .bit/.hwh、
  MEMRANGE 的 base/size、VLNV）就够，真实比特流不提供任何额外信息。
- 结论已经跑出来了（`p=1.0`，未复现差异），补一份真实 bit/hwh **也改变不了这个结论**；要提升泛化证据，
  应该换更多、由没读过 Skill 的人编写的留出题，而不是给这道题补硬件。

**什么情况下需要真实工件**：只有想把 T5 也搬到 L3（实板）时才需要——那要一个真实的 AXI BRAM overlay
（Vivado 里把 AXI BRAM Controller + Block Memory Generator 挂到 PS 的 M_AXI_GP 上，导出 .bit/.hwh），
再在板上跑一遍 `poke_block`/`peek_block`。这属于 L3 的范围，不是 L2 的缺口，而且优先级低于用现有
`board/vivado_zynq7000_xc7z020_pynq/release/` 把 L3 主流程（段 A–D）先跑通。

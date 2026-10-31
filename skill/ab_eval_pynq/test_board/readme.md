# PYNQ Skill L3 board Notebooks

owner TBD。这里存放 **人工 L3 验证**的上板入口。所有执行入口使用 Jupyter Notebook；
Skill 的通用实现和既有 pytest 仍位于 `skill/pynq-overlay-workflow/`，Notebook 只负责
编排、断言和保存证据。

本目录不进行 with/without/placebo 对照。L3 只回答：人工按照 Skill 流程，在真实 PYNQ
板上能否完成加载、身份校验、寄存器访问和 DMA 数据通路验证。

## 与 L2 结果的边界

L2 已归档的结果全部是假 PYNQ 上的 `simulated` 证据：T1–T3 主指标中
`with > without`（p=0.0425），但 `with vs placebo` 不显著（p=0.2248）；
独立留出任务 `t5_bram` 也未复现显著差异（p=1.0）。因此：

- L3 不通过重复 with/without/placebo 来“补显著性”。
- L3 成功只证明指定脚本和 Skill 工具在真实板上可运行，不证明因果提升。
- 报告必须同时引用 L2 的模型、n、p 值、留出失败和 `simulated` 边界。
- T3 DMA 是 L2 中最有区分度的任务，因此 L3 优先完成 DMA；T5 BRAM 不因 L2 结果追加实板工件。

## 执行顺序

1. `l3_00_preflight.ipynb`
2. `l3_10_ascon_release.ipynb`
3. `l3_20_gpio.ipynb`
4. `l3_30_dma.ipynb`
5. `l3_40_summary.ipynb`

每个 Notebook 均使用 `Restart Kernel and Run All Cells`，不要只运行部分单元。

## 板端目录和环境

所有 Notebook 固定使用以下仓库绝对路径，不读取环境变量或当前工作目录：

```text
/home/xilinx/jupyter_notebooks/amd_fpga_2026
```

板上仓库必须同步到这个位置。若要换路径，需要统一修改五个 Notebook 中的
`repo = Path("/home/xilinx/jupyter_notebooks/amd_fpga_2026").resolve()`，不能只设置环境变量。

`l3_00_preflight.ipynb` 默认冻结当前 Skill：

```text
skill/pynq-overlay-workflow/SKILL.md
SHA-256 = 967ccd78278580f96150a8e84177408dd189b265a5e04d1fc31ff45d9ec5f9ad
```

如需测试另一版本，必须显式设置其完整 SHA-256：

```bash
export L3_SKILL_SHA256=<64 hex characters>
```

不能通过删除断言绕过版本冻结。

Notebook 从 HWH 记录 FCLK0 设计值，同时把 PYNQ `Clocks.fclk0_mhz` 记为“寄存器派生观察值”。
厂家镜像的参考时钟假设可能使该读数失真，因此它不单独作为硬件失败门禁；真实频率仍以
Vivado/HWH、已有 mcycle 实测或其他独立测量为准。

## 当前非 Ascon 工件状态

- GPIO：使用板卡已有 PYNQ BaseOverlay 中名称含 `led` 的 AXI GPIO，不要求新建 bit/hwh。
- DMA：当前不提供非 Ascon 回环 bit/hwh，因此 `l3_30_dma.ipynb` 初始状态应为
  `NOT_RUN`。不得把 BaseOverlay 中未核实连接的 `axi_dma_0` 当作回环通过。

将来具备独立回环工件后设置：

```bash
export L3_DMA_DIR=/home/xilinx/l3_non_ascon_dma
# 或
export L3_DMA_BIT=/home/xilinx/l3_non_ascon_dma/design.bit
export L3_DMA_MANIFEST=/home/xilinx/l3_non_ascon_dma/manifest.json
```

manifest 必须列出同一实现生成的 bit、hwh 和需要的附加文件。只有 bit 没有 manifest
不足以形成可通过的 L3 证据。

## 原始结果

第一次预检创建：

```text
data/skill/l3_<yyyyMMdd_HHmmss>/
  00_preflight.json
  10_ascon_release.json
  20_non_ascon_gpio.json
  30_non_ascon_dma.json
  40_summary.json
  40_summary.md
data/skill/l3_current_session.json
```

`l3_current_session.json` 只是 session 指针。后续 Notebook 可覆盖：

```bash
export L3_RUN_DIR=/absolute/path/to/data/skill/l3_<timestamp>
```

原始 JSON 不覆盖，也不能只保留截图。执行后的 Notebook 应另存到同一 session 目录，
并计算 SHA-256。

最新 session 为 `l3_20261031_030131`：

- `00_preflight.json` PASS：关键依赖与 L2 归档哈希齐全，但未触碰硬件。
- `10_ascon_release.json` PASS：正式 release 加载、ID、服务能力、`simulated=false`
  和开机自检均通过。
- GPIO C PASS：`leds_gpio` 为 3-bit、`C_ALL_OUTPUTS=1`；`GPIO_DATA`
  写入 0/7/5/2 均读回一致，原始值 0 已恢复，错位 contract 被拒绝。
- DMA D `NOT_RUN`：没有非 Ascon DMA 回环 bit/hwh/manifest。
- 汇总 FAIL 且明确只有一项问题：`30_non_ascon_dma status=NOT_RUN`。

该 session 的预检哈希早于随后对 `l3_00`、`l3_30`、`l3_40` 的最新修改，不能与当前
代码继续混用。最终完成 L3 时必须用当前仓库重新运行 `l3_00` 创建新 session，
再执行 Ascon、GPIO、DMA 和汇总。

旧的 `l3_20261030_163953` 保留为历史 session，不进入新汇总。新汇总会拒绝缺少
`l2_evidence` 的旧预检，避免把不同源码或 L2 结果混入同一 L3 结论。

## 无界面执行

在板端仓库根目录按顺序执行，例如：

```bash
cd /home/xilinx/jupyter_notebooks/amd_fpga_2026
sudo -E env PYTHONPATH="$PWD" PATH="$PATH" \
  jupyter nbconvert --to notebook --execute \
  skill/ab_eval_pynq/test_board/l3_00_preflight.ipynb \
  --output l3_00_preflight.executed.ipynb \
  --output-dir data/skill
```

其余 Notebook 更换输入文件名和输出文件名。`l3_30_dma.ipynb` 在没有
DMA 工件时预期非零退出；这是缺失证据，不是脚本故障。

## L3 判定

完整功能 L3 至少需要：

- Ascon release：artifact 哈希、加载、IP/VLNV/FCLK、control/mailbox ID、服务握手通过。
- 非 Ascon GPIO：contract 校验、方向和值读回通过，原始状态已恢复。
- 非 Ascon DMA：有界传输、实际长度、flush/invalidate 路径、哨兵值、黄金比较通过。
- DMA 还应覆盖奇数长度、同长度连续调用和启动前拒绝超过最大传输长度的请求；
  `short_output`/缺失 TLAST 若没有专用可恢复测试源，必须写 `not_tested`，不能在正式回路上制造挂死。
- 至少一个负向门禁真实失败，例如篡改 manifest 在下载前被拒绝。

没有 DMA 工件时只能写 `PARTIAL` 或 `not_measured`，不能写完整 L3 通过。

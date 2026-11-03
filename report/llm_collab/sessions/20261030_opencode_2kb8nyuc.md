# PYNQ+PUF三模式加速比演示方案评估

- 工具：opencode；模型：claude-opus-5-5；会话：`ses_e74b72af5ffecyFEXq2Kb8NyuC`
- 开始：2026-10-30 13:29；用户提示 10 条；工具调用 280 次

## 用户提示（2026-10-30 13:29）

当前我们的PYNQ加上PUF没法运行三模式演示，三模型演示的意义是为了体现加速比，我们需要加上这个，请你检查当前项目，并告诉我能不能加上这个三模型演示，以及怎么加上；而当前只有PYNQ和PUF的方案意义又有什么

<details><summary>工具调用 2 次</summary>

- `shell` `git status --short | Select-Object -First 40; git log --oneline -8`
- `grep` `PUF`

</details>

<details><summary>工具调用 3 次</summary>

- `read` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf\readme.md`
- `read` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf`
- `glob` `board/vivado_zynq7000_xc7z020_pynq/*`

</details>

<details><summary>工具调用 3 次</summary>

- `read` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq\readme.md`
- `read` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq\build.tcl`
- `read` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf\build.tcl`

</details>

<details><summary>工具调用 1 次</summary>

- `grep` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\rtl`

</details>

<details><summary>工具调用 2 次</summary>

- `read` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\rtl\soc_top.v`
- `read` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\rtl\keys\key_mmio.v`

</details>

<details><summary>工具调用 2 次</summary>

- `grep` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\firmware\pynq_svc`
- `grep` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src`

</details>

<details><summary>工具调用 1 次</summary>

- `shell` `git diff --no-index --stat board/vivado_zynq7000_xc7z020_pynq/rtl_p0/ascon_mmio.v src/rtl/ascon/ascon_mmio.v; git diff --no-index --ignore-c`

</details>

<details><summary>工具调用 2 次</summary>

- `grep` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq\validation_20261029.md`
- `glob` `data/pynq_puf/**`

</details>

<details><summary>工具调用 1 次</summary>

- `read` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq\validation_20261029.md`

</details>

### 模型回答（2026-10-30 13:30）

**结论：** 能加，但现在这个 overlay 换一份固件跑不起来。真正卡住的是一处 RTL 行为：PUF 密钥一旦就绪，MMIO 加速器就会忽略 CPU 写入的 KEY。改起来不难，但要重新构建、仿真，还要上板测一次。按 11-01 冻结的时间，我建议这次先在同一个 Notebook 里依次加载两个 overlay，单 bitstream 版本放到后面。以下都是查代码得出的，我没有运行任何构建、仿真或板测。

## 一、现在为什么跑不了三模式

有三个原因，前两个容易解决，第三个才是主要障碍：

| # | 原因 | 证据 |
|---|---|---|
| 1 | 固件不同。PUF overlay 装的是 `ascon_keys.coe`（keys_rv32 v3，只输出 PUF 自检文字日志），不是三模式服务固件 `pynq_svc.coe` | `board/vivado_zynq7000_xc7z020_pynq_puf/build.tcl:10` |
| 2 | ID 不同。overlay 的 ID 是 `0x31554650`（"PFU1"），三模式客户端只接受 `0x514E5950`，按设计会拒绝 | `build.tcl:50`、`src/pynq/pynq_transport.py:47` |
| 3 | **RTL 密钥锁定。** `src/rtl/soc_top.v:572-575` 在复位后约 0.65 ms PUF 出密钥时，会把 `key_hw_sel` **自动、永久**置 1。之后 `ascon_mmio` 丢掉 CPU 写的 KEY0..3，改用 PUF 密钥（`ascon_mmio.v:191-194, 321`） | MMIO 模式用不了调用方给的 key，官方 KAT 必然失败，16.2× 的加速比也就测不出来 |

第 3 点正是 PYNQ 正式版钉住 `rtl_p0/`（无 PUF 版本）的原因，见 `board/vivado_zynq7000_xc7z020_pynq/readme.md` §4。SW 和 ISE 两个模式不受影响，因为它们是 CPU 上的软件和自定义指令，不走这个密钥通路。我比对过：两套 RTL 只有 `soc_top.v` 和 `ascon_mmio.v` 不一样，`ascon_mmio.v` 的差异只在这条密钥选择通路上。

这个问题不能靠只替换 bitstream 里的 BRAM 内容（updatemem）绕过去，因为它是逻辑问题。

## 二、怎么加上

### 方案 1：同一个 Notebook 加载两个 overlay（推荐本次提交用）
- 第一段加载 `pynq.bit`，跑已在实板验证过的三模式 KAT 和 benchmark。加密加速比 MMIO 16.221×、ISE 5.843×，见 `validation_20261029.md`。
- 第二段用 `Overlay()` 换成 `pynq_puf.bit`，跑 PUF 自检。切换只需重新加载 PL，几秒钟。
- 不改 RTL，也不用重新实现，工作量是 Notebook 加文档，约半天。
- 前提：`pynq_puf` 还没上过板（`data/pynq_puf/` 不存在），要先跑一次 `board_test.py` 拿到 PASS。
- 演示时要说清楚：两项能力来自两个 bitstream，不是同时在一颗 SoC 上运行。

### 方案 2：单 bitstream 同时有三模式和 PUF（真正合一，约 1–2 天，冻结前有风险）
1. **RTL**：新建一个独立目录，例如 `board/vivado_zynq7000_xc7z020_pynq_puf3/rtl/`，在副本里改 `soc_top.v` 和 `key_mmio.v`。不直接改共享的 `src/rtl/soc_top.v`，因为 10-27 的 JTAG PUF 板测 PASS 依赖它。
   - 把自动锁定改成软件控制：给 `key_mmio` CTRL 加一位 `USE_HW_KEY`，默认为 0，只有密钥就绪后写这一位才切到 PUF 密钥。
   - 这样 MMIO 默认用调用方的 key，KAT 和加速比都能复现；需要演示"PUF 密钥喂给 Ascon"时再显式打开。
2. **固件**：在 `src/firmware/pynq_svc/` 加一个服务帧（例如 `Y01P`），支持 enroll、reconstruct、读状态，返回 STATUS、DNA、quality、mismatch。逻辑从 keys_rv32 移植。原有 Y01Q/R/S/E 不动。
3. **Python**：`pynq_transport.py` 增加接受新 ID（例如 `PQF3`），并提供 `puf_status()` / `puf_enroll()`；Notebook 加一节 PUF。
4. **构建**：复制 `pynq_puf/build.tcl`，把 COE 换成 `pynq_svc.coe`，并保留 FIXED_IO/DDR 外接、RO pblock 和各项门禁。注意：PUF 版用正式版的策略 Performance_ExploreWithRemap 时序不满足（WNS −0.135），只有 Performance_RefinePlacement 达到 +0.208。新网表要重新跑实现并检查时序，可能还要再试几种策略。
5. **验证**：
   - 仿真：Icarus 跑真实 RV32 + pynq_svc + PUF RTL，包括三模式 KAT 和 PUF 帧，再加一个反例："不打开 USE_HW_KEY 时 MMIO KAT 必须通过"。
   - 模型测试：`test_pynq_transport.py` 回归。
   - 实板：三模式 KAT、benchmark 和 PUF 帧都要测。加速比要重新测，不能沿用正式版的数字。

## 三、只有 PYNQ+PUF 这个方案的意义

它的价值在于说明扩展可行，不在于性能。

- **第一次把 PUF 接到 PYNQ 平台上。** 之前唯一的 PUF 板测 PASS 来自 JTAG 工程，靠物理 CH340 串口读日志；正式 PYNQ 测试从没覆盖过 PUF。现在 PUF 可以从 Jupyter 控制和取证，演示平台和主线一致。
- **证明 PUF 能和完整的 RV32 SoC、PS7 在同一颗 XC7Z020 上共存，并且只用一个 100 MHz 时钟。** 已定义时钟的建立/保持时序为正，DRC 没有 Error 或 Critical Warning，1280 个 RO LUT 全部在 pblock 内，占用 18.5k LUT。
- **为方案 2 打底。** BD 结构、地址和门禁脚本都能直接复用，剩下要做的只是上面那处密钥锁定和固件。
- **要如实说明的限制：** 没有加速比；板测还没跑；每次运行都重新 enroll，只能证明同一次会话内可重复；REF/RAW/DNA 能通过 MMIO 读到，不能宣称保密；RO 采样时钟域没有完成时序签核。

需要的话，我可以先做方案 1（Notebook 和文档），或者直接在独立目录里开始方案 2。你选哪个？

## 用户提示（2026-10-30 13:36）

你直接开始做2吧

<details><summary>工具调用 3 次</summary>

- `read` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\firmware\pynq_svc\main.c`
- `read` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\firmware\pynq_svc\svc.h`
- `glob` `{src/firmware/pynq_svc/*,sim/pynq_puf/*,sim/pynq/*,src/pynq/*}`

</details>

<details><summary>工具调用 3 次</summary>

- `read` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\pynq\pynq_transport.py`
- `read` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\firmware\pynq_svc\build.sh`
- `read` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\sim\pynq\run_service.py`

</details>

<details><summary>工具调用 3 次</summary>

- `read` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\sim\pynq\tb_pynq_svc.v`
- `read` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\sim\pynq_puf\run.py`
- `read` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\sim\pynq_puf\tb_pynq_puf.v`

</details>

<details><summary>工具调用 3 次</summary>

- `glob` `src/firmware/**/*keys*/**`
- `read` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\firmware\pynq_svc\svc_io.c`
- `read` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\firmware\pynq_svc\ascon_modes.c`

</details>

### 模型回答（2026-10-30 13:36）

Now the keys_rv32 firmware, to port the PUF procedure.

<details><summary>工具调用 1 次</summary>

- `read` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\firmware\keys_rv32\main.c`

</details>

<details><summary>工具调用 1 次</summary>

- `read` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\rtl\keys\puf_key.v`

</details>

<details><summary>工具调用 2 次</summary>

- `read` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\pynq\mailbox_protocol.py`
- `read` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf\board_test.py`

</details>

<details><summary>工具调用 2 次</summary>

- `shell` `Get-Command riscv-none-elf-gcc,riscv64-unknown-elf-gcc,iverilog,vivado,bash -ErrorAction SilentlyContinue | Format-Table Name,Source -AutoSi`
- `grep` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\pynq`

</details>

<details><summary>工具调用 1 次</summary>

- `grep` `RISCV_TOOLCHAIN=|riscv-none-elf-gcc.*(\\|/)|Vivado\\2025.2|vivado.bat`

</details>

<details><summary>工具调用 1 次</summary>

- `shell` `Test-Path C:/wenjian/toolchain/xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf-gcc.exe; Test-Path C:/ruanjian/2025.2/Vivado/bin/vivado.`

</details>

<details><summary>工具调用 2 次</summary>

- `read` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\firmware\keys_v2\build.py`
- `read` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\rtl\pynq\pynq_soc.v`

</details>

<details><summary>工具调用 3 次</summary>

- `read` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf\puf_opt_pre.tcl`
- `read` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf\pynq_puf_timing.xdc`
- `read` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf\package.py`

</details>

<details><summary>工具调用 1 次</summary>

- `shell` `Get-Process vivado -ErrorAction SilentlyContinue | Format-Table Id,StartTime; New-Item -ItemType Directory -Force board/vivado_zynq7000_xc7z`

</details>

<details><summary>工具调用 1 次</summary>

- `shell` `python -c "b=open('src/rtl/soc_top.v','rb').read();  try:   b.decode('utf-8'); print('utf8 ok', b[:3], b.count(b'\r\n')) except Exception as`

</details>

<details><summary>工具调用 1 次</summary>

- `read` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf3\rtl\soc_top.v`

</details>

<details><summary>工具调用 4 次</summary>

- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf3\rtl\soc_top.v`
- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf3\rtl\soc_top.v`
- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf3\rtl\soc_top.v`
- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf3\rtl\soc_top.v`

</details>

### 模型回答（2026-10-30 13:38）

Now the key_mmio variant.

<details><summary>工具调用 4 次</summary>

- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf3\rtl\key_mmio.v`
- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf3\rtl\key_mmio.v`
- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf3\rtl\key_mmio.v`
- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf3\rtl\key_mmio.v`

</details>

<details><summary>工具调用 1 次</summary>

- `read` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\pynq\board_demo.py`

</details>

<details><summary>工具调用 1 次</summary>

- `grep` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\pynq\board_benchmark.py`

</details>

<details><summary>工具调用 1 次</summary>

- `read` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\pynq\board_benchmark.py`

</details>

<details><summary>工具调用 1 次</summary>

- `grep` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\pynq\mailbox_backend.py`

</details>

<details><summary>工具调用 1 次</summary>

- `read` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\pynq\mailbox_backend.py`

</details>

<details><summary>工具调用 1 次</summary>

- `write` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\firmware\pynq_svc_puf\puf_svc.h`

</details>

<details><summary>工具调用 1 次</summary>

- `write` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\firmware\pynq_svc_puf\puf_svc.c`

</details>

<details><summary>工具调用 2 次</summary>

- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\firmware\pynq_svc_puf\puf_svc.c`
- `shell` `Copy-Item src/firmware/pynq_svc/main.c src/firmware/pynq_svc_puf/main.c`

</details>

<details><summary>工具调用 6 次</summary>

- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\firmware\pynq_svc_puf\main.c`
- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\firmware\pynq_svc_puf\main.c`
- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\firmware\pynq_svc_puf\main.c`
- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\firmware\pynq_svc_puf\main.c`
- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\firmware\pynq_svc_puf\main.c`
- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\firmware\pynq_svc_puf\main.c`

</details>

<details><summary>工具调用 1 次</summary>

- `write` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\firmware\pynq_svc_puf\build.py`

</details>

<details><summary>工具调用 1 次</summary>

- `shell` `Get-ChildItem src/firmware/ascon_hw_rv32 | Select Name; Get-Content src/firmware/pynq_svc/bin2coe.py -TotalCount 15`

</details>

<details><summary>工具调用 1 次</summary>

- `shell` `python -X utf8 src/firmware/pynq_svc_puf/build.py`

</details>

<details><summary>工具调用 1 次</summary>

- `shell` `Get-Content build/local/pynq_svc_puf/compile.log`

</details>

<details><summary>工具调用 1 次</summary>

- `write` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\sim\pynq_puf3\tb_pynq_puf3.v`

</details>

<details><summary>工具调用 1 次</summary>

- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\sim\pynq_puf3\tb_pynq_puf3.v`

</details>

<details><summary>工具调用 1 次</summary>

- `write` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\sim\pynq_puf3\run.py`

</details>

<details><summary>工具调用 1 次</summary>

- `shell` `python -X utf8 sim/pynq_puf3/run.py 2>&1 | Select-Object -Last 60`

</details>

<details><summary>工具调用 4 次</summary>

- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\sim\pynq_puf3\tb_pynq_puf3.v`
- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\sim\pynq_puf3\tb_pynq_puf3.v`
- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\sim\pynq_puf3\run.py`
- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\sim\pynq_puf3\run.py`

</details>

<details><summary>工具调用 1 次</summary>

- `shell` `Copy-Item board/vivado_zynq7000_xc7z020_pynq_puf/puf_opt_pre.tcl board/vivado_zynq7000_xc7z020_pynq_puf3/; Copy-Item board/vivado_zynq7000_x`

</details>

<details><summary>工具调用 1 次</summary>

- `write` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf3\build.tcl`

</details>

<details><summary>工具调用 2 次</summary>

- `shell` `New-Item -ItemType Directory -Force build/local/pynq_puf3 | Out-Null; & C:/ruanjian/2025.2/Vivado/bin/vivado.bat -mode batch -nojournal -log`
- `shell` `python -X utf8 sim/pynq_puf3/run.py 2>&1 | Select-Object -Last 25`

</details>

<details><summary>工具调用 1 次</summary>

- `read` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\pynq\test_pynq_transport.py`

</details>

### 模型回答（2026-10-30 13:59）

Now the Python driver.

<details><summary>工具调用 1 次</summary>

- `write` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\pynq\pynq_puf3.py`

</details>

<details><summary>工具调用 2 次</summary>

- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\pynq\pynq_puf3.py`
- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\pynq\pynq_puf3.py`

</details>

<details><summary>工具调用 1 次</summary>

- `write` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\pynq\test_pynq_puf3.py`

</details>

<details><summary>工具调用 2 次</summary>

- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\pynq\test_pynq_puf3.py`
- `shell` ``$f='src/pynq/test_pynq_puf3.py'; (Get-Content $f -Raw -Encoding utf8).Replace("    from .mailbox_backend import MailboxBackend`r`n    from .``

</details>

<details><summary>工具调用 1 次</summary>

- `shell` `python -c "b=open('src/pynq/test_pynq_puf3.py','rb').read(); print(b[:4], b.count(b'\r\n'))"`

</details>

<details><summary>工具调用 1 次</summary>

- `shell` `python -c "p='src/pynq/test_pynq_puf3.py'; b=open(p,'rb').read(); b=b[3:] if b[:3]==b'\xef\xbb\xbf' else b; open(p,'wb').write(b); print(b[:`

</details>

<details><summary>工具调用 3 次</summary>

- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\pynq\test_pynq_puf3.py`
- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\pynq\test_pynq_puf3.py`
- `shell` `python -X utf8 src/pynq/test_pynq_puf3.py; python -X utf8 src/pynq/test_pynq_transport.py | Select-Object -Last 3`

</details>

<details><summary>工具调用 2 次</summary>

- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\pynq\test_pynq_puf3.py`
- `shell` `python -X utf8 src/pynq/test_pynq_puf3.py`

</details>

<details><summary>工具调用 1 次</summary>

- `write` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf3\board_test.py`

</details>

<details><summary>工具调用 1 次</summary>

- `grep` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\pynq\golden_checker.py`

</details>

<details><summary>工具调用 3 次</summary>

- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\pynq\test_pynq_puf3.py`
- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\pynq\test_pynq_puf3.py`
- `shell` `python -X utf8 src/pynq/test_pynq_puf3.py`

</details>

<details><summary>工具调用 1 次</summary>

- `shell` `Get-Content build/local/pynq_puf3/build.log -Tail 8; Get-ChildItem build/local/pynq_puf3/vivado/pynq_puf3.runs -ErrorAction SilentlyContinue`

</details>

<details><summary>工具调用 1 次</summary>

- `write` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf3\package.py`

</details>

<details><summary>工具调用 2 次</summary>

- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf3\package.py`
- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf3\package.py`

</details>

<details><summary>工具调用 1 次</summary>

- `shell` `$m = Get-ChildItem -Recurse build/local/pynq_puf3/vivado -Filter blk_mem_gen_0.mif -ErrorAction SilentlyContinue; $m | % FullName; if ($m) {`

</details>

<details><summary>工具调用 1 次</summary>

- `write` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf3\readme.md`

</details>

### 模型回答（2026-10-30 14:05）

Vivado 实现正在后台运行，等完成后再继续收尾。

<details><summary>工具调用 3 次</summary>

- `read` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf\explore_impl.tcl`
- `read` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf\finalize_run.tcl`
- `shell` `Select-String -Path build/local/pynq_puf3/vivado/reports/timing_summary.rpt -Pattern "^Slack \(VIOLATED\)|Source:|Destination:|Logic Levels|`

</details>

<details><summary>工具调用 2 次</summary>

- `write` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf3\explore_impl.tcl`
- `shell` `"impl_1 Performance_RefinePlacement routed (no post-route phys_opt) wns=-0.123 whs=0.027 (build.tcl gate stopped; CPU id_ex forwarding paths`

</details>

<details><summary>工具调用 1 次</summary>

- `shell` `& C:/ruanjian/2025.2/Vivado/bin/vivado.bat -mode batch -nojournal -log C:/wenjian/game/FPGA2026/ours/amd_fpga_2026/build/local/pynq_puf3/exp`

</details>

<details><summary>工具调用 1 次</summary>

- `write` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf3\finalize_run.tcl`

</details>

<details><summary>工具调用 3 次</summary>

- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf3\package.py`
- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf3\package.py`
- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf3\package.py`

</details>

<details><summary>工具调用 3 次</summary>

- `read` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\project_log\actual_progress.md`
- `read` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\project_log\development_log.md`
- `read` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\project_log\lessons_learned.md`

</details>

### 模型回答（2026-10-30 14:16）

`build.tcl` 的时序门禁拦下了第一次实现：WNS 为 −0.123 ns，所以没有生成 bit。违例路径都在 CPU 内部（id_ex 前递 → dcache），和 pynq_puf 历史上的违例位置相同，不在这次改动的 PUF/HWKEY 逻辑里。

现在在同一份综合网表上并行试 4 个实现策略，并都开启布线后 phys_opt；时钟和约束保持不变。结果出来后选一个通过门禁的运行生成 bit，再打包。

<details><summary>工具调用 1 次</summary>

- `shell` `foreach ($i in 2..5) { $r="build/local/pynq_puf3/vivado/pynq_puf3.runs/impl_$i"; $s = (Select-String -Path "$r/runme.log" -Pattern "Command:`

</details>

<details><summary>工具调用 2 次</summary>

- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf3\explore_impl.tcl`
- `shell` `$f='board/vivado_zynq7000_xc7z020_pynq_puf3/explore_impl.tcl'; $t=[IO.File]::ReadAllText($f); $t=$t.Replace('puts $fp "$r [get_property STRA`

</details>

<details><summary>工具调用 1 次</summary>

- `shell` `Select-String -Path build/local/pynq_puf3/vivado/pynq_puf3.xpr -Pattern '<Run Id="impl_\d"[^>]*' | % { ($_.Matches.Value -replace '.*Run Id=`

</details>

<details><summary>工具调用 1 次</summary>

- `shell` `& C:/ruanjian/2025.2/Vivado/bin/vivado.bat -mode batch -nojournal -log C:/wenjian/game/FPGA2026/ours/amd_fpga_2026/build/local/pynq_puf3/fin`

</details>

<details><summary>工具调用 1 次</summary>

- `shell` `python -X utf8 board/vivado_zynq7000_xc7z020_pynq_puf3/package.py | Select-Object -Last 4; Select-String -Path board/vivado_zynq7000_xc7z020`

</details>

<details><summary>工具调用 2 次</summary>

- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf3\build.tcl`
- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf3\build.tcl`

</details>

<details><summary>工具调用 2 次</summary>

- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf3\readme.md`
- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf3\readme.md`

</details>

<details><summary>工具调用 3 次</summary>

- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\project_log\actual_progress.md`
- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\project_log\development_log.md`
- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\project_log\lessons_learned.md`

</details>

<details><summary>工具调用 1 次</summary>

- `read` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\tasks\task_board.md`

</details>

<details><summary>工具调用 2 次</summary>

- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\tasks\task_board.md`
- `shell` `python -X utf8 board/vivado_zynq7000_xc7z020_pynq_puf3/package.py | Select-Object -Last 1; Get-Content board/vivado_zynq7000_xc7z020_pynq_pu`

</details>

<details><summary>工具调用 1 次</summary>

- `shell` `git log --oneline -3; git status --short | Select-String "puf3|pynq_svc_puf|pynq_puf3|project_log|task_board"`

</details>

<details><summary>工具调用 1 次</summary>

- `shell` `git diff --no-index --stat board/vivado_zynq7000_xc7z020_pynq_puf/pynq_puf_timing.xdc board/vivado_zynq7000_xc7z020_pynq_puf3/pynq_puf3_timi`

</details>

<details><summary>工具调用 1 次</summary>

- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf3\readme.md`

</details>

### 模型回答（2026-10-30 14:36）

方案 2 的离线部分做完了：同一个 bitstream 里既有 SW/MMIO/ISE 三模式服务，也有 PUF。仿真、模型测试、时序和 DRC 门禁都通过了，候选包在 `board/vivado_zynq7000_xc7z020_pynq_puf3/candidate/`。**还没上板**，三模式加速比要在这个新 bit 上重新测，不能沿用正式版的 16.2× / 5.8×。

**主要改动**（共享的 `src/rtl`、PYNQ 正式版、pynq_puf 和 JTAG 工程都没碰）：
- **RTL**：在新目录 `board/vivado_zynq7000_xc7z020_pynq_puf3/rtl/` 里放了两个文件的副本。PUF 密钥生成后不再自动接管 MMIO；只有软件写 CTRL[3] 打开 HWKEY 才切换，CTRL[4] 关闭，复位默认关闭。所以 MMIO 平时用调用方的 key，官方 KAT 照常能过。
- **固件**：`src/firmware/pynq_svc_puf/` 在原三模式服务基础上加了一组 PUF 命令（查状态、enroll、reconstruct、开/关 HWKEY），原有消息格式完全不变。开机自检前会强制关 HWKEY；PUF 只有降级密钥或重建不一致时，拒绝打开 HWKEY。
- **PS 端驱动**：新增 `src/pynq/pynq_puf3.py`，正式版的 `pynq_transport.py` 没改。新 overlay 的 ID 是 `PQF3`，正式版客户端和 PUF 自检版都会拒绝它，不会混用。

**验证结果**：
- **仿真**（`sim/pynq_puf3/run.py`，真实 RV32 + 固件）：正常用例 54 步全过。覆盖了开机自检三模式全过、36 个三模式 KAT，以及 PUF 流程：
  - HWKEY 打开后，MMIO 用官方 key 解官方密文会认证失败，说明确实换成了 PUF 密钥；
  - SW/ISE 不受影响，关掉 HWKEY 后 MMIO KAT 恢复。
- **反例**：同一份固件配原来的自动锁定 RTL，开机自检只剩 SW 和 ISE（mask 0x05），MMIO 丢失。这证明问题确实是 RTL 改动修好的。
- **Python 模型测试**：新驱动 12/12 通过；原有驱动回归 14/14 通过。
- **Vivado**：

  | 项 | 结果 |
  |---|---|
  | 第一次实现 | WNS −0.123 ns，门禁拦下，没出 bit |
  | 选用的实现 | 换策略后 WNS +0.104 ns、WHS +0.041 ns（违例路径都在 CPU 内部，不在这次改动的逻辑里） |
  | DRC | 0 个 Error 或 Critical Warning |
  | RO | 1280 个 LUT 全部保留 |
  | 资源 | 18674 LUT / 32002 FF / 34.5 BRAM / 4 DSP |
  | 一致性 | BRAM 初始化内容与固件逐字一致，HWH 里的 ID 和地址正确 |

**上板**：在板上运行下面的命令。它会依次检查身份、跑三模式 KAT、做 30 次基准测出加速比，再测 PUF 的 enroll、多次重建和 HWKEY。四段全过才返回 0。
```
sudo -E python3 board/vivado_zynq7000_xc7z020_pynq_puf3/board_test.py --candidate board/vivado_zynq7000_xc7z020_pynq_puf3/candidate --out data/pynq_puf3/board_<日期>_run1
```

**限制和未做的事**：
- **时序**：RO 采样部分没有完成时序签核，RO 的角落分析也没跑。
- **PUF 能证明什么**：每次复位都要重新 enroll，所以只能证明同一次上电内可重复，跨上电、熵、误码率、温度都没测。
- **安全性**：DNA 和 helper 数据能被读出来，HWKEY 只是固件策略，不能宣称保密。
- **构建脚本**：`build.tcl` 的默认配方已经改成这次通过的策略，但还没从头重跑验证过。

`project_log` 三个文件和 `tasks/task_board.md`（新增 P05）都已更新。没有提交。

## 用户提示（2026-10-30 14:39）

当前已经有了一版加入时序签核的版本，请你参照这个直接迁移一下吧

<details><summary>工具调用 1 次</summary>

- `shell` `git show --stat 5eb64a5 | Select-Object -First 40`

</details>

<details><summary>工具调用 2 次</summary>

- `shell` `git show --stat 5eb64a5 | Select-Object -Skip 40; git show 5eb64a5 -- board/vivado_zynq7000_xc7z020_pynq_puf/build.tcl board/vivado_zynq7000`
- `read` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf\ro_corner_sta.tcl`

</details>

<details><summary>工具调用 1 次</summary>

- `shell` `Copy-Item board/vivado_zynq7000_xc7z020_pynq_puf/ro_corner_sta.tcl board/vivado_zynq7000_xc7z020_pynq_puf3/ro_corner_sta.tcl; & C:/ruanjian/`

</details>

<details><summary>工具调用 1 次</summary>

- `shell` `$c = Get-Content build/local/pynq_puf3/vivado/reports/timing_summary.rpt; $i = ($c | Select-String "^Intra Clock Table" | Select -First 1).L`

</details>

<details><summary>工具调用 1 次</summary>

- `shell` `Select-String -Path build/local/pynq_puf3/vivado/reports/timing_summary.rpt -Pattern "^(clk_fpga_0|ro_clk)\s+-?\d|^(clk_fpga_0|ro_clk)\s+(cl`

</details>

<details><summary>工具调用 1 次</summary>

- `shell` `Select-String -Path build/local/pynq_puf3/vivado/reports/timing_summary.rpt -Pattern "^\s*ro_clk\s" -Context 0,0 | Select -First 5 | % Line;`

</details>

<details><summary>工具调用 4 次</summary>

- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf3\package.py`
- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf3\package.py`
- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf3\package.py`
- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf3\package.py`

</details>

<details><summary>工具调用 3 次</summary>

- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf3\build.tcl`
- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf3\build.tcl`
- `shell` `python -X utf8 board/vivado_zynq7000_xc7z020_pynq_puf3/package.py | Select-Object -Last 1; Get-Content board/vivado_zynq7000_xc7z020_pynq_pu`

</details>

<details><summary>工具调用 3 次</summary>

- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf3\readme.md`
- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf3\readme.md`
- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf3\readme.md`

</details>

<details><summary>工具调用 2 次</summary>

- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\project_log\actual_progress.md`
- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\project_log\development_log.md`

</details>

### 模型回答（2026-10-30 14:50）

迁移完成。pynq_puf3 现在和 pynq_puf 提交 5eb64a5 用同一套方法签核，**bit 没有变**，sha256 仍是 `56b3bc45…`。原因是 pynq_puf3 第一次构建时，已经用上了那份把 ro_clk 声明为 100 MHz 四分频的约束文件，内容和 5eb64a5 逐字节一致。所以这次只补了分析脚本和打包检查，没有重新实现。

**三块电路的签核状态：**

| 部分 | pynq_puf3 | pynq_puf（5eb64a5） |
|---|---|---|
| CPU / Ascon / 总线（100 MHz） | ✅ WNS +0.104 / WHS +0.041 | WNS +0.062 / WHS +0.009 |
| PUF 采样控制（25 MHz 的 ro_clk） | ✅ WNS +24.822 / WHS +0.115；和 CPU 之间的跨域路径两个方向都通过（+3.742/+0.216、+6.994/+0.428） | WNS +16.371 / WHS +0.146 |
| 振荡环计数器（256 × 20 位） | ❌ 未签核 | ❌ 未签核 |

振荡环计数器用 `ro_corner_sta.tcl`（只做分析、不改 bit）在这次的布线结果上跑了一遍，退出码 0：

| 角 | 环周期 | 最快环 | 计数器 setup 最差 | 计数器 hold 最差 |
|---|---|---|---|---|
| 慢角 | 3.473 ns | 288 MHz | −0.478 ns | −0.552 ns |
| 快角 | 1.194 ns | 837 MHz | −0.598 ns | −0.427 ns |

结论和 pynq_puf 一样：这一块只靠约束签不下来，必须改 PUF RTL。没有时钟约束的引脚剩 5120 个，全部来自振荡计数器。

**这次的改动**（都在 `board/vivado_zynq7000_xc7z020_pynq_puf3/` 下）：
- 新增 `ro_corner_sta.tcl`，是 5eb64a5 版本的逐字节副本。
- `build.tcl`：和 5eb64a5 一样，改为打开布线后 phys_opt 的结果再出 bit。新默认配方仍没有从头重跑验证。
- `package.py`：
  - 检查分析报告对应的就是出 bit 的那份布线结果；
  - 在 manifest 里写入三块签核状态和约束说明；
  - 注明 RO 实际放在区域内的数量，和分配数量分开报告。
- 重新打包通过，`candidate/reports/ro_corner_sta.txt` 已放进候选包。
- `readme.md`、`project_log/actual_progress.md`、`project_log/development_log.md` 已同步。

板测仍是 NOT_RUN，三模式加速比要等板上跑完 `board_test.py` 才能报。没有提交。

## 用户提示（2026-10-30 14:51）

你把这个最终版提交上去，让我队友上板测试

<details><summary>工具调用 1 次</summary>

- `shell` `git branch --show-current; git fetch origin 2>&1 | Select -Last 2; git status -sb | Select -First 3; git log --oneline -1 origin/main; git d`

</details>

<details><summary>工具调用 2 次</summary>

- `write` `C:\Users\HXZ\AppData\Local\Temp\opencode\stage_mine.py`
- `shell` `git check-ignore -v board/vivado_zynq7000_xc7z020_pynq_puf3/candidate/pynq_puf3.bit board/vivado_zynq7000_xc7z020_pynq_puf3/candidate/pynq_s`

</details>

<details><summary>工具调用 1 次</summary>

- `shell` `Get-Content .gitattributes -ErrorAction SilentlyContinue; git check-attr -a board/vivado_zynq7000_xc7z020_pynq_puf3/candidate/pynq_puf3.hwh `

</details>

<details><summary>工具调用 1 次</summary>

- `shell` `git diff --quiet -- .gitattributes; "clean=$LASTEXITCODE"`

</details>

<details><summary>工具调用 1 次</summary>

- `shell` ``$t = [IO.File]::ReadAllText('.gitattributes'); $t = $t.TrimEnd("`r","`n") + "`n`n# pynq_puf3 candidate (three-mode + PUF v1): bytes pinned b``

</details>

<details><summary>工具调用 1 次</summary>

- `shell` `python -c " import subprocess,hashlib,json m=json.load(open('board/vivado_zynq7000_xc7z020_pynq_puf3/candidate/manifest.json'))['artifacts']`

</details>

<details><summary>工具调用 1 次</summary>

- `shell` `$msg = @" feat(pynq-puf3): 三模式 SW/MMIO/ISE + PUF v1 单一 overlay（离线门禁通过，board NOT_RUN）  - 变体 RTL（board/vivado_zynq7000_xc7z020_pynq_puf3/rtl）：`

</details>

<details><summary>工具调用 2 次</summary>

- `write` `C:\Users\HXZ\AppData\Local\Temp\opencode\commit_msg.txt`
- `shell` `git commit -q -F C:\Users\HXZ\AppData\Local\Temp\opencode\commit_msg.txt; git log --oneline -1; git push origin main 2>&1 | Select -Last 2; `

</details>

### 模型回答（2026-10-30 14:53）

已提交并推送到 `origin/main`，提交号 **`f70ddc8`**（推送范围 `5eb64a5..f70ddc8`）。终端显示的退出码 1 是 PowerShell 把 git 的推送提示当成了错误，推送本身是成功的。

**提交里有什么：**
- 只包含这次 pynq_puf3 的文件：变体 RTL、固件、PS 驱动、仿真、构建和打包脚本、候选包 `candidate/`、板测脚本、readme。
- `project_log` 三个日志和 `tasks/task_board.md`，只提交了我写的那几段。这几个文件里别人还没提交的内容留在本地，没有混进去。
- `.gitattributes` 新增一行，让候选包保持原始字节，不做换行转换。否则在 Windows 上 checkout 后 hwh/coe 会变成 CRLF，板测的哈希校验会失败。
- 已核对：git 里存的 bit/hwh/固件和 `manifest.json` 记录的 sha256 一致。

**发给队友的上板步骤**（在板子的 Linux 上执行，要有 `pynq`）：
```bash
git pull                     # 到 f70ddc8 或更新
sudo -E python3 board/vivado_zynq7000_xc7z020_pynq_puf3/board_test.py \
  --candidate board/vivado_zynq7000_xc7z020_pynq_puf3/candidate \
  --out data/pynq_puf3/board_20261030_run1
```
- 脚本依次测四段，全部通过才返回 0，最后一行打印 `PASS` 或 `FAIL`：
  1. 身份：bit/hwh 哈希、ID `PQF3`、FCLK0 100 MHz、固件 ID；
  2. 三模式 KAT：6 个官方用例，加 `--full-kat` 跑 289 个；
  3. 基准：KAT #529，预热 5 次、采集 30 次，输出 SW/MMIO/ISE 的中位周期数和加速比；
  4. PUF：enroll，5 次重建都稳定，打开 HWKEY 后 MMIO 拒绝官方密文，换回后 KAT 恢复。
- 测完请把整个输出目录（`result.json`、`mailbox_log.txt`）原样发回来。目录名不能重复，脚本不会覆盖已有目录；第二次跑就改成 `run2`。
- 拿到 `result.json` 里的 `speedup_median_vs_sw` 以后，才能报这个 bit 的加速比。

**要注意：**
- `manifest.json` 里 `source_dirty` 是 true，因为打包时工作区还有别人未提交的改动。这是如实记录，不影响板测。
- 振荡环计数器部分仍未签核，板测结果出来前状态都是 NOT_RUN。

## 用户提示（2026-10-30 18:54）

vivado_zynq7000_xc7z020_pynq_puf3，在这个工程中，我们进行分频，但是这样会使得这个文件夹中的测试过不了

<details><summary>工具调用 1 次</summary>

- `shell` `$p='PCW_CRYSTAL_PERIPHERAL_FREQMHZ|PCW_FPGA0_PERIPHERAL_FREQMHZ|PCW_FCLK0_PERIPHERAL_DIVISOR\d|PCW_FCLK_CLK0_BUF|PCW_FCLK0_PERIPHERAL_CLKSRC`

</details>

<details><summary>工具调用 1 次</summary>

- `grep` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026`

</details>

<details><summary>工具调用 1 次</summary>

- `grep` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board`

</details>

<details><summary>工具调用 1 次</summary>

- `read` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_dma_cpu\pynq27_audit.md`

</details>

<details><summary>工具调用 1 次</summary>

- `read` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\atk_navigator_7020\vendor_findings.md`

</details>

<details><summary>工具调用 2 次</summary>

- `write` `C:\Users\HXZ\AppData\Local\Temp\opencode\ps7_probe.tcl`
- `shell` `& C:/ruanjian/2025.2/Vivado/bin/vivado.bat -mode batch -nojournal -nolog -source C:/Users/HXZ/AppData/Local/Temp/opencode/ps7_probe.tcl -not`

</details>

<details><summary>工具调用 1 次</summary>

- `shell` `Get-ChildItem -Recurse -Force .srcs | Select -First 10 FullName; git status --short -- .srcs .gen; Get-ChildItem -Force -Directory | ? { $_.`

</details>

<details><summary>工具调用 1 次</summary>

- `shell` `Remove-Item -Recurse -Force .srcs; Test-Path .srcs`

</details>

<details><summary>工具调用 3 次</summary>

- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\firmware\pynq_svc_puf\puf_svc.c`
- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\firmware\pynq_svc_puf\puf_svc.c`
- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\firmware\pynq_svc_puf\puf_svc.h`

</details>

### 模型回答（2026-10-30 18:58）

Now the Python driver.

<details><summary>工具调用 3 次</summary>

- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\pynq\pynq_puf3.py`
- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\pynq\pynq_puf3.py`
- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\pynq\pynq_puf3.py`

</details>

<details><summary>工具调用 3 次</summary>

- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\pynq\pynq_puf3.py`
- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\pynq\pynq_puf3.py`
- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\pynq\pynq_puf3.py`

</details>

<details><summary>工具调用 1 次</summary>

- `webfetch` 

</details>

<details><summary>工具调用 1 次</summary>

- `webfetch` 

</details>

<details><summary>工具调用 5 次</summary>

- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf3\board_test.py`
- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf3\board_test.py`
- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf3\board_test.py`
- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf3\board_test.py`
- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf3\board_test.py`

</details>

<details><summary>工具调用 2 次</summary>

- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf3\board_test.py`
- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf3\board_test.py`

</details>

### 模型回答（2026-10-30 19:00）

Now build.tcl PS config.

<details><summary>工具调用 1 次</summary>

- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf3\build.tcl`

</details>

<details><summary>工具调用 7 次</summary>

- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\pynq\test_pynq_puf3.py`
- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\pynq\test_pynq_puf3.py`
- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\pynq\test_pynq_puf3.py`
- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\pynq\test_pynq_puf3.py`
- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\pynq\test_pynq_puf3.py`
- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\pynq\test_pynq_puf3.py`
- `shell` `python -X utf8 src/pynq/test_pynq_puf3.py 2>&1 | Select-String "PASS t_|FAIL|/" | % Line`

</details>

<details><summary>工具调用 1 次</summary>

- `shell` `python -X utf8 src/firmware/pynq_svc_puf/build.py | Select -Last 3; Rename-Item build/local/pynq_puf3/vivado vivado_iopll1600_62m5; Rename-I`

</details>

<details><summary>工具调用 2 次</summary>

- `shell` `& C:/ruanjian/2025.2/Vivado/bin/vivado.bat -mode batch -nojournal -log C:/wenjian/game/FPGA2026/ours/amd_fpga_2026/build/local/pynq_puf3/bui`
- `shell` `python -X utf8 sim/pynq_puf3/run.py 2>&1 | Select-Object -Last 3`

</details>

<details><summary>工具调用 2 次</summary>

- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf3\package.py`
- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf3\package.py`

</details>

<details><summary>工具调用 1 次</summary>

- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf3\readme.md`

</details>

### 模型回答（2026-10-30 19:11）

Waiting for the Vivado rebuild to finish.

<details><summary>工具调用 1 次</summary>

- `shell` `Select-String -Path build/local/pynq_puf3/build_iopll1000.log -Pattern "CRITICAL WARNING" | % { $_.Line.Substring(0, [Math]::Min(220, $_.Lin`

</details>

<details><summary>工具调用 1 次</summary>

- `shell` `@" 2026-10-30 rebuild with PS7 IO PLL pinned to the board (FBDIV 30, FCLK0 10x1): fresh build.tcl run impl_1 Performance_ExtraTimingOpt + po`

</details>

<details><summary>工具调用 1 次</summary>

- `shell` `python -X utf8 board/vivado_zynq7000_xc7z020_pynq_puf3/package.py | Select -Last 1; Get-Content board/vivado_zynq7000_xc7z020_pynq_puf3/cand`

</details>

<details><summary>工具调用 1 次</summary>

- `grep` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf3\readme.md`

</details>

<details><summary>工具调用 1 次</summary>

- `read` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf3\readme.md`

</details>

<details><summary>工具调用 2 次</summary>

- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf3\readme.md`
- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf3\readme.md`

</details>

<details><summary>工具调用 4 次</summary>

- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf3\readme.md`
- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\project_log\actual_progress.md`
- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\project_log\development_log.md`
- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\project_log\lessons_learned.md`

</details>

<details><summary>工具调用 1 次</summary>

- `shell` `git fetch origin 2>&1 | Out-Null; git log --oneline -3 origin/main; git log --oneline -1; $s = Get-Content C:\Users\HXZ\AppData\Local\Temp\o`

</details>

<details><summary>工具调用 1 次</summary>

- `shell` `git log --oneline --graph -8 main origin/main; git show --stat ff7360d | Select -First 25; git show --stat e92e782 | Select -First 20`

</details>

<details><summary>工具调用 1 次</summary>

- `shell` `git ls-tree -r --name-only origin/main -- src/pynq_puf3 src/pynq/pynq_puf3.py src/pynq/test_pynq_puf3.py board/vivado_zynq7000_xc7z020_pynq_`

</details>

<details><summary>工具调用 1 次</summary>

- `shell` `git show origin/main:src/pynq_puf3/pynq_puf3_board_test.ipynb > $env:TEMP\opencode\nb_upstream.ipynb; python -c " import json,sys nb=json.lo`

</details>

<details><summary>工具调用 3 次</summary>

- `write` `C:\Users\HXZ\AppData\Local\Temp\opencode\nb_dump.py`
- `shell` `python C:\Users\HXZ\AppData\Local\Temp\opencode\nb_dump.py`
- `read` `C:\Users\HXZ\AppData\Local\Temp\opencode\nb_dump.txt`

</details>

<details><summary>工具调用 1 次</summary>

- `shell` `python -c "print(open(r'C:\Users\HXZ\AppData\Local\Temp\opencode\nb_dump.txt',encoding='utf-8').read()[:200]); import os; print(os.path.gets`

</details>

<details><summary>工具调用 1 次</summary>

- `read` `C:\Users\HXZ\AppData\Local\Temp\opencode\nb_dump.txt`

</details>

<details><summary>工具调用 1 次</summary>

- `shell` `$b="$env:TEMP\opencode\fclk_backup"; New-Item -ItemType Directory -Force $b | Out-Null; foreach ($p in 'src/pynq/pynq_puf3.py','src/pynq/tes`

</details>

<details><summary>工具调用 1 次</summary>

- `shell` `git stash push -m "puf3-fclk-wip" -- board/vivado_zynq7000_xc7z020_pynq_puf3/board_test.py board/vivado_zynq7000_xc7z020_pynq_puf3/candidate`

</details>

<details><summary>工具调用 1 次</summary>

- `shell` `git status --porcelain | Select-String "^(UU|AA|DU|UD|AU|UA|DD) |pynq_puf3|actual_progress|task_board" | % Line`

</details>

<details><summary>工具调用 1 次</summary>

- `shell` `git rm -q board/vivado_zynq7000_xc7z020_pynq_puf3/board_test.py src/pynq/pynq_puf3.py src/pynq/test_pynq_puf3.py; git checkout --theirs -- b`

</details>

<details><summary>工具调用 1 次</summary>

- `shell` `python -c "b=open('src/pynq_puf3/pynq_puf3_board_test.ipynb','rb').read(); print(b[:300]); print(b.count(b'\r\n'), b[-60:])"`

</details>

<details><summary>工具调用 1 次</summary>

- `cactus_write` `C:\Users\HXZ\AppData\Local\Temp\opencode\patch_nb.py`

</details>

<details><summary>工具调用 2 次</summary>

- `write` `C:\Users\HXZ\AppData\Local\Temp\opencode\patch_nb.py`
- `shell` `python -X utf8 C:\Users\HXZ\AppData\Local\Temp\opencode\patch_nb.py; git diff --stat -- src/pynq_puf3/pynq_puf3_board_test.ipynb`

</details>

<details><summary>工具调用 1 次</summary>

- `shell` `python -X utf8 board/vivado_zynq7000_xc7z020_pynq_puf3/package.py | Select -Last 1; Get-Content board/vivado_zynq7000_xc7z020_pynq_puf3/cand`

</details>

### 模型回答（2026-10-30 19:49）

Now an offline harness that executes the notebook's own code against register models.

<details><summary>工具调用 2 次</summary>

- `write` `C:\Users\HXZ\AppData\Local\Temp\opencode\nb_harness.py`
- `shell` `python -X utf8 C:\Users\HXZ\AppData\Local\Temp\opencode\nb_harness.py 2>&1 | Select-String "PASS|FAIL|Error" | % Line`

</details>

<details><summary>工具调用 2 次</summary>

- `edit` `C:\Users\HXZ\AppData\Local\Temp\opencode\nb_harness.py`
- `shell` `python -X utf8 C:\Users\HXZ\AppData\Local\Temp\opencode\nb_harness.py 2>&1 | Select-String "PASS|FAIL|Error|FCLK0" | % Line`

</details>

<details><summary>工具调用 1 次</summary>

- `grep` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf3\readme.md`

</details>

<details><summary>工具调用 2 次</summary>

- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf3\readme.md`
- `grep` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf3\readme.md`

</details>

### 模型回答（2026-10-30 19:51）

Now fix my progress-log entry to match the notebook layout.

<details><summary>工具调用 1 次</summary>

- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\project_log\actual_progress.md`

</details>

<details><summary>工具调用 2 次</summary>

- `write` `C:\Users\HXZ\AppData\Local\Temp\opencode\stage_fclk.py`
- `shell` `git add board/vivado_zynq7000_xc7z020_pynq_puf3 src/firmware/pynq_svc_puf src/pynq_puf3/pynq_puf3_board_test.ipynb 2>$null; python C:\Users\`

</details>

<details><summary>工具调用 1 次</summary>

- `shell` `python -c " import subprocess,hashlib,json m=json.loads(subprocess.run(['git','show',':board/vivado_zynq7000_xc7z020_pynq_puf3/candidate/man`

</details>

<details><summary>工具调用 1 次</summary>

- `shell` `git rev-parse --short HEAD; git rev-parse --short origin/main`

</details>

<details><summary>工具调用 2 次</summary>

- `write` `C:\Users\HXZ\AppData\Local\Temp\opencode\commit_msg2.txt`
- `shell` `git commit -q -F C:\Users\HXZ\AppData\Local\Temp\opencode\commit_msg2.txt; git log --oneline -1; git push origin main 2>&1 | Select-String "`

</details>

### 模型回答（2026-10-30 19:52）

已修好并推送到 `origin/main`，提交号 **`aec180d`**。新 bit 的 sha256 是 `769ed24c…`，**还没上板**，需要队友重新跑一次 Notebook。测试门禁仍要求 100 MHz，没有放宽。

**原因：不是"分频"错了，是 bit 默认的 PLL 和板子上的不一致**
- PYNQ 加载 overlay 时只把 hwh 里的 FCLK0 分频值（4×4）写进 PS 寄存器，PLL 本身不动，仍是板子启动镜像设好的 1000 MHz。
- 但 Vivado 生成 bit 时自己按 1600 MHz 的 PLL 算出了 4×4。所以板上实际是 1000/16 = **62.5 MHz**。
- 屏幕上的 93.75 也不是真实频率：原版 PYNQ 2.7 按固定 50 MHz 参考时钟换算（v2.7.0 源码 `pynq/ps.py` 里是 `DEFAULT_SRC_CLK_MHZ = 50.0`），而这块板的晶振是 33.333333 MHz，换算出来是 50×30/16 = 93.75。
- 厂家 base 工程里 FCLK1 = 142.857 = 1000/7、FCLK3 = 200 = 1000/5，和板上 PLL 是 1000 MHz 对得上。

**改动：**
- **`build.tcl`**：把 PLL 固定为板上的 1000 MHz，FCLK0 分频改为 10×1，正好 100 MHz。从头重建后时序和之前一样：
  - CPU 时钟 WNS +0.104 ns、WHS +0.041 ns；
  - PUF 采样时钟 +24.822 / +0.115 ns；
  - DRC 0，1280 个 RO LUT 都在。
- **固件**：PUF 响应帧最后 8 字节改为发帧时刻的 CPU 周期计数，用来在板上直接测频率。
- **Notebook**（`src/pynq_puf3/pynq_puf3_board_test.ipynb`）：
  1. 下载前读寄存器，确认板上 PLL 和 bit 的假设一致，不一致就拒绝下载；
  2. 下载后按真实晶振从寄存器算出 FCLK0，必须为 100 ± 0.5 MHz；
  3. 用 CPU 周期计数对 PS 时间实测 3 秒，结果必须在 100 MHz ± 1% 以内。

  这是频率第一次真正被测出来，以前都只是配置值。
- **`package.py`**：打包时检查 hwh 的时钟配置并写进 manifest。上一版 bit `56b3bc45…` 作废。

**和队友的改动合并：** 队友已经把驱动和板测合成了一个 Notebook（e92e782 / ff7360d）。我先同步到他们的版本，再把上面的修正移进这个 Notebook，原来的 `.py` 文件没有恢复。

**验证结果：**
- 仿真 54 步全过，自动锁定反例仍能检出；原版传输层测试 14/14 通过。
- 另写了一个临时离线脚本（没提交），直接执行 Notebook 里的代码并模拟板子寄存器，6/6 通过：
  - 正常情况通过，推算 100.000 MHz、实测 99.997 MHz、PYNQ 显示 150；
  - PLL 不对时拒绝下载，分频 4×4 判为 62.5 MHz 失败，实测 62.5 MHz 失败，HWKEY 没生效时失败。

**请转告队友：**
- 拉取到 `aec180d` 后，在 Jupyter 里按顺序执行整个 Notebook。
- 打印里的 `PYNQ Clocks shows 150.0` 是正常现象，不是故障。以 `register-derived` 和 `measured` 两个值为准，都应接近 100。
- 如果出现 "refusing to download"，说明板上 PLL 和预期不同，请把 `result.json` 发回来，不要改门禁。

**另外一个需要你知道的问题：** PYNQ 正式版和 pynq_puf 的 hwh 也是同样的 4×4 配置，在这块板上实际同样跑在 62.5 MHz。它们的周期数和加速比不受影响，因为都按 CPU 周期计；但"板上 100 MHz"这个说法对它们不成立。这两个工程我没有改，要不要同样修正由你决定。

## 用户提示（2026-10-30 20:10）

我有一个问题，这个分频我记得是为了改善时序的问题，采用的部分分频，都是哪里进行了分频；PYNQ 正式版和 pynq_puf 的 hwh 也是同样的 4×4 配置这个又是什么意思，这里的测试是为了什么，我们要怎么说比较合适

<details><summary>工具调用 2 次</summary>

- `grep` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\docs\tech_report`
- `grep` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026`

</details>

### 模型回答（2026-10-30 20:10）

先说结论：项目里有两种完全不同的"分频"。你记得的那种是为改善时序做的，这次没有动；我改的是 PS 生成 FCLK0 时的分频，它不是时序优化，是这块板子上配错了。

## 1. 都有哪些分频

| 位置 | 是什么 | 目的 | 这次有没有改 |
|---|---|---|---|
| `soc_top.v` 里的 `ro_clk_div` | ro_clk = FCLK0 ÷ 4（25 MHz），经 BUFG 送给 PUF 采样控制逻辑 | **改善时序**：采样逻辑跑在低频；`pynq_puf_timing.xdc` 把它声明为生成时钟，所以能签核（ro_clk WNS +24.8 ns） | 没改，仍是 FCLK0 ÷ 4 |
| PS 内部：IO PLL ÷ DIVISOR0 ÷ DIVISOR1 → FCLK0 | Zynq 给 PL 提供时钟必须经过的分频器 | 不是时序手段，只决定 FCLK0 实际是多少 MHz | **改了**：4×4 改成 10×1 |
| UART `BAUD_CNT_MAX = 16` | 100 MHz ÷ 16 = 6.25 Mbaud 的波特率分频 | 只管串口速率 | 没改 |
| 其他目录：CPU-DMA 80 MHz 候选、PUF v2 修复方案 A2-a | 把 PS FCLK0 降到 80 MHz | 改善时序 | 和 pynq_puf3 无关 |

所以"为时序做的部分分频"指的是 ro_clk ÷ 4。它和 FCLK0 的比例这次保持不变。

## 2. "正式版和 pynq_puf 的 hwh 也是 4×4"是什么意思

FCLK0 是由两部分相乘决定的：
- **IO PLL 频率**：由板子启动镜像设定，PYNQ 加载 bit 时不会改它。
- **两个分频值**：写在 bit 配套的 hwh 里，PYNQ 加载时照着写进去。

Vivado 生成这三个工程的 bit 时，都默认 IO PLL 是 1600 MHz，于是算出 4×4（÷16），得到 1600 ÷ 16 = 100 MHz。但这块领航者板的启动镜像把 IO PLL 设成了 1000 MHz：

| 工程 | hwh 里的假设 | 板上实际 |
|---|---|---|
| PYNQ 正式版 | 1600 MHz ÷ 16 = 100 | 1000 ÷ 16 = **62.5 MHz** |
| pynq_puf | 同上 | **62.5 MHz** |
| pynq_puf3（第一版） | 同上 | 62.5 MHz（队友看到的 93.75 就是这个） |
| pynq_puf3（修正后） | 1000 MHz ÷ 10 = 100 | 100 MHz（等板测确认） |

队友看到的 93.75 也不是真实频率：原版 PYNQ 2.7 固定按 50 MHz 参考时钟换算，而这块板的晶振是 33.333333 MHz。

正式版的 62.5 MHz 是我根据相同的 hwh 配置、93.75 这个读数和厂家 base 工程推出来的，没有在正式版上实测。

**对已有结果的影响：**
- **仍然有效**：功能和 KAT 结果；所有 cycles 数和加速比（16.2× / 5.8×），因为都按 mcycle 计，和频率无关；Python 墙钟时间（ms），那是实际测到的时间。另外，芯片实际跑得比签核频率慢，时序裕量只会更大，不会出错。
- **不成立**：
  - "板上以 100 MHz 运行"这个说法；
  - 任何用"cycles ÷ 100 MHz"换算出来的绝对耗时或吞吐量；
  - pynq_puf 的 ro_clk 实际只有约 15.6 MHz。PUF 的采样窗口按时钟周期计数，所以窗口时长被拉长约 1.6 倍，计数器更容易溢出回绕。这一点会影响对 PUF 结果的解读。

## 3. 新加的时钟测试是为了什么

1. **确认实际运行的频率就是签核时的频率。** 时序报告只对 100 MHz 成立：实际偏低，"100 MHz"的说法就是错的；实际偏高，可能违反时序，导致结果不可信。所以下载前先核对板上 PLL，不一致就拒绝下载，避免超频运行。
2. **补上一直缺的"独立频率测量"。** 报告里这一项目前写的是 not_measured。新 Notebook 用两种独立的方法确认 100 MHz：
   - 从寄存器按真实晶振推算；
   - 用 CPU 周期计数对 PS 时间实测 3 秒。

## 4. 建议的说法

技术报告目前写的是"PS7 FCLK0 配置 100 MHz；独立频率 not_measured"，没有声称实测，所以不算错。但"配置 100 MHz"在这块板上并不准确，建议改成：

> 工程按 FCLK0 = 100 MHz 完成时序签核（WNS +0.034 ns）。PYNQ 加载 overlay 时只写入 hwh 中的 FCLK0 分频（÷16），IO PLL 沿用板卡启动镜像（33.333 MHz × 30 = 1000 MHz），因此该 release 在板上的 FCLK0 推算为 62.5 MHz，低于签核频率。性能与加速比均以 CPU 周期（mcycle）计，与时钟频率无关；本文不给出按 100 MHz 换算的绝对时间，也不声称板上以 100 MHz 运行。pynq_puf3 版本已将 PS 时钟按板卡 PLL 配置，板上频率经寄存器推算和 mcycle 实测双重确认（待板测）。

最后一句要等 pynq_puf3 板测通过后才能写"已确认"。

**想把正式版的 62.5 MHz 从推算变成实测证据，不需要重建 bit。** 让队友在加载正式版 overlay 之后跑下面这段，读的是同一组寄存器：
```python
from pynq import MMIO
s = MMIO(0xF8000000, 0x200)
io, f0 = s.read(0x108), s.read(0x170)
fbdiv, d0, d1 = (io >> 12) & 0x7F, (f0 >> 8) & 0x3F, (f0 >> 20) & 0x3F
print(fbdiv, d0, d1, 33.333333 * fbdiv / d0 / d1)   # 预期 30 4 4 62.5
```

**还没做的：**
- 正式版处于冻结状态，我没有改它的工程和 bit；离 11-01 时间紧，建议只改说法、不重建。
- 技术报告的正文和图（`ch01`–`ch04`、`app04`、`fig_2_1`、`fig_2_2` 里的"FCLK0 100 MHz"）还没改。

需要的话，我可以按上面的口径去改这些报告和图。

## 用户提示（2026-10-30 20:14）

现在的三模加PUF转换不就是正式版吗

### 模型回答（2026-10-30 20:14）

现在还不是。按仓库现状和项目文档，"正式版"和 pynq_puf3 是两套东西：

| | PYNQ 正式版 | pynq_puf3（三模式 + PUF） |
|---|---|---|
| 位置 | `board/vivado_zynq7000_xc7z020_pynq/release/pynq.bit` | `board/vivado_zynq7000_xc7z020_pynq_puf3/candidate/pynq_puf3.bit` |
| RTL | `rtl_p0`，不含 PUF | 变体 RTL，含 PUF + HWKEY 开关 |
| 控制 ID / 固件 | `PYNQ` / `pynq-svc-v1` | `PQF3` / `pynq-svc-puf3` |
| 板测 | 已通过：KAT、Notebook、基准、错误恢复 | **NOT_RUN**，等队友测这个新 bit |
| 时钟 | hwh 写 4×4，板上推算 62.5 MHz | 已修正为 10×1，目标 100 MHz（待实测） |
| 现在被谁引用 | 技术报告、16.2× / 5.8× 加速比、`AGENTS.md` 里的"主线" | 只在它自己的 readme、日志和任务板 P05 |

`AGENTS.md` 现在写的是"独立 RO-PUF/DNA 原型保留为扩展展示，不混入当前 overlay"。所以 pynq_puf3 目前的定位是"候选"，还不是"正式版"。

**如果你决定把 pynq_puf3 作为提交用的正式版**，上一条里关于正式版的担心大部分就没有了：你们实际提交的 bit 时钟已经修正，报告可以直接写板上实测频率。但还要做下面这些，才算正式切换：

1. **板测通过**：队友跑完 Notebook，身份、时钟、KAT、基准、PUF 四段全过。
2. **换掉报告里的数据**：技术报告里的加速比、cycles、资源、WNS（+0.034 → +0.104）、频率，都换成 pynq_puf3 在板上实测的结果。旧正式版的数据只能作为历史版本保留，两套数字不能混用。
3. **改项目文档**：`AGENTS.md`、`README.md`、`docs/current_status_20261029.md`、`tasks/release_plan_20261101.md` 里"主线 = 旧 release、PUF 不混入 overlay"的说法要改。旧 release 保留，不删。
4. **旧正式版的频率另行说明**：如果报告里还引用它的历史证据，要注明它在板上实际是推算 62.5 MHz（只影响频率说法，cycles 和加速比不受影响）。

要我等队友板测通过后，按"pynq_puf3 = 提交正式版"去改这些文档和技术报告吗？还是你希望继续保持"旧正式版是主线、pynq_puf3 是扩展"？

## 用户提示（2026-10-30 20:41）

当前仍然存在问题，请你拉取我队友的代码再进行检查

<details><summary>工具调用 1 次</summary>

- `shell` `git fetch origin 2>&1 | Out-Null; git log --oneline -6 origin/main; git rev-parse --short HEAD; git diff --stat HEAD origin/main`

</details>

<details><summary>工具调用 1 次</summary>

- `shell` `git merge --ff-only origin/main 2>&1 | Select -Last 1; Get-ChildItem -Recurse data/pynq_puf3 | Select FullName; Get-Content data/pynq_puf3/n`

</details>

## 用户提示（2026-10-30 20:42）

data\pynq_puf3\notebook_20261030_123118你可以重点看一下这个文件夹

<details><summary>工具调用 1 次</summary>

- `shell` `git show 27f24bb -- src/pynq_puf3/pynq_puf3_board_test.ipynb | Select -First 150`

</details>

<details><summary>工具调用 1 次</summary>

- `write` `C:\Users\HXZ\AppData\Local\Temp\opencode\patch_nb2.py`

</details>

<details><summary>工具调用 2 次</summary>

- `edit` `C:\Users\HXZ\AppData\Local\Temp\opencode\nb_harness.py`
- `shell` `python -X utf8 C:\Users\HXZ\AppData\Local\Temp\opencode\nb_harness.py 2>&1 | Select-String "^PASS t_|^FAIL t_|/6" | % Line`

</details>

<details><summary>工具调用 3 次</summary>

- `shell` `python -X utf8 C:\Users\HXZ\AppData\Local\Temp\opencode\patch_nb2.py`
- `edit` `C:\Users\HXZ\AppData\Local\Temp\opencode\nb_harness.py`
- `shell` `python -X utf8 C:\Users\HXZ\AppData\Local\Temp\opencode\nb_harness.py 2>&1 | Select-String "^PASS t_|^FAIL t_|/8|FCLK0" | % Line`

</details>

<details><summary>工具调用 1 次</summary>

- `shell` `$f="$env:TEMP\opencode\nb_harness.py"; $t=[IO.File]::ReadAllText($f); $t=$t.Replace("mb = base.MboxModel(fw)","mb = base.MboxModel(fw, rx_de`

</details>

<details><summary>工具调用 1 次</summary>

- `shell` `python -X utf8 board/vivado_zynq7000_xc7z020_pynq_puf3/package.py | Select -Last 1; git status --porcelain -- board/vivado_zynq7000_xc7z020_`

</details>

### 模型回答（2026-10-30 20:44）

Now the log entries.

<details><summary>工具调用 3 次</summary>

- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\project_log\actual_progress.md`
- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\project_log\development_log.md`
- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\project_log\lessons_learned.md`

</details>

<details><summary>工具调用 1 次</summary>

- `shell` `$f="$env:TEMP\opencode\stage_fclk.py"; $t=[IO.File]::ReadAllText($f,[Text.Encoding]::UTF8); $t=$t.Replace("## 2026-10-30 — pynq_puf3 FCLK0 修`

</details>

<details><summary>工具调用 3 次</summary>

- `write` `C:\Users\HXZ\AppData\Local\Temp\opencode\stage_proto.py`
- `write` `C:\Users\HXZ\AppData\Local\Temp\opencode\commit_msg3.txt`
- `shell` `python "$env:TEMP\opencode\stage_proto.py"; git diff --cached --stat; git commit -q -F "$env:TEMP\opencode\commit_msg3.txt"; git log --oneli`

</details>

### 模型回答（2026-10-30 20:45）

问题找到了：板子发出的开机欢迎文字里有 "Y01K" 这四个字符，被 Notebook 误当成了 PUF 响应帧。这是我上一版在 Notebook 驱动里留下的问题，bit 和固件都没错。修复已推送到 `origin/main`，提交号 **`dd0dc25`**，需要队友在板上再跑一次。

**`data/pynq_puf3/notebook_20261030_123118` 里能看出的情况：**
- **时钟已经对了**：bit/hwh 哈希和候选包一致；下载后从寄存器推算 FCLK0 为 **99.999999 MHz**（PLL 倍频 30、分频 10×1）。PYNQ 显示 150 是因为它按 50 MHz 参考时钟换算，属正常现象。
- **失败发生在握手阶段，PUF 命令根本还没发出**：
  - `tx_bytes = 0`：PS 一个字节都没发出，连 PUF 请求都没有；
  - `service = null`：板子的服务帧（Y01S）没有被收到；
  - `mailbox_log.txt` 恰好停在 `...puf: Y01P/`，后面就是 "Y01K"。
- **具体过程**：固件开机欢迎文字是 `mode caps: ... puf: Y01P/Y01K`。Notebook 按四字符标记（Y01S、Y01R、Y01K）把字节流切成帧，于是把这段文字里的 "Y01K" 当成一个 112 字节的 PUF 帧，把后面的服务帧也一起吞掉了。握手时它在等服务帧，却拿到一个"PUF 帧"，所以报 `unexpected PUF frame`。
- 队友收到的 296 字节就是欢迎文字加服务帧，**并不是 "2 个 Y01K 帧"**，因为根本没发过 PUF 请求。
- 这次 KAT、基准和 PUF 都没执行，所以不能说明它们有问题。

**为什么之前没测出来：** 仿真里的测试台会先跳过文字、直到找到期望的标记；我写的模拟固件的欢迎文字是另编的，里面没有 "Y01K"。两条路径都没覆盖到真实固件的这句文字。

**修复（只改了 Notebook 里的驱动代码）：**
- 只有在确实发出了 PUF 命令、正在等它的回复时，才把 "Y01K" 当成帧。
- 而且帧头里的版本号、命令号和序号必须和发出的命令一致，否则当成普通文字跳过。这样日志里出现 "Y01K" 也不会再出错。
- bit、hwh 和固件都没动（`769ed24c` / `4a0e7b95`），**不需要重新烧写新的 bit**。重新打包只更新了 manifest 里的源文件哈希。
- 我清空了 Notebook 里上次失败运行的输出，失败证据仍然保留在 data 目录里。

**验证：** 离线脚本直接执行 Notebook 里的代码，并把模拟固件的欢迎文字改成和真实固件一字不差：
- 修复前：复现了完全相同的 `unexpected PUF frame`；
- 修复后：8/8 通过，包括：
  - 用板上这句欢迎文字回放握手，能正常通过；
  - 等待回复时夹在中间的 "Y01K" 文字会被跳过，序号不对的帧不会被接受；
  - 完整流程通过（推算 100.000 MHz、实测约 99.99 MHz）；
  - 时钟、分频不对，以及 HWKEY 没生效时，都会判失败。

**请队友：**
1. `git pull` 到 `dd0dc25`。
2. **重启 Jupyter 内核**，避免还在用旧的类定义。
3. 从头按顺序执行 Notebook，把新生成的 `data/pynq_puf3/notebook_<时间>/` 整个发回来。

固件欢迎文字里的 "Y01P/Y01K" 我没去掉，改它要重编固件和 bit，主机端已经能正确处理。三个 project_log 日志也已同步更新。

## 用户提示（2026-10-30 21:53）

我认为当前只需要测试3就可以，2的话没有办法去测试了

<details><summary>工具调用 1 次</summary>

- `shell` `git fetch origin 2>&1 | Out-Null; git log --oneline -4 origin/main; git diff --stat HEAD origin/main`

</details>

<details><summary>工具调用 1 次</summary>

- `shell` `git stash list | Select -First 2; git merge --ff-only origin/main 2>&1 | Select -Last 1; python -c " import json r=json.load(open('data/pynq`

</details>

<details><summary>工具调用 1 次</summary>

- `shell` `git merge --ff-only origin/main 2>&1 | Select -First 12`

</details>

<details><summary>工具调用 1 次</summary>

- `shell` `git stash push -m "others-wip-logs" -- project_log/actual_progress.md project_log/lessons_learned.md tasks/task_board.md 2>&1 | Select -Last`

</details>

<details><summary>工具调用 1 次</summary>

- `shell` `python -c " import json r=json.load(open('data/pynq_puf3/notebook_20261030_131920/result.json',encoding='utf-8')) print(r['status'], r.get('`

</details>

<details><summary>工具调用 1 次</summary>

- `shell` `python -c " import sys; sys.path.insert(0,'src/pynq') from golden_checker import parse_kat k=parse_kat(); c=[x for x in k if len(x['PT'])<=1`

</details>

### 模型回答（2026-10-30 21:55）

队友这次板测已经全部通过：`data/pynq_puf3/notebook_20261030_131920/result.json` 里 status 是 PASS、exit_code 是 0，我已拉取核对。

我同意你的判断：这四项里，现在能补测的只有第 3 项。不过要更正一处：完整 KAT 不是 529 个，而是 **289 个**。

## 这次结果（与正式版的数字分开）

| 项 | 结果 |
|---|---|
| 时钟 | 寄存器推算 99.999999 MHz；mcycle 实测 **99.988 MHz**（首次独立实测）；PYNQ 显示 150，属正常 |
| KAT | SW / HW / ISE 各 6 个用例全部通过，篡改的标签全部被拒绝 |
| 加速比（KAT #529，16 B，30 次中位数） | SW 加密/解密 21862 / 22562 cycles；HW 1369 / 1213（**15.97× / 18.60×**）；ISE 3895 / 4288（**5.61× / 5.26×**）；30 次结果完全一致 |
| PUF | 注册质量 127；连续 5 次重建都稳定；打开 HWKEY 后官方密文被拒绝；用 PUF 密钥加解密能还原；重建后密文不变；关掉 HWKEY 后官方 KAT 恢复 |

这组数字来自 pynq_puf3 的 bit，固件也换了，所以和正式版的 16.2× / 5.8× 不能混在一起引用。

## 四项限制怎么处理

| 项 | 能不能测 | 说明 |
|---|---|---|
| 3. 完整 KAT | **能，现在就补** | 见下文 |
| 2. RO 振荡器域时序签核 | 不能靠测试解决 | 分析脚本在两个角下都是负 slack，只能改 PUF RTL；上板测试证明不了时序，只能如实列为未签核 |
| 1. 断电重启后的稳定性 | 当前设计下测不了 | PUF v1 的注册数据（REF/MASK）存在寄存器里，断电就丢；没有把注册数据存下来再装回去的通路。断电后重建必然退回只用 DNA 的密钥，测了也只会得到"失败"。要测得先加这个功能 |
| 4. 温度、误码率、熵、跨板 | 冻结前做不了 | 需要多块板、温箱和大量采样 |

## 第 3 项：完整 KAT 是 289 个

- 官方 KAT 文件一共 1089 个用例，即明文 0–32 B × AD 0–32 B。
- 板上固件的单次容量上限是明文 ≤ 16 B、AD ≤ 16 B，符合这个范围的正好 **289 个**（17 × 17）。
- **#529 是基准测试用的那个用例的编号**（16 B 明文、无 AD），不是用例总数。
- 1089 个全量 KAT 已经在主机端验证过；板上能跑的全集就是 289 个，正式版之前做的"板级 289 组"也是这个口径。

**不需要改代码。** 让队友在 Notebook 第一个配置单元里把

```python
FULL_KAT = False
```

改成 `True`，然后重启内核、从头执行，把新生成的 `data/pynq_puf3/notebook_<时间>/` 发回来即可。

- 这次会跑 289 个用例 × 3 种模式 × 3 项检查（加密、解密、篡改标签被拒），约 2600 次请求。按每次约 5 ms 计，KAT 部分大约十几秒到半分钟。
- 基准测试和 PUF 会跟着再跑一遍，正好得到一套完整、一致的证据。
- `result.json` 会逐个记录用到的用例编号，可以确认确实是 289 个。

结果回来后，我帮你核对，并把 P05 状态里的 `full_kat_pending` 改掉；第 1、2、4 项按上表口径写成已声明的限制。

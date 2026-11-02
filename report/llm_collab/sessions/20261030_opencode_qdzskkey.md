# PUF_V2时序修正与最小闭环PUF方案

- 工具：opencode；模型：claude-opus-5-5；会话：`ses_e752c0f5fffew7M4VRqDZSkKEY`
- 开始：2026-10-30 11:21；用户提示 1 条；工具调用 30 次

## 用户提示（2026-10-30 11:21）

当前对于PUF_V2存在时序违例，我希望你通过goal，给我制定一个计划，我让另一个ai来完成时序修正，并且现有 PUF v2 的 bit 本身就有缺陷。 它的 setup.tcl 没有把 PS 的 FIXED_IO/DDR 引到顶层端口，impl_1.log 里有一串 Netlist 29-160 CRITICAL WARNING。CPU-DMA 第一版就是因为同样的问题作废的。也就是说，即便不合并，现有 puf_v2/candidate/puf.bit 也不该直接上板。我现在想去修正他，同时，我感觉当前的PUF做的太多了，感觉其实没有必要做这么多功能，你需要同时给我一个最小闭环PUF方案，让我另一个ai可以去探索和检查

### 模型回答（2026-10-30 11:21）

我先查看 PUF v2 的现状：目录、setup.tcl、时序报告和日志。

<details><summary>工具调用 2 次</summary>

- `glob` `**/puf*/**`
- `shell` `git status --short | Select-Object -First 50`

</details>

<details><summary>工具调用 3 次</summary>

- `glob` `board/vivado_zynq7000_xc7z020_puf_v2/**/*.{tcl,xdc,md,txt}`
- `glob` `src/rtl/puf_soc_v2/**`
- `read` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\data\advanced\puf_soc\validation_20261030.md`

</details>

<details><summary>工具调用 4 次</summary>

- `read` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_puf_v2\setup.tcl`
- `read` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_puf_v2\readme.md`
- `read` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_puf_v2\candidate\reports\verdict.txt`
- `grep` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\data\advanced\puf_soc\vivado_logs\impl_1.log`

</details>

<details><summary>工具调用 3 次</summary>

- `grep` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board`
- `read` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_puf_v2\sources.txt`
- `read` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_puf_v2\methodology_resolution_report.md`

</details>

<details><summary>工具调用 2 次</summary>

- `shell` `Get-ChildItem src/rtl/keys_v2, src/rtl/keys, src/rtl/pynq, board/vivado_zynq7000_xc7z020_pynq_puf, sim/pynq_puf, src/firmware/keys_v2 | Sele`
- `shell` `Select-String -Path data/advanced/puf_soc/implementation/setup_paths.rpt -Pattern "Slack|Source:|Destination:|Logic Levels|Data Path Delay|R`

</details>

### 模型回答（2026-10-30 11:22）

Now the PUF RTL scope and the older independent PUF prototype.

<details><summary>工具调用 3 次</summary>

- `read` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\rtl\keys_v2\puf_mmio_v2.v`
- `read` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\rtl\keys_v2\readme.md`
- `read` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_puf\readme.md`

</details>

<details><summary>工具调用 1 次</summary>

- `shell` `Get-ChildItem -Recurse board/vivado_zynq7000_xc7z020_pynq_puf, build/local/pynq_puf -ErrorAction SilentlyContinue -Depth 1 | Select-Object F`

</details>

<details><summary>工具调用 1 次</summary>

- `shell` `Get-Content build/local/pynq_puf/build.log -Tail 25; Get-ChildItem build/local/pynq_puf/vivado/reports | Select-Object Name; Get-Content bui`

</details>

<details><summary>工具调用 3 次</summary>

- `grep` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\rtl\puf_soc_v2\soc_top_puf_v2.v`
- `read` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\rtl\puf_soc_v2\bus_interconnect_puf_v2.v`
- `read` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq_dma_cpu\setup.tcl`

</details>

<details><summary>工具调用 2 次</summary>

- `read` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq\build.tcl`
- `read` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\project_log\actual_progress.md`

</details>

<details><summary>工具调用 2 次</summary>

- `grep` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\board\vivado_zynq7000_xc7z020_pynq`
- `grep` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\project_log\lessons_learned.md`

</details>

<details><summary>工具调用 2 次</summary>

- `grep` `def ascon_encrypt|import ascon|pyascon`
- `grep` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\src\rtl\keys_v2\ro_puf_core_v2.v`

</details>

### 模型回答（2026-10-30 11:23）

Material is sufficient. Writing the plan document.

<details><summary>工具调用 1 次</summary>

- `write` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\tasks\puf_fix_and_min_goal_20261030.md`

</details>

### 模型回答（2026-10-30 11:25）

Per the AGENTS.md rules, I'm adding a progress entry.

<details><summary>工具调用 1 次</summary>

- `edit` `C:\wenjian\game\FPGA2026\ours\amd_fpga_2026\project_log\actual_progress.md`

</details>

### 模型回答（2026-10-30 11:25）

I've written the plan for the other AI to execute: **`tasks/puf_fix_and_min_goal_20261030.md`**. Nothing was modified, built or simulated in this session; I only added a planning entry to `project_log/actual_progress.md`.

## What I confirmed in the repo

- **FIXED_IO/DDR defect is real.** `setup.tcl` line 26 explicitly skips exporting the PS ports, and `impl_1.log` has a long run of `Netlist 29-160` warnings starting at line 37. This is the same problem that killed CPU-DMA v1. That fix (`pynq_dma_cpu/setup.tcl:58-59`) can be reused as-is.
- **The timing violation is real and not properly fixed.** The first route failed at −0.249 ns. The failing path runs from the CPU dcache address through a 24-bit address decode, then the PUF register's "is this write allowed" check, into the write enable of the 128-bit input registers: 10 logic levels in one cycle. The candidate only reached +0.009 ns through a post-route optimization pass, and that netlist still has the FIXED_IO problem. So `candidate/puf.bit` must not go on the board.
- **There is no ready fallback.** The old PUF v1 overlay build (`pynq_puf`) never finished; its log stops during placement at an estimated −1.18 ns.
- **Possible issue on the main line (not changed).** `vivado_zynq7000_xc7z020_pynq/build.tcl` also doesn't export FIXED_IO/DDR. I couldn't find its implementation log in the repo, so the plan has the other AI check it read-only and report back to you. It must not modify or rebuild the release.

## Track A: fix PUF v2

1. **Invalidate the old candidate first.** Add an invalid marker, mark it do-not-program in the candidate index, and make `capture.py` refuse the old bit's SHA-256.
2. **Export FIXED_IO/DDR in `setup.tcl`**, build in a new project directory, and add a hard check: zero `29-160` warnings and DDR/FIXED_IO ports present.
3. **Fix timing.** First rerun routing once to see where it stands after the port fix. Then choose one:
   - **Recommended:** actually lower the PS clock to 80 MHz, as CPU-DMA did.
   - **Or, to keep 100 MHz:** add one register stage on the PUF write path (only in files under `src/rtl/puf_soc_v2/`). This needs a one-cycle stall when a read immediately follows a write.
4. **Pass bar:** at least +0.1 ns slack without the post-route optimization pass, plus all existing simulations passing again. It stays labelled structural/diagnostic only, because the ring-oscillator (RO) logic still has no defined clock.

## Track B: minimal closed-loop PUF

The current design builds everything into the FPGA: the RISC-V CPU, firmware memory, AEAD and image authentication in hardware, the diagnostic helper interface, and the mailbox. That's about 39k LUTs, and the timing failure sits exactly on the CPU-to-PUF path. Only the physical response actually has to live in the FPGA. The minimal design:

- **FPGA side:** the ARM processor connects directly to a small new register block. It reuses the existing 256-ring sampler from `keys_v2`, plus the device DNA reader. There's no CPU, no hardware AEAD, and a single 100 MHz clock.
- **Python side:** sample several times to build a reference and a mask of stable bits, then derive a key from the stable bits plus DNA. Encrypt a fixed message with that key using the repo's `pyascon`. After reloading the bitstream or a power cycle, rebuild the key and decrypt. **If the tag verifies, the loop is closed**, and a ciphertext with one flipped bit must be rejected.
- **Before building, the other AI must answer 7 questions (E1–E7).** The most important is whether the existing sampler still works when both of its clocks are the same clock.
- **Pass bar:** at least +0.5 ns slack, zero `29-160` warnings, all RO logic inside its placement region, and leftover unclocked RO endpoints counted and listed. Board testing stays not-run until done by hand.

## Order of work

Do the 15-minute invalidation first, then explore and build Tracks A and B in parallel. If time runs short before the 11-01 freeze, put the minimal PUF first as the PUF demo, and leave v2 marked as "invalidated / fix in progress".

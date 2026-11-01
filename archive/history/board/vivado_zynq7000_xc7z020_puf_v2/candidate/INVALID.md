# 本目录 candidate 已作废：禁止上板、禁止合并

状态：**INVALID_DO_NOT_PROGRAM**
作废日期：2026-10-30
任务号：PUF-V2-FIX / A0（见 `tasks/puf_fix_and_min_goal_20261030.md`）
owner：TBD

本目录所有文件**原样保留**，仅新增本说明；`puf.bit` / `puf.hwh` / `manifest.json` /
`reports/` 未删、未改、未重打包。`manifest.json` 仍记录当初打包时的哈希与
`STRUCTURAL_DIAGNOSTIC_ONLY` 结论，它与本文件不矛盾：结构可追溯到原始构建，
但该 bitstream 不可用于任何板级或交付用途。

## 作废原因

### 1. F2：源配置未导出 PS 的 `FIXED_IO` / `DDR` 接口

`board/vivado_zynq7000_xc7z020_puf_v2/setup.tcl` 第 26 行注释明确跳过了
`make_bd_intf_pins_external`，因此生成的 `puf_ps7_0.xdc` 把 IOSTANDARD /
PACKAGE_PIN / slew / PIO_DIRECTION 施加到内部 pin 上。

实测（本次复核，不是估计）：

| 日志 | `CRITICAL WARNING: [Netlist 29-160]` 条数 |
|---|---|
| `data/advanced/puf_soc/vivado_logs/impl_1.log`（首条在第 37 行） | **301** |
| `data/advanced/puf_soc/vivado_logs/synth_1.log` | 0 |

301 = 4 类 property（iostandard / PACKAGE_PIN / slew / PIO_DIRECTION）× PS 侧约 75 个
DDR+MIO 引脚。这是**约束没有落到真实顶层端口**的直接证据，不是日志噪声。

### 2. F5：时序余量几乎为零，且该网表带着缺陷 1

`reports/verdict.txt`：post-route `phys_opt_design -directive AggressiveExplore`
之后 setup slack = **+0.009 ns**、hold = +0.019 ns。首次 `route_design` 的真实结果是
WNS −0.249 ns / TNS −1.615 ns（`data/advanced/puf_soc/implementation/setup_paths.rpt`），
违例路径为 `u_dcache/bus_addr_r_reg[23]` → `u_puf/peripheral/input_data_reg[*]/CE`
（10 级逻辑、82% 布线延迟、100MHz）。

即：该 bitstream 的“通过”依赖 post-route 物理优化，余量小于 1 个 LUT 延迟，
固定/温度/电压漂移下不可靠；同时它是在缺陷 1 的网表上得到的。

### 3. F8：RO 域未签核（本次不修）

7424 个无时钟 seq pin、19712 个未约束端点，TIMING-6/7 存在。即使缺陷 1、2 修好，
本设计的结论仍然是 `STRUCTURAL_DIAGNOSTIC_ONLY`。

## 禁止事项

1. **禁止**把本目录 `puf.bit` + `puf.hwh` 装载到 PYNQ / 板卡。加载会失败或产生未定义行为，
   且违反“约束未落到真实端口”的构建卫生门禁。
2. **禁止**把本目录内容合并进 `board/vivado_zynq7000_xc7z020_pynq/release/` 或任何 release。
3. **禁止**手工修改 `reports/` 或 `manifest.json` 让门禁“看起来通过”。
4. **禁止**引用 `validation_20261030.md` 的仿真 PASS 作为本 bitstream 的板测证据——板测
   状态自始至今是 `not_measured` / `NOT_RUN`。

## 程序化防护

`board/vivado_zynq7000_xc7z020_puf_v2/capture.py` 增加了硬拒绝：当待加载 bitstream 的
SHA-256 等于本目录 `puf.bit` 的值时

```
05c955cdc8ca5d7c019eed1194e4f2403ef1d415e582750fa04c7a1b5cf3dc62
```

脚本在任何 MMIO 访问之前抛错并 `exit 1`，`--out/result.json` 记录 `status=FAIL`。
没有旁路开关。主机侧单元测试见 `sim/puf_soc_v2/test_capture.py::test_invalidated_bit`。

索引同步：`data/advanced/current_candidates.json` 中 `puf_soc_v2` 条目已改为
`INVALID_DO_NOT_PROGRAM` 并指向本文件。

## 后续

修复方向（下一轮，已确认）：A1 先修源配置（导出 `ps7/FIXED_IO`、`ps7/DDR`，重建到
`work_fix/`，门禁 29-160 = 0 且 DDR*/FIXED_IO* 端口存在）；A2 在 A1 的新网表上**先做
A2-explore**（一次不跑 phys_opt 的 route），再按用户已选定的 **A2-b**（保持 100MHz，
在 `src/rtl/puf_soc_v2/` 内给 PUF 写通路打一拍，并处理写后读冒险与 bus_error 语义对齐）
修改。在此之前，本设计的展示入口改用 `PUF-MIN` 最小闭环。

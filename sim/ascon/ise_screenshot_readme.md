# PUF3 工程中的 ISE 截图配置

任务 D03/I04；owner TBD；Vivado/XSim 2025.2；2026-10-31。

## 已配置工程

`build/local/pynq_puf3/vivado/pynq_puf3.xpr`

- 设计顶层仍为 `pynq_puf3_wrapper`，part `xc7z020clg400-1`。
- 新增并激活仿真集 `sim_ise_screenshot`，top=`tb_key_ise`。
- 使用原 `sim/ascon/tb_key_ise.v` 和三个 ISE/置换 RTL 文件；未改 DUT 或 TB。
- 测试向量 `data/ascon/permutation.mem` 在仿真运行前自动复制到仿真工作目录的对应相对路径。
- 运行时限 50 us，原 TB 在 37390 ns 正常 `$finish`，1502 checks / 0 errors。
- 自动记录 15 个重点信号、WDB/VCD，并打开 `ise_screenshot_view.wcfg`；以原始自检判定 PASS。

## 现在截图

Vivado 原生 GUI 已打开，并保留已完成的 simulation。选择 `ise_screenshot_view` 或
`ise_screenshot_focus` 波形页；若时间轴只显示末尾很小一段，用波形工具栏缩放，推荐 **300–1800 ns**。
保留信号名、时间轴和底部 PASS 文本；可双击 Wave 页签扩大窗口。

首两次请求的 VCD 读回时间：

| 事件 | 时间 ns |
|---|---:|
| P8 start 拉高 | 380 |
| P8 done 拉高 | 495 |
| P8 ack 拉高 | 760 |
| P12 start 拉高 | 1190 |
| P12 done 拉高 | 1345 |
| P12 ack 拉高 | 1610 |
| cancel 拉高 | 36760 |

`mode_p12` 是已锁存模式；TB 在运行中故意翻转 `perm_p12` 并写入干扰数据，验证结果不受影响。
`perm_done` 保持到 ack 展示完成后的下游停顿行为；此单元 TB 没有名为 hold 的输入。
取消场景可另截 **36650–37100 ns**。实际 EX hold 的整合测试是 `tb_key_execute.v`，不混作本截图。

资源图仍从同一工程的 **Open Implemented Design → Reports → Report Utilization** 查看，
应为 LUT 18674、FF 32002、BRAM 34.5、DSP 4。

## 关闭后再打开

打开上述 XPR，选择 **Run Simulation → Run Behavioral Simulation**。
活动仿真集已保存，会自动执行全部自检并添加波形。

若在重新构建的 PUF3 工程中恢复该配置，在 Vivado Tcl Console 执行：

```tcl
source C:/wenjian/game/FPGA2026/ours/amd_fpga_2026/sim/ascon/configure_ise_screenshot.tcl
launch_simulation -simset sim_ise_screenshot -mode behavioral
```

绝对路径按仓库位置修改；脚本其余路径由自身位置推导。

## 证据

- 波形：`build/local/pynq_puf3/ise_screenshot/ise_screenshot.{wdb,wcfg,vcd}`。
- 视图源：`sim/ascon/ise_screenshot_view.wcfg`；WDB 保存真实数据，WCFG 只配置显示。
- 日志和哈希：`data/ascon/results/ise_screenshot_20261031/`。
- 复核：`python -X utf8 sim/ascon/check_ise_screenshot.py`。
- 修改前 XPR 备份：`build/local/pynq_puf3/ise_screenshot_backup/20261031_224938/`。

已完成 synth/impl 未重跑，candidate bit/hwh/manifest 哈希保持；本次只是 ISE 行为级单元测试。
启动时 BD 的 protoinst 可视化提示不存在 `pynq_puf3` 实例，因为本次 top 是 `tb_key_ise`；
不影响单元 RTL 的编译、自检或所记录信号。未将其隐藏或降级。

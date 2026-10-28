# PYNQ 2026-10-28 最终验证

Y01/Y02/Y03/Y04/V01/V04，owner TBD。分支feat/pynq-final-integration，从远端0f5d49c开始；源码提交见release manifest（生成后填写）。实物型号/速度级待核实，目标xc7z020clg400-1。

| 验证 | 实际结果 | 原始证据 |
|---|---|---|
| test_host_api.py | PASS / exit0，17项含历史Notebook顺序执行 | build/reports/pynq_final_20261028/host_final.log |
| test_mailbox.py | PASS / exit0，24项 | mailbox_final.log |
| test_navigator.py | PASS / exit0，8项 | regression_final/navigator_adapter.log（完整摘要summary.json） |
| test_pynq_transport.py | PASS / exit0，14项，包含real service flag回归 | transport_final.log |
| golden_checker.py | PASS / exit0，1089官方KAT、4290拒绝，host模拟范围 | tests.json / regression_final |
| make_pynq_profile.py --selftest | PASS / exit0，合成HWH，非硬件 | tests.json |
| bash sim/pynq/elab_check.sh | PASS / exit0，IP stub仅elaboration | tests.json |
| bash src/firmware/pynq_svc/build.sh | PASS / exit0，RV32IM_Zicsr/ilp32，24条custom-0，P12/P8存在 | tests.json / 固件构建日志 |
| python sim/pynq/run_bridge.py | PASS / exit0，真实桥RTL：双向、空读、WSTRB、RX满/溢出/顺序读回、复位中止发送 | bridge_0.log / bridge_1.log |
| python sim/pynq/run_service.py | PASS / exit0，真实CPU+最终服务固件+AXI-Lite/UART+行为AXI存储；直接官方corpus的empty/1B/16B/16B+AD，共三模式36请求（加/解/坏tag），检查mcycle非零；半帧复位后重新握手 | service.json / service_1.log |
| python -B sim/board/run_tests.py --mode smoke | PASS / exit0 | smoke/summary.json |
| python -B sim/board/run_tests.py --mode regression --pynq-p0 | PASS / exit0；CPU SW/HW/ISE、镜像一致性、Host/mailbox KAT、DCache和定向中断 | regression_final/summary.json |
| Vivado BRAM MIF与最终BIN逐字节比较 | PASS，128KiB含补零 | bram_image.json |
| 生产Python语法按3.8 AST解析 | PASS；不是目标PYNQ运行验证 | 开发日志命令 |
| PYNQ系统/网络/Jupyter/Overlay/PS7实际MMIO | NOT_RUN | 今晚执行handoff手册 |
| FPGA真实周期与速度比 | NOT_MEASURED | 不填模拟数字 |

运行环境：Windows PowerShell、CPython3.14.3（以日志实际version探测为准）、WSL Ubuntu、GCC13.2.0、native Icarus/vvp12.0、Vivado2025.2 SW6299465/IP6300035。全部命令从仓库根运行。WSL elaboration使用 `IVERILOG=/mnt/d/iverilog/iverilog/bin/iverilog.exe`，队友可配置为自己的路径或PATH。

## Vivado

**PASS / exit0，已真实生成 bitstream**（2026-10-28 15:03）。最终恢复命令：

```powershell
& E:/2025.2/Vivado/bin/vivado.bat -mode batch -notrace -source board/vivado_zynq7000_xc7z020_pynq/rebuild_firmware.tcl -log build/local/pynq_final/vivado_resume.log -journal build/local/pynq_final/vivado_resume.jou
```

首次建工程使用build.tcl；rebuild_firmware.tcl只对本轮已生成的独立工程重新生成BRAM、复位相关run并继续构建。正式文件为release/pynq.bit（4,045,688B）及pynq.hwh（148,833B）。bit/hwh由同一pynq BD导出，BRAM单独重新生成后MIF与最终BIN完全一致。

100MHz：WNS **+0.034ns**、TNS **0**，WHS **+0.020ns**、THS **0**，setup/hold失败端点均 **0/62861**；内部未约束端点0，无no_clock/no_input_delay/no_output_delay项。资源见utilization.rpt。
DRC **0 Error / 0 Critical Warning**；默认report列出53项Warning，其中两项是CHECK-3规则条数上限提示，REQP-1839/1840各显示20项（并非所有warning只有53项）。还包括DSP流水、RAM输出寄存器、无可布线负载；原始DRC完整保存，不将warning抹成0。methodology有LUT异步复位提示。时序余量很小，不能当作跨板温度/电压稳定性保证；今晚仍须实板KAT与连续请求验证。

最终八条必跑命令已重跑，全部exit0，见final_tests.json和final_00..07.log；tests.json保留首轮历史结果。


Tcl导入现有两项XCI到独立工作目录；只改本工程的COE配置并移除旧COE依赖，未改原始baseline/PL-only XCI。PS7 GP0、100MHz FCLK、proc_sys_reset（生成结果C_EXT_RESET_HIGH=0）、两独立AXI-Lite窗口已验证BD。ascon_word.v含i++，在新工程仅将此辅助源标为SystemVerilog；BD三个module reference顶层仍Verilog。

## 保留的失败/限制

初始当前main回归缺少新PUF模块、首轮P0 wrapper误传参数均FAIL，保留regression/和regression_p0/；修调用点后regression_final整套PASS。首轮Vivado缺include header、辅助RTL解析、旧COE依赖错误保留后续原始日志。修复前固件误读UART接收位在service_before_fix.log显示epoch20B后卡svc_getc；停止自己的旧仿真后重跑，不把中止写成PASS。

P0源集声明是本轮scope，不代表PUF main全系统回归。原PL-only三版历史bit不在本机仓库工作区，不能伪称本次已重新上板。16B容量内官方289组已提供板端命令，本轮真实CPU联合仿真是4代表组×三模式，不宣称289/1089目标全量PASS。服务固件半帧读取依赖host超时后reset；无本地接收超时；单客户端串行，无跨进程锁。UART无远端流控，实际吞吐与PS访问延迟待测。HW polling超时目前可能表现为内部失败/解密认证失败，异常时整链reset后重测，不作为认证性能数据。

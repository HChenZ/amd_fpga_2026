# PUF3 专用协同仿真入口

更新：2026-11-01；owner TBD。`run.py` 对应当前 PUF3 固件与 board 下两个变体，不是旧 run_cpu_regression 的别名。

- normal：真实 RV32 固件、AXI-Lite/UART/mailbox + PUF 命令，既有结果 54 步 PASS。
- mutant_autolock：有意换回旧自动锁钥 soc_top/key_mmio，相同固件应不能通过 HW 自检；这是必要负向用例，不能改成 PUF3 以“统一源文件”。
- RO/DNA/BUFG 在仿真中是模型，不能据此宣称物理 PUF 稳定性或时序签核。

程序依赖 `build/local/pynq_svc_puf/` 的固件产物，输出 `build/local/pynq_puf3/sim/`。
先确认使用的固件与源码版本；重跑可能更新本机输出，不自动更新已发布 candidate 或既有板测。
`sim/ascon/run_cpu_regression.py` 默认源集缺 keys/BUFG；--pynq-p0 只选择旧无 PUF 版本，不是本入口。

当前已归档结果见 `board/vivado_zynq7000_xc7z020_pynq_puf3/candidate/reports/cosim_summary.json`；
本次文档收口没有重跑仿真、改 golden 或改程序默认值。

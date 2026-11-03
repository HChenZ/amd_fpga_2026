# PUF v1 模型与历史单元验证

更新：2026-11-01。本目录是 PUF v1 的模型/单元与早期 keys 自检支持，不是当前 PUF3 板测入口。
DNA_PORT_sim.v、BUFG_sim.v、LUT_sim.v 被 PUF3 协同仿真复用；不能因为目录旧而删除这些依赖。
PUF3 normal/mutant 流程用 sim/pynq_puf3/run.py；物理板测用 src/pynq_puf3 的 Notebook。
模型验证不证明真实RO频率、跨上电/PVT/BER或安全性；本页不改变测试、默认参数或历史结果。

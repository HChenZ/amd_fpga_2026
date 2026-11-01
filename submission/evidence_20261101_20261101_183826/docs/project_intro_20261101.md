# 当前项目简介（提交候选）

更新：2026-11-01，与最终报告 `docs/tech_report/amd_fpga_2026_latex_final/amd_fpga_2026_report/output/pdf/final_report.pdf`
及板测 `data/pynq_puf3/notebook_20261031_114512/result.json` 一致。

本作品面向嵌入式数据安全场景，基于 AMD Zynq-7000（XC7Z020）平台，实现集成轻量级密码加速的
RISC-V 处理器 SoC。处理器采用五级流水线，支持 RV32IM、Zicsr，集成分支预测、指令与数据 Cache、
AXI 互连及 UART、GPIO、CLINT 等外设，配置工作频率为 100 MHz。围绕 NIST SP 800-232 Final
Ascon-AEAD128，提供纯软件、MMIO 硬件加速与定制指令三种方案，并完成分层仿真、官方向量验证与实板演示。

主演示为 PUF3 overlay：同一 bitstream 集成 SW/MMIO/ISE 三模式与 256 路 RO-PUF、Device DNA
硬件密钥通路，PS 经 AXI-Lite 窗口与 PL 中 UART mailbox 通信，提供 Python API 与 Jupyter 交互，
明文与关联数据各不超过 16 字节。2026-10-31 实板测试中，三模式各通过 289 组容量内官方 KAT 并拒绝
289 个错误 Tag。固定 16 字节、AD 为空、HWKEY 关闭、预热 5 次后 30 次采样，加密中位周期为软件 21862、
MMIO 1369、ISE 3895，对软件周期加速比分别为 15.969 倍、5.613 倍；解密为 22562/1213/4288 周期，
加速比 18.600 倍、5.262 倍；PS 调用墙钟单独记录，不计入加速比。实现资源 LUT 18674、FF 32002、
BRAM 34.5、DSP 4；已约束路径 WNS +0.104 ns、TNS 0、WHS +0.041 ns，DRC 0 Error/0 Critical Warning，
普通警告保留。

PUF 密钥通路在同一会话内完成注册（质量 127/128）、连续 5 次重建稳定、HWKEY 下拒绝调用者密钥及关闭后
官方 KAT 恢复。RO 计数器域时序尚未签核，跨上电、温度/电压、误码率、熵与唯一性尚未测量，原始响应
在调试接口上可读，因此不将其表述为已验证的可靠保密密钥或完整安全启动。
项目于 11 月 1 日提交并冻结，后续按需完善稳定性、工程通用性和扩展验证。

## 历史指标的使用方式

- PYNQ v1 release（固件 `pynq-svc-v1`，无 PUF）10-31 重测的 23342/1439/3995 cycles、16.221×/5.843×、
  WNS +0.034 ns，以及其 9/9 错误恢复门禁，只作历史对照，不作为当前主性能或 PUF3 的通过项。
- 20806 / 688 / 2570 cycles（软件/MMIO/ISE）与 30.24×/8.10× 为 10-26/27 的**历史 PL-only 基准**，
  可保留在历史对照表，但不能与当前主性能表混用。
- 早期独立 RO-PUF 原型 keys3 日志中的 127/128 来自 v2 失败片段，v3 为 128/128；均不同于 PUF3 的
  注册质量 127/128（10-31 PUF3 实板），引用时须注明来源。

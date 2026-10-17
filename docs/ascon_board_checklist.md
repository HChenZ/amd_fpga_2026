# XC7Z020 借板与上板清单

2026-10-16；B03/B02/V01/I08/Y01；owner TBD。当前板卡型号未知，未生成本轮 bitstream、未烧录。

1. 拍照/记录品牌、型号、PCB revision、芯片完整丝印/封装/速度等级、供电与启动跳线；
   取得对应版本原理图、官方 XDC、手册。XC7Z020 本身不能确定板型，更不能推出 PYNQ-Z2。
2. 核查时钟源频率、电平、时钟脚；复位极性；UART 电压/引脚；LED/button；JTAG 连接。
   对照恢复工程 const.xdc，逐项确认后在独立板型配置修改。未核实前不烧录。
3. 确定是 PL BRAM 裸机路径，还是需要 PS/DDR/AXI。当前 top_pl_bram 无已验 PS/PYNQ 控制链。
   需要 PYNQ 时另核 image/board support，不复用未知板平台镜像。
4. 固定待测 commit、Vivado 2025.2、IP 版本、part/top/约束及综合/实现策略；读取当前
   WNS/TNS/WHS、未约束路径、LUT/FF/BRAM/DSP、DRC。时序或 DRC 阻塞须先关闭。
   特别核查 PS7 缺失的默认配置要求、BRAM 异步控制和 ZEROIZE 派生复位的毛刺/恢复移除风险；
   内部 STA 通过不能替代这些检查，也不能覆盖未知板卡的 UART/button/LED IO 约束。
5. 将通过仿真的 Ascon 裸机 ELF/BIN 转换为独立公开测试 COE，确认复位向量0x10000000、
   128 KiB BRAM布局、栈/数据容量、cache 行为与硬件 UART 时钟分频；原始 FreeRTOS COE 保留。
   从源配置重新生成 IP/bitstream，记录 firmware/bitstream hash；禁止用真实秘密初始化。
6. 先执行基础串口、复位、mcycle 和内存/Cache/AXI 检查，再跑软件/MMIO/ISE 官方 KAT、
   至少三组不同 Key/Nonce、错误 Key/Tag/密文拒绝、连续请求、ZEROIZE/复位清理。
   从黄金参考逐字节核对，不能只做加密后再解密。
7. 测量同输入/频率/工具链/Cache/中断策略下的 cycles 和端到端时间。将板上实测与现有
   仿真结果分列；注明软件擦除与 MMIO ZEROIZE 是否包含在测量范围。
8. 真正接入上位机前冻结请求协议、容量/长度验证、独占与超时恢复、缓存一致性、
   Key/Nonce 来源及生命周期；验证失败不发布明文，日志只记录公开测试数据。

未完成项：实物身份、pinout、电气/供电、固件加载链、完整 baseline ISA/外设/异常回归、
ISE 抢占上下文策略、PS/PL transport、板上 KAT/benchmark。不要将借到板直接等同于可演示。

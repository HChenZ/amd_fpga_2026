## 6 性能量化与分析

本章以当前 PYNQ release 的同次板测为主表；历史 PL-only 固件仅作独立对照。
不将不同编译器、固件调用边界、输入长度矩阵或实现源集的结果拼接计算加速比。

### 6.1 当前 PYNQ 固定输入 warm benchmark

输入为锁定官方 KAT #529，PT=16 B、AD=0；每模式预热 5 次，再各采集 30 次加密和 30 次解密。
全部结果与官方 CT、Tag、PT 比对，service simulated=false、selftest_mask=7。
周期测量范围为固件 svc_aead_encrypt/decrypt 调用边界，不含 PS 与 UART。

| 模式 | 加密中位 cycles | 加密 cycles/B | 加密周期加速比 | 解密中位 cycles | 解密 cycles/B | 解密周期加速比 |
|---|---:|---:|---:|---:|---:|---:|
| SW | 23342 | 1458.875 | 1.000× | 24005 | 1500.312 | 1.000× |
| HW/MMIO | 1439 | 89.938 | 16.221× | 1388 | 86.750 | 17.295× |
| ISE | 3995 | 249.688 | 5.843× | 4385 | 274.062 | 5.474× |

六档 raw_cycles 各 30 个，且每档数值完全一致，故 min/median/P95/max 相同。
这是固定输入 warm 路径的重复采样结果，不是覆盖全部长度的平均性能，也不是小时级稳定性证据。
证据：`data/pynq/notebook_20261029_130920/pynq_warm_benchmark.json`。

### 6.2 PS 调用墙钟与 CPU 周期的区别

同一批采样的 PS 调用墙钟如下，由 raw_wall_ns 复算中位数：

| 模式 | 加密中位 ms | 解密中位 ms |
|---|---:|---:|
| SW | 5.216 | 4.957 |
| HW/MMIO | 4.479 | 4.262 |
| ISE | 5.154 | 4.986 |

PS 墙钟包括 Python、MMIO 访问、UART 字节传输和轮询等待。CPU 周期下降并未等比例转化为
PS 响应时间下降；不得将 16.221× 或 5.843× 标成 Python API 的响应时间加速比。
两条测量边界分别保留，不以串口理论传输时间代替实测。

### 6.3 历史 PL-only 基准的独立对照

历史三套基准固件在同一板卡、配置 100 MHz、16 B 加密 warm 条件下经串口输出 mcycle：

| 模式 | 历史板上 cycles | 对应 RTL 仿真 cycles | 历史周期加速比 |
|---|---:|---:|---:|
| SW | 20806 | 17353 | 1.00× |
| ISE | 2570 | 2496 | 8.10× |
| MMIO 调用 | 688 | 670 | 30.24× |
| MMIO 核本体观测 | 103 | 99 | 不与完整 AEAD 调用并列计算加速比 |

历史日志为 `data/ascon/results/board/uart_20261026_sw_and_ise.txt` 与 `uart_20261027_mmio.txt`。
688 与 103 的差额为 585 周期，占调用周期约 85.0%；这仅说明该历史测量中核外开销占比，
不直接套用到当前服务固件。板上与仿真差异的完整定量归因未完成，不外推为一般平台规律。
当前主表始终使用 §6.1 的 PYNQ 同次运行结果。

### 6.4 资源与时序的统计范围

当前 PYNQ overlay 的资源、WNS、DRC 取自独立 pynq_wrapper 实现报告（§8.4）。
历史 PL-only 的 12426 LUT、16156 FF、34.5 BRAM tile、4 DSP 为整个 SoC 的实现资源，
包含 CPU、Cache、总线、存储与加速逻辑，不是单独密码运算逻辑的面积。
SW/ISE/HW 历史镜像共用同一硬件结构，固件 COE 不同，不能据此推导各方案的边际资源消耗。
复用同一个 Verilog 模块定义也不意味着不同实例在运行时共享一块电路。

本文只陈述已有整机实现结果及同平台周期对照，不提供未测的功耗、Fmax 或各加速通路独立面积。

### 6.5 对比结论的适用边界

当前结论限于相同 RV32/PYNQ 平台、相同输入与操作、相同固件调用边界的三模式对照。
host 的完整标准验证、历史 PL-only 周期和当前 PYNQ 结果分别成立，不互相替代。
超出 16 B 的板级运行不属于当前服务能力，既不计为通过，也不列为本次交付必须完成的新功能。
不据整机资源或短消息延迟宣称优于其他器件、其他工具或其他论文实现。

<span class="evid">证据 data/pynq/notebook_20261029_130920/pynq_warm_benchmark.json；board/vivado_zynq7000_xc7z020_pynq/validation_20261029.md；data/ascon/results/board/uart_20261026_sw_and_ise.txt；data/ascon/results/board/uart_20261027_mmio.txt</span>

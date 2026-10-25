# 厂家资料提取事实

2026-10-25，owner TBD，证据类型 vendor_static_inspection。根目录为用户提供的 `E:\正点原子领航者(V2)ZYNQ开发板资料盘(A盘)`。未运行厂家脚本、未解包整个 ZIP、未复制厂家工程进仓库。来源文件/成员 SHA256 见 `vendor_sources.json`，可由 `inspect_vendor.py` 复核。

## 系统和示例

PYNQ 开发指南 V3.2 §2.2（印刷/PDF p19）指向 `4_SourceCode/5_PYNQ_Design/IMG/ZYNQ-7020-2.7.0.zip`，解压 `.img` 后写 SD；§2.3（p22–23）要求 P5 选 PS 串口、SD CARD 启动、PS Ethernet，115200 8N1 无流控。指南描述 Ubuntu 20.04 / kernel 5.4.0。本机目录实际拼写 `4_Source_Code`；其中 `5_PYNQ_Design` 只有 7010/7020 示例 ZIP。递归文件名检查未找到 `.img` 或 `2.7.0`，7020 ZIP 中也没有镜像。因此：**厂家文档声称提供可启动镜像，但当前所供盘中镜像缺失，实际启动 BLOCKED**。不把示例 `.bit` 当启动镜像。

7020 示例 ZIP 为680,414,199 bytes，17,381 entries；本轮只读以下成员：

- `base/base.srcs/sources_1/bd/base/base.bd`：完整 Base 的 PS7 配置；BD tool_version=2020.2，device=xc7z020clg400-2。
- `2_axi_gpio/vivado/axi_gpio/axi_gpio.srcs/sources_1/bd/system/system.bd`：精简 Overlay；50 MHz FCLK0，关闭 UART/SD/Ethernet MIO。不能据此重建 Linux 启动平台。
- `2_axi_gpio/vivado/axi_gpio/axi_gpio.xpr`：Vivado v2020.2，part `xc7z020clg400-2`，含原作者 F: 路径元数据。
- `3_mmio/notebook/mmio.ipynb`：`Overlay('./ready_to_test/axi_gpio.bit')`；从 `overlay.ip_dict[IP]['phys_addr']` 取得地址后创建 `MMIO`，演示 GPIO 数据/三态控制。示例 GPIO 偏移与地址不能充当本项目 Ascon Mailbox。

指南 §5.3–5.4（p60–68）与 §6.3（p74起）：从现有 Vitis Hello World/AXI GPIO 工程派生，配置 PS7/EMIO 或 AXI GPIO，验证 BD、添加适用 XDC、生成 bitstream，导出硬件；复制同名 `.bit` 与 BD `hw_handoff/*.hwh` 到 `ready_to_test`。Python Overlay 默认下载并解析 HWH。本轮仅阅读，代码没有调用 Overlay 下载。

## Base BD 中的 PS7（不是本轮实物测量）

| 项目 | BD 静态值 |
|---|---|
| PS7 IP | processing_system7（完整 VLNV 见 JSON） |
| PS 晶振 | PCW_CRYSTAL_PERIPHERAL_FREQMHZ=33.333333 |
| DDR | DDR3，32 Bit，MT41J256M16 RE-125，配置533.333333 MHz，计算533.333374 MHz |
| DDR 地址 | PCW_DDR_RAM_BASEADDR=0x00100000；HIGHADDR=0x3fffffff；不等于可随意分配的 Linux 内存 |
| UART | UART0 enable=1，MIO14..15，115200；UART1 enable=0 |
| SD | SD0 enable=1，MIO40..45，CD=MIO10 |
| Ethernet | ENET0 enable=1，MIO16..27，MDIO52..53，计算125 MHz，1000 Mbps |
| FCLK0 | 计算100 MHz，驱动 GP0、AXI 外设、rst_ps7_0_fclk0 |
| FCLK1 | 请求150 MHz，计算142.857132 MHz，驱动视频/HP0/另一复位域 |
| FCLK2/3 | 计算11.904762 / 200 MHz；不是本项目 CPU 必须使用的时钟 |
| 复位 | FCLK_RESET0_N 接两个 proc_sys_reset/ext_reset_in；输出 interconnect/peripheral_aresetn 分别复位总线/外设 |

核心板 2V5 原理图是7010/7020共用图，DDR 页还标 NT5CC256M16；不能仅从 BD 的 JEDEC 型号断言实物 DDR 型号或时序完全适用。实物芯片、容量和 bootloader PS7 初始化都要复核。底板 V3.9 p6 与核心板 2V5 p3 已渲染并目视核验 P5、50 MHz/U18；其余引脚由 XDC 与底板连接器表交叉检查。

## Vivado / Python 兼容性边界

本机 `E:\2025.2\Vivado\bin\vivado.bat -version` 输出 Vivado 2025.2 / SW Build6299465 / IP Build6300035；本次进程退出1并有 XILINX_HLS 默认位置警告。只记录版本，不将该退出码算作工程构建结果。未打开旧 XPR，未升级 IP，未综合/实现。

2020.2→2025.2 的 XPR/BD/IP 迁移、厂家自定义 IP/HLS、绝对路径、`.bit/.hwh` 匹配与 PYNQ 2.7 的 HWH 解析兼容性均 **NOT_RUN**，不能保证旧工程直接重建。后续应保留厂家原件，在经授权的独立工程中审查升级报告、重建同一设计的 bit/hwh 并在目标 image 运行 KAT。不得将厂家 `-2` 覆盖本项目 `-1`。

本次 Host/Transport 验证用 Python3.14.3，WSL host validation 为3.12.3；既有 API 使用 `int | None` 等现代类型语法/运行时，已有文档验收基于3.11。厂家 image 的实际 Python/PYNQ 运行时未读取，不能承诺直接兼容；拿到 image 后先执行 `python3 --version`、读取 `pynq.__version__`，再决定受支持的运行环境，不能擅自升级整套板上系统。本轮没安装软件或修改系统配置。

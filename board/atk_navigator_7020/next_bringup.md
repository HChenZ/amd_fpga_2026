# 领航者7020下一步最短上板路线

2026-10-25；B02/B03/B04/Y01/Y02，owner TBD。本文是下一阶段计划；本轮未打开/修改原始baseline、未运行Vivado构建或下载板卡。

## 当前可开始什么

**建议开始独立PL-only工程的配置与离线重建准备**：三套COE已生成且对应BIN在真实RV32仿真执行通过，板级8个端口已从厂家XDC核验，本轮Cache事务与timer中断子集通过。正式板卡下载前仍需确认实物完整part/版本、生成适用工程、STA/DRC与启动链。

**PYNQ端到端工程尚不具备验收条件**：启动镜像缺失、PS7实物DDR/启动配置待核、PS可达Mailbox/服务固件与cache策略未冻结；默认Backend继续NOT_CONFIGURED。PL自测和JTAG/UART可以先进行，不依赖PS Linux/PYNQ镜像。

## 独立工程需要的Tcl/XDC/IP工作

1. 单独脚本/输出目录，基于真实恢复baseline的资源与工程配置派生；记录Vivado2025.2、part `xc7z020clg400-1`、top `top_pl_bram`、IP版本和全部输入SHA。不在原XPR目录generate、upgrade或写runs；不创建空工程假装替代原baseline验收。
2. 明确生产源manifest：使用当前 `src/rtl` 及 `src/rtl/ascon`，剔除`*_tb.v`，检查模块重复；**原baseline imports是历史快照，不等于当前CPU/MMIO/ISE**。不能原样加载旧imports却宣称使用了当前Ascon。源依赖应固定到本次通过的哈希，在未来独立工程中审核来源选择。
3. 只派生必要3个IP输入：clk_wiz6.0（原50→100MHz）、axi_bram_ctrl4.1、blk_mem_gen8.4（32×32768、byte enables）。新工程的blk_mem_gen指向本轮SW COE，重新生成独立IP产物；以后分别建立MMIO/ISE配置。原freertos_demo.coe/XCI完全保留。先验证工具/IP版本和接口，再综合/实现。
4. 新constrs只加入本目录最小navigator_uart.xdc所列端口；确认顶层不改名、不重复加原const.xdc或厂家全模板。外50MHz/U18、N16 reset、H15/L15 LED、T19/J15 USB UART来自厂家资料；实物版本再核。异步按键/UART/复位只在核对同步器后约束实际边界，不以整片false_path遮蔽同步路径。重新检查未约束端点、时钟、IO、电压、DRC和timing。
5. 保持既有100MHz配置做第一轮离线重建；当前已记录的+0.087ns是芯片级历史余量，不能冒充新板工程签核。若团队决定80MHz/50MHz，必须作为独立配置重新生成时钟IP并同时核对UART参数、计时频率和STA，不能把估算时序当实测。
6. 当前生产top.v默认UART_CLK_FREQ=100MHz并传给soc_top，115200的分频计数为868；top_pl_bram提供100MHz时与之匹配。旧直接soc_top仿真是50MHz/434，不能把那个时钟参数套到新硬件。频率更改须沿实例链核对，实板需验证实际baud。

以上可以通过独立Tcl/IP配置/XDC、选择现有生产源和新固件完成，**不需要改共享CPU/SoC生产RTL**。新增板级smoke固件（GPIO心跳、UART身份/mcycle/BRAM自检）也是独立软件工作。PS复位/动态装载、Mailbox地址映射、Cache不缓存窗口、AXI多主机/CDC和PUF密钥路由均需要接口评审，不能在本轮偷偷接入。

## 速度等级待确认的影响

离线脚本、COE与Python/协议准备可按现有-1继续；引脚映射还取决于实际CLG400/PCB版本，签核的速度文件、允许时钟/PLL配置、setup/hold和Fmax结论必须对应实物。拿到芯片完整丝印或正式BOM/订单后确认-1/-2，不因厂家示例是-2而自动改part，也不只凭JTAG识别到XC7Z020猜速度等级。未确认前不作该板时序通过或可稳定运行声明。

## 首次拿板后的顺序

1. 记录板卡/核心板/底板版本、芯片丝印、供电和跳帽照片；确认厂家资料适用、UART为3.3V、JTAG和USB口。
2. Hardware Manager只连接读取器件身份，核对目标与工程。确认独立工程的报告/DRC和bitstream来源后再安排SRAM下载；首次不要写QSPI/固化启动镜像。
3. 用独立最小固件或最小板级wrapper验证LED/复位/时钟与UART hello。PL串口选P5 3–5、4–6，按实物pin1确认；115200/8N1采集原始文件。PS控制台另用P5 1–3、2–4，不能混为同一个程序输出。
4. 验证复位后从0x10000000启动、BRAM读写、mcycle递增和可重复复位；串口报告固件构建ID/RTL与bitstream SHA（缺字段就记缺失），解析时选择hardware_uart_capture，不回填模拟数据。
5. 先加载SW COE跑当前代表KAT/篡改，再分别重建/加载MMIO、ISE COE，逐项比对官方expected；记录每套镜像/bitstream/频率和原始UART日志。16B MMIO限制保留，不宣称板上完整1089 KAT已通过。
6. KAT通过后再采同条件mcycle与加速比，之后接PS/PYNQ。软件时序、AXI/Cache可见性、PLL/板级IO签核、复位和真实传输未测均是正式板上验收前的阻塞。

当前准备不等于已授权下载：本轮没有连接或配置实板。正式Ascon上板前最短阻塞为实物确认、独立工程重建/STA/DRC、COE到实际BRAM初始化核对、板级自检和UART可追溯身份。

## PYNQ镜像缺失的可行处理

- 最短路线：通过厂家资料更新入口/技术支持取得适配该7020核心板与底板版本的 `ZYNQ-7020-2.7.0` 镜像，核对来源/哈希后再安排SD烧写。本轮未找到可验证下载，不虚构链接，不用PYNQ-Z2镜像代替。
- 备选路线：取得能正常启动的领航者PS7 XSA/BSP（DDR/MIO/SD/Ethernet），按锁定PYNQ版本的官方sdbuild进行板级构建。PYNQ2.7的官方版本表对应Vivado/Vitis/PetaLinux2020.2，不能直接把本项目2025.2当兼容环境。自建是独立工作项，不在本轮安装大软件或构建系统镜像。[PYNQ2.7官方构建文档](https://pynq.readthedocs.io/en/v2.7.0/pynq_sd_card.html)、[v2.7.0 sdbuild说明](https://github.com/Xilinx/PYNQ/blob/v2.7.0/sdbuild/README.md)（2026-10-25核读）。
- 并行路线：先完成PL/JTAG/UART自测；这能验证P0算法/固件，但不把串口路径标为PYNQ/PS端到端通过。取得镜像后先核对板上Python/PYNQ版本；既有Host API依赖现代Python运行时，不能未测即承诺厂家image原生兼容。

## 给PUF队友预留的接口（仅设计，不实现）

保留协议版本/能力协商、key_source/key_handle的版本化扩展位置、密钥slot所有权、有效/错误/zeroize/重置完成握手、busy期间换key行为以及异常/取消时的生命周期。当前v1的16B公开测试key仍按原契约传递，不复用保留位偷偷传handle，不输出PUF内部密钥/重建中间量。PS复位RV32或Mailbox恢复不能擅自推定PUF已清零/已重建，需要队友给出独立完成/错误语义；板级时钟/复位域也需共同评审。所有owner TBD，未碰PUF、key_mmio、Skill或共享SoC。

# 领航者 7020 上板准备（B03 / Y01，owner TBD）

> 2026-11-01 阅读提示：本目录为资料/板前验证交接，不是 overlay。下面镜像缺失/未上板等状态是当时记录；
> 后续旧 PYNQ v1、PUF3 均已实板。完整丝印/速度等级与真实 IO 延迟等仍未闭合。
> 当前入口见 docs/version_entrypoints.md，本文不回写原数据或改变操作程序。

2026-10-25；只读厂家证据、独立配置与接口准备。未修改两个 baseline、CPU/Cache/Ascon/PUF RTL 或 `skill/`，未生成正式 bitstream，未下载板卡。

| 项目 | 本轮结论 | 状态 |
|---|---|---|
| 板型 | 用户指定正点原子领航者 ZYNQ 7020，CF7010B/7020B / ATK-DF7010/7020P 系列 | 已知型号，实物版本待核 |
| 器件 | 当前项目继续 `xc7z020clg400-1`；厂家 AXI GPIO/Base 示例是 `-2` | 实物速度等级 BLOCKED，不自动换 part |
| 时钟 | 核心板 2V5 原理图 PDF p3：X1 50 MHz，经 R7 到 U18/PL_GCLK | PASS 静态；频率实测 NOT_MEASURED |
| 工程 | 原 baseline `top_pl_bram`；BRAM 32×32768 / 128 KiB；50→100 MHz PLL | 本轮仅核对，不打开/升级工程 |
| PYNQ | 指南 V3.2 §2.2/§2.3 描述 PYNQ 2.7.0、Ubuntu 20.04、kernel 5.4.0 | PASS 文档提取；实板 NOT_RUN |
| 镜像 | 文档列 `ZYNQ-7020-2.7.0.zip` / `.img`，说明出厂镜像不支持 PYNQ | 当前资料树与 7020 ZIP 未找到，BLOCKED |

源码入口：[统一测试](../../sim/board/readme.md)、[接口建议](interface_plan.md)、[厂家证据](vendor_findings.md)、[待配置后端](backend_profile.json)、[最小 XDC](navigator_uart.xdc)。本目录不是第三套 Vivado 工程。

## 最小引脚与串口

以下从厂家 `NAVIGATOR_ZYNQ_IO.xdc` 核验，映射到现有 `src/rtl/top_pl_bram.v` 端口。所有列出引脚为 LVCMOS33。

| 厂家端口/网络 | 项目端口 | 管脚 | 说明 |
|---|---|---|---|
| sys_clk / PL_GCLK | clk | U18 | 20 ns 输入；不把 PS 晶振 33.333333 MHz 当 PL 外时钟 |
| sys_rst_n / PL_RESET | reset_btn | N16 | 低有效；现有 wrapper 默认 RESET_ACTIVE_LOW=1 |
| key[0] | button[0] | L14 | 底板 PL 按键 |
| key[1] | button[1] | K16 | 底板 PL 按键 |
| led[0] | led[0] | H15 | 底板 LED0 |
| led[1] | led[1] | L15 | 底板 LED1 |
| USB UART uart_rxd / UART3_RX | uart_rxd | T19 | FPGA RX ← CH340 TX |
| USB UART uart_txd / UART3_TX | uart_txd | J15 | FPGA TX → CH340 RX |

核心板标量 LED 的 J16 没有映射给现有 2-bit `led`。厂家通用 XDC 对 `uart_rxd/uart_txd` 同时包含 USB、RS232/RS485（K14/M15）、ATK MODULE 重复约束；本目录仅选 T19/J15，各端口各一个 PACKAGE_PIN，不能把通用模板全量加入工程。`inspect_vendor.py` 自动核对所选8个端口的来源、唯一端口/唯一管脚；未做 Vivado DRC 或 IO 时序签核。

底板 V3.9 PDF p6 的 P5：1=UART1_TXD、2=UART1_RXD、3=CH340C_RXD、4=CH340C_TXD、5=UART3_TX、6=UART3_RX。**PS 控制台：短接1–3、2–4；PL RISC-V：短接3–5、4–6**。使用前按实物 pin1 丝印确认，不能同时桥接两端。板上网络叫 UART1，不代表 PS7 必须配置 UART1；Base BD 实际使用 PS7 UART0 MIO14–15。PS Linux 启动日志与 PL 固件串口需分别采集。指南 PS 控制台 115200/8N1/无流控；PL 固件 UART 取决于实际 CPU 时钟及现有 uart 配置，必须另核波特率。

## 将来独立工程清单

经团队确认后才集成：Vivado 2025.2、part `xc7z020clg400-1`、真实 baseline 资源清单及 3 个 IP（clk_wiz_0、axi_bram_ctrl_0、blk_mem_gen_0），现有 top 与生产 RTL 精确 SHA；按新工程 top 选择约束端口。本轮 XDC 仅适用现有 `top_pl_bram` 端口。

新增 PS7、GP0 AXI 互连、复位控制、共享内存/控制块及物理 Mailbox driver 均属后续方案，不代表已经存在。PS7 DDR/MIO 需对照实物和已启动系统确认；PS 与 CPU AXI 时钟/复位必须一致或有 CDC。替换 COE 只在未来独立工程中指定本轮构建产物，**原 freertos_demo.coe 保留**。交付 bit/hwh/firmware 哈希、Vivado/IP 版本、地址表、时序/DRC 报告后才能配置真实 Backend。

复现只读提取（输出目录必须不存在）：

```powershell
python -B board/atk_navigator_7020/inspect_vendor.py --vendor-root 'E:\正点原子领航者(V2)ZYNQ开发板资料盘(A盘)' --out build/local/vendor_new
```

不复制大工程；只读取4个 ZIP 成员、4份外部文件与文件名清单。完整报告/提取文本留在 `build/local/preboard_vendor_02/`；精选事实与文件 SHA 在 [vendor_sources.json](vendor_sources.json)。下一接收 B03（实物/image）、Y01（物理协议审查）、Y02（独立 Overlay），owner TBD。

# DMA / PUF 离线实现状态（2026-10-30）

> 2026-11-01 范围：本页是独立实验的10-30证据索引，非当前 PUF3。CPU-DMA的全1089目标仿真只属该版本。
> **PUF v2 SoC旧候选已作废**（candidate/INVALID.md），下文结构/时序/交付检查PASS保留历史，不可据此上板。
> “原主线 release”指旧 PYNQ v1；当前 PUF3 的PS外部接口和门禁不能由旧版推断覆盖。见 version_entrypoints.md。

owner TBD。独立实验目录，不覆盖原PYNQ release，不修改已提交简介。
这是代码/仿真/实现的证据索引；所有新版本 board_validation 仍为 NOT_RUN。

## HW_DIRECT 已取得的证据

- 新模块 `src/rtl/ascon_dma/`：Final标准多块AEAD，PT/AD各0–1024B，mode4。
- ABI v2、AXI-Lite控制、32-bit AXIS、背压、TKEEP/TLAST、epoch/ID、有限接收deadline。
- 认证前/失败不发布明文；失败/clear/reset有界擦除；同步结果读的有效标志与数据同拍。
- 输入LOAD即撤销前次结果；生命周期201检查、128位坏Tag、14状态reset/clear及tag绕过故障注入通过。
- 当前完整Icarus协议/KAT回归3467项PASS（含fault后拒收直到recover）：`data/advanced/dma_direct/20261030_022713/`。
- 当前生命周期与故障注入：`data/advanced/dma_direct/lifecycle_20261030_014019_800532/`。
- 最终实际AXI DMA IP+AXI内存BFM的XSim3465包PASS：`vendor_final_20261030_0302/`；
  另外两类不能由正常DMA产生的坏流由直接AXIS TB验证。最终XSim3467协议、201生命周期、18控制检查
  见 `xsim_final_20261030_0219/`（最终故障锁定日志axis_fault_lock.log）。

**最终RAM版实现已通过（100MHz配置，Vivado2025.2，xc7z020clg400-1）：**

| 指标 | 原始结果 |
|---|---:|
| WNS / TNS | +0.345ns / 0 |
| WHS / THS | +0.031ns / 0 |
| setup/hold失败端点 | 0/18268 |
| no_clock / 未约束内部端点 | 0 / 0 |
| DRC Error / Critical Warning | 0 / 0 |
| 整个direct overlay资源 | LUT5611 / FF6425 / BRAM4.5 tile / DSP0 |

证据与候选：`data/advanced/dma_direct/vivado_20261030_024214/`。
candidate下bit/hwh配对，manifest含源快照/哈希；不是已上板结果，也不是旧RV32整机资源。
`final_verified_20261030.json` 校验当前源码、候选哈希、原始回归与实现门禁一致；
`hwh_driver_contract_20261030.json` 核对真实HWH与PYNQ2.7驱动参数/地址。
前一版 `vivado_20261030_015458/` 的+0.242/+0.029及5703/6430是独立旧快照，不混入最终值。
核与协议模块OOC资源3136LUT/2870FF/2.5BRAM，原首版15693LUT/19483FF/0BRAM，
均属各自综合快照，不能直接当成板上功耗或吞吐。

## CPU-DMA 已取得的证据

- `src/rtl/pynq_dma_cpu/`：独立CPU端点与总线/SoC变体；不替换生产CPU。
- `src/firmware/pynq_dma_svc/`：真实RV32固件，SW/ISE≤32B、HW≤16B，能力分模式广告。
- `src/pynq/dma_transport.py`：PYNQ2.7后端，先收后发、缓存同步、deadline、单客户端锁、未静止buffer保留。
- `board/vivado_zynq7000_xc7z020_pynq_dma_cpu/bringup.py`：永久smoke/full/benchmark入口，支持mode4。
- 真实CPU的SW1089、ISE1089、HW289官方向量，各做加密/解密/坏tag，共7401事务PASS；
  协议拒绝与取消/恢复另外记录。证据 `data/advanced/dma_cpu/full_20261030_002958_293520/verified_full.json`。
- 最终32主机测试、10 CLI测试及端点/AXI-Lite/reset检查PASS。
- 实际XSim全量7418/7418包PASS（含7401密码事务+17协议负向），另有95/95实际AXI DMA IP、
  真实CPU及vendor BRAM联合用例PASS；DDR为有界AXI BFM，不是PS/DDR芯片仿真。
- 100MHz固定PS端口版本WNS-0.046，有限优化无改善，失败证据保留；另建**实际80MHz FCLK**候选，
  readback80MHz、STA12.5ns，WNS+0.601/WHS+0.024、critical/error DRC0，5条LUTAR-1保留。
- 最终候选 `data/advanced/dma_cpu/vivado_20261030_040257/candidate/`，
  资源17179LUT/21936FF/36.5BRAM/4DSP；汇总 `data/advanced/dma_cpu/handoff_summary.json`。
  父会话重验7418与95两个XSim摘要及4候选文件、42个RTL/固件输入hash，均PASS。
- 行为仿真时钟100MHz、实现候选80MHz是不同层级记录；不把仿真墙钟当80MHz板测。
  原正式PYNQ与HW_DIRECT仍100MHz，不因该独立CPU-DMA候选而修改旧简介/结果。

## PUF v2 已实现的离线内容

- `src/rtl/keys_v2/`：明确采样错误/事务新鲜度、核心域deadline、旧key撤销、禁止DNA-only正常回退，
  RO健康与计数握手、key内部驱动AEAD、normal/diagnostic MMIO分离、真实DNA读取集成。
- `src/firmware/keys_v2/`：真实RV32自检，normal/diagnostic执行通过。
- helper版本/设备/构建/参数绑定及诊断持久化；不是保密secure sketch。
- 1–16B IMAGE_VERIFY演示，版本/长度/目的地址作为认证AD；不是CPU可信执行启动链。
- 独立Icarus故障矩阵和5个XSim顶层通过；物理综合网表保留256×5=1280 RO LUT。
- 完成跨域捕获修复后CDC-1消失；对popcount与MMIO读选择作两项有据修改后，
  定义路径WNS+0.054/TNS0、core内部setup+1.648/hold+0.098，全部5个XSim顶层和真实CPU回归再次通过。
  条件OOC的IO-inclusive hold仍-0.502，RO频率未测，不能称全域签核。
  最终源快照、报告、DCP：`data/advanced/puf/physical_quality_decode_20261030_023728/`；
  说明 `src/rtl/keys_v2/synchronous_timing_20261030.md`。独立实际SoC接线/候选见下一节。

## PUF v2 实际 SoC / 诊断候选已完成

- 新 `src/rtl/puf_soc_v2/` 将真实PUF MMIO精确解码到0x30010000，注册读回符合CPU接口；
  128KiB私有BRAM含真实RV32自检固件，PS控制与UART mailbox收集ASCII，**不是Y01服务**。
- 两种Icarus真实SoC模式、四种XSim配置（含真实vendor BRAM/COE）、6项CLI测试PASS。
- 已完成综合、布线、实际物理优化及bit生成：100MHz核心WNS+0.009/WHS+0.019，
  25MHz管理域WNS+5.117/WHS+0.119，定义路径TNS/THS0，69141/69141可布线net完成。
- 资源39077 LUT/40051 FF/34.5 BRAM tile/4 DSP；normal ABI不导出内部key/raw。
- **候选只作STRUCTURAL_DIAGNOSTIC_ONLY**：仍有7424 no_clock、19712未约束内部端点，
  RO频率、跨域与复位脉宽尚未完成物理签核；正WNS只适用于已定义时钟路径。
- 配套候选：`board/vivado_zynq7000_xc7z020_puf_v2/candidate/`；
  验证记录：`data/advanced/puf_soc/validation_20261030.md`；
  父会话实际执行 `verify_delivery.py` exit0，10项source/bit/HWH/firmware/test边界检查全true。
- normal ABI与“物理诊断候选”的两个概念分开；没有生成helper可导出的diagnostic ABI物理bit。
  上板运行、DNA位序、熵/可靠性/唯一性及安全启动均未验收。

## 仍依赖物理测量/外部信任条件

实际PS DDR/HP口、Linux cache和DMA、板上KAT/吞吐、PUF频率/熵/BER/温压/唯一性/可靠性未测。
纠错/提取器安全强度不能由行为RO模型定案；完整保密helper与可信启动/回滚链未完成，
不能把诊断REF持久化或小镜像认证演示包装为这些能力。

上板顺序与回退：`advanced_board_handoff.md`；接口：`advanced_dma_contract.md`。

## 待确认：主线 release 的 `Netlist 29-160` 计数（只读检查，未做任何修改）

任务 `tasks/puf_fix_and_min_goal_20261030.md` §3 要求统计主线 release 对应 impl 日志中的
`CRITICAL WARNING: [Netlist 29-160]`。执行方只做只读核查，**没有改 release、没有重建 release**。

### 结论：`mainline_29_160 = not_retained`（无法计数，不是 0）

没有找到主线 overlay 的 `impl_1` / `synth_1` 运行日志，因此**不能给出数字**。把这件事写成
`0` 或“已确认无问题”都是错的。

### 核查范围（全部为只读）

| 检查 | 结果 |
|---|---|
| `board/vivado_zynq7000_xc7z020_pynq/release/` 内容 | 只有 `manifest.json` / `pynq.bit` / `pynq.hwh` / `pynq_svc.{bin,coe,elf}` / `sha256sums.txt`，**无 impl 日志** |
| `board/vivado_zynq7000_xc7z020_pynq/build.tcl` 指定的工程目录 `build/local/pynq_final/vivado` | **不存在**（构建工作区已被清理） |
| 全仓库 `*.log` 扫描 | 165 个 >100KB 日志中，仅 `build/reports/pynq_final_20261028/verify.log` 提到 `pynq_overlay`，且它是校验日志不是运行日志 |
| `submission/evidence_20261101_20261029_2333*/` | 只快照了 `build/reports/pynq_final_20261028/{timing,drc,utilization}.rpt`，无 `runme.log` |
| `build/reports/pynq_final_20261028/drc.rpt` 中 `29-160` | 0 条 —— 但这条**不能作为证据**，见下 |
| `data/advanced/puf_soc/optimized/drc.rpt`（puf_v2）中 `29-160` | 0 条 —— 同一原因 |

### 为什么不看 DRC 报告

`Netlist 29-160` 是 `set_property` 施加失败时打给**运行日志**的告警，`report_drc` 不会收集它。
用 puf_v2 这个已知带缺陷的工程做过对照：`impl_1.log` 有 **301** 条，而它的 `optimized/drc.rpt`
是 **0** 条。所以“DRC 0 Error / 0 Critical Warning”不能推出“没有 29-160”。

### 结构性判断（推断，非实测）

`board/vivado_zynq7000_xc7z020_pynq/build.tcl` 与 puf_v2 的 `setup.tcl` 一样，没有对
`ps7/FIXED_IO` 和 `ps7/DDR` 调用 `make_bd_intf_pins_external`，因此生成的 PS 引脚 XDC 同样会
落到内部 pin 上。**按同一构建结构推断，主线 release 也应存在同类告警**，但这是推断，
不是计数结果。主线已有板测 PASS 证据（`validation_20261028.md` / `validation_20261029.md`），
29-160 属于构建卫生问题而非功能失败，因此**是否处理由用户决定**。

### 若要拿到数字，需要什么

在不改 release、不重建 release 的前提下，需要一份当初构建 `pynq_overlay` 的运行日志。若该
工作区已被清理，则只能由用户在需要时单独重建一次同配置工程来计数——**本轮不做**。

### 交给用户的决定

1. 接受 `not_retained`，主线保持现状（推荐：主线功能证据已齐，且冻结在 2026-11-01）。
2. 后续单独安排一次主线只读复核（新建 work 目录、不改 release），把 29-160 计数补进本文件。

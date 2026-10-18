# Ascon 100 MHz 时序续接审查

> V10 留存更新：本文是历史审查记录；V06 旧 RPT 曾被删除，随后并行会话恢复，
> 用户确认暂时保留。最终双策略报告及清理后数据一致性结论见 [清理与复验](workspace_cleanup.md)。

实现日期2026-10-16；2026-10-17复核；V06 / B02 / I08；owner TBD。承接 `fix/ascon-key-lifecycle` 的安全修复，
保留 `build/reports/ascon_key_lifecycle/` 的优化前报告。用户授权最多两轮有依据的优化和实现，
不修改正式频率、时钟约束或时序例外。板型未知，未生成或烧录 bitstream。

## 优化前证据与第一轮修改

Vivado 2025.2 build 6299465，xc7z020clg400-1，top_pl_bram；50 MHz 外部输入，经
clk_wiz 产生100 MHz内部时钟。原始 XCI/XDC/COE 原样保留，IP 为 axi_bram_ctrl 4.1、
blk_mem_gen 8.4、clk_wiz 6.0。默认综合和实现策略，报告为 fully routed。

最差 setup 路径位于 `u_soc_axi_top/u_soc_top/u_ascon_mmio/u_ascon_core/u_crypto_aead`：
`ad_rem_reg[3]/C → s1_reg[58]/D`，源/目的均为 `clk_out1_clk_wiz_0`，周期10 ns。
WNS=-1.641 ns；数据路径11.561 ns，其中逻辑6.263 ns（54.173%）、布线5.298 ns（45.827%）。
11级逻辑为7个CARRY4、2个LUT5、2个LUT6。源码尾块掩码的可变移位后64-bit减一
产生长进位链，源扇出52又增加布线延迟。这些数据支持先消除掩码算术路径；
没有据此把原因泛称为全局拥塞或跨时钟问题。

第一轮仅修改 `crypto_aead.v` 的尾块组合逻辑：16个固定字节通道按有效长度选择输入、
0x01 padding或0；替换 AD 和明文尾块的宽移位/减一。没有新增状态、寄存器或周期，
没有变更 START/BUSY/DONE、长度范围、密钥锁存、认证门禁和 ZEROIZE。

`run_tail_equivalence.py` 用原 main `c37ecae` 核心做逐周期对比，覆盖AD/消息0..16字节
全部289种长度组合，每种加密、正确解密、错误Tag解密，合计867请求/43098周期。
输出（包括未用输出位）和握手逐周期完全一致。该差分只证明行为与延迟未改变；
密码学正确性另由锁定 Final C/Python 黄金参考、289个官方接口内KAT及认证负向回归证明。

## 可复现命令与报告

在仓库根目录执行；使用新工作名和报告名，避免覆盖旧构建：

```text
python sim/ascon/run_tail_equivalence.py
python sim/ascon/run_key_rtl.py --label timing_r1
python sim/ascon/run_rtl_regression.py --report data/ascon/results/key_lifecycle/rtl_timing_r1.json
python sim/ascon/run_cpu_regression.py --mode hw --label timing_r1
python sim/ascon/run_cpu_regression.py --mode hw --security --label timing_r1
vivado -mode batch -source build/build_ascon_review.tcl -notrace -log build/local/key_audit/vivado_timing_r1.log -journal build/local/key_audit/vivado_timing_r1.jou -tclargs ascon_timing_r1 fresh ascon_timing_r1
```

当前续接结果索引为 `data/ascon/results/key_lifecycle/final_validation_summary.json`；
旧 `validation_summary.json` 对应优化前源码。两者不混用。各CPU报告包含实际编译命令、
GCC/Icarus版本、ELF与输入源哈希。实现快照和最终源码逐文件核对，原始报告另有SHA-256。
`.log.gz` 是无损日志压缩，生成IP、DCP、固件镜像与缓存不纳入Git。
源哈希首先记录实际测试的工作区字节（Windows RTL为CRLF）；汇总另含仅规范化到LF的哈希，
供不同系统检出时核对文本内容。原始Vivado报告及build_context按字节保存，不受Git换行转换。

## 实现结果

| 阶段 | WNS ns | TNS ns | LUT | FF | BRAM tiles | DSP |
|---|---:|---:|---:|---:|---:|---:|
| 优化前 fully routed | -1.641 | -607.794 | 11683 | 15960 | 38.5 | 4 |
| 第一轮 fully routed | -0.942 | -433.585 | 11562 | 15949 | 38.5 | 4 |
| 第二轮 post-route physical optimization | -0.177 | -2.968 | 11636 | 15949 | 38.5 | 4 |

第一轮综合/实现命令exit0，但setup仍有1579个失败端点；WHS=0.019 ns、THS=0，
WPWS=3.750 ns、TPWS=0。最差路径转为 `id_ex_u/csr_addr_o_reg[4]/C` 到
`u_dcache/data_way1_reg_1/DIADI[3]`；9级逻辑，数据10.654 ns中布线8.586 ns（80.589%）。
前20条路径还包括 PC 经取指/保持控制到ISE state CE及EX/MEM CE。报告没有支持继续扩大
Ascon算法流水的依据；剩余瓶颈已进入CPU控制、CSR旁路与cache区域。

第二轮复用第一轮 synth_1，在同一隔离工程内新建 `key_review_r2`，采用
`Performance_ExplorePostRoutePhysOpt`，目标是通过布局、扇出优化和布线后物理优化缩短
路由主导路径。RTL、IP、XDC、时钟和时序例外完全不变，因此第一轮最终功能测试仍对应
同一源码；这不是第二次RTL修改，也不是降低频率。入口：

```text
vivado -mode batch -source build/refine_ascon_timing.tcl -notrace -log build/local/key_audit/vivado_timing_r2_resume.log -journal build/local/key_audit/vivado_timing_r2_resume.jou -tclargs resume
```

首次调用因 `launch_runs` 阶段名不匹配而exit1，尚未启动实现；保留日志。2025.2接受的是
`{phys_opt_design (Post-Route)}`，不是属性名 `post_route_phys_opt_design`。
修正后 `resume` 只允许继续状态为Not started的已建run，不会重复/覆盖完成的第二轮。
全新复现使用同一脚本、不带 `-tclargs resume`。第二轮批处理exit0，最后一个routed checkpoint
写出后正常退出；23917个可布线net全部布线，routing errors=0。WHS=0.015 ns、THS=0，
WPWS=3.750 ns、TPWS=0，但仍有31个setup失败端点：**100 MHz timing not met**。

最终最差路径为CPU `id_ex_u/rs1_o_reg[1]/C → u_dcache/bus_wmask_r_reg[0]/CE`，
同一100 MHz时钟域；数据延迟9.753 ns，逻辑2.885 ns、布线6.868 ns（70.420%），
10级逻辑（4个CARRY4、LUT3/5/6及RAMD64E）。前20条路径主要到dcache的bus_addr_r、
bus_wmask_r等CE。下一步应针对地址计算、cache miss/hold/使能扇出开展独立CPU时序任务，
评估局部寄存或解码简化及其stall/旁路影响；当前不继续第三轮优化或Strategy Sweep。
正式100 MHz目标不变，降低主频须另行决策，不能把本结果作为成功上板版本。

最终DRC为已报告95 Warning、0 Critical Warning、0 Error；部分REQP规则达到20条报告上限。
主要类别为BRAM异步控制/输出寄存、DSP输入/输出寄存、PS7缺失；Methodology另有23 Warning，
包括LUT驱动异步复位。未约束内部端点、组合环和多时钟寄存均为0；button/uart的3个输入
及led/uart的3个输出缺少IO delay，reset_btn保留既有false path。IO及复位物理风险尚未关闭。

2026-10-17逐字节复核RTL快照及全部测试输入无差异。XDC、COE、AXI BRAM和clock wizard XCI
与baseline完全一致；Vivado在独立副本的blk_mem_gen XCI移除了一个enabled=false元数据并
重算checksum，功能参数值不变，原baseline未改。精确双侧hash见final_build_inputs.json。
所有旧报告保留，没有以中间阶段估计替代最终summary。

## 上板门禁

即使内部约束时序通过，也须单独处理缺失的板级IO delay、板型/pinout核验、复位与BRAM
告警、正确Ascon固件初始化和实板回归。原COE仍为FreeRTOS。不得把芯片级结果标为上板通过。
下一接收 B02/B03/V01/I08/Y01；见 [板卡核验清单](ascon_board_checklist.md)。

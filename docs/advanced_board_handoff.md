# DMA / PUF 新版上板交接门禁

> 2026-11-01 范围：本页的“新版”指独立 CPU-DMA/HW_DIRECT/PUF v2 实验，不是当前 PUF3。
> PUF v2 旧 candidate 已 INVALID、禁止上板；其早期正 slack/校验结果不构成下载许可。
> 当前主演示入口见 version_entrypoints.md；实验程序和已归档结果不改。

本文件用于离线工作完成后的现场执行，所有 board 结果初始为 NOT_RUN。
原PYNQ正式release与新实验候选必须区分；先记录hash，再烧录。已提交简介保持不动。

## 1. 文件与运行身份

- 正式回退：`board/vivado_zynq7000_xc7z020_pynq/release/`。
- CPU-DMA：`board/vivado_zynq7000_xc7z020_pynq_dma_cpu/`；能力SW/ISE32B、HW16B。
- CPU-DMA合格候选是**80MHz**，位置 `data/advanced/dma_cpu/vivado_20261030_040257/candidate/`；
  不烧录旧100MHz失败实验，不把80MHz的墙钟指标与原100MHz基线混算。
- HW_DIRECT：`board/vivado_zynq7000_xc7z020_dma_direct/`；mode4，PT/AD各1024B，不是ISE。
- PUF v2：`src/rtl/keys_v2/`、`src/firmware/keys_v2/`；正常与诊断构建独立标识。
- PUF实际SoC候选：`board/vivado_zynq7000_xc7z020_puf_v2/candidate/`，仅结构诊断用途，
  normal ABI无helper/key导出；另有helper-disclosing ABI的离线测试，不混称该物理bit。
- 新bit/HWH只使用同一个通过实现门禁的候选目录；源码或仿真PASS不能代替bit候选。

统一工件索引：`data/advanced/current_candidates.json`。HW_DIRECT quickstart有完整文件哈希与CLI命令；
CPU-DMA CLI还必须提供配套dma_svc.bin。PUF候选只允许结构诊断，不是全域签核release。

## 2. DMA现场顺序

| 顺序 | 操作 | 判据与失败处理 |
|---|---|---|
| 1 | 保留原镜像，记录板型、系统、PYNQ/Python、候选hash | 候选与HWH/固件必须匹配 |
| 2 | 确认PS HP0、DDR、PL时钟实际设置 | 不能仅凭BD参数认为运行PS已经配置好 |
| 3 | 运行独立loopback（若有已验候选） | 从小包到跨4KiB，逐字节/canary一致；失败不接密码核 |
| 4 | 读取控制ID/version/capabilities，recover新epoch | ID=0x32414d44/version2，模式位与长度正确 |
| 5 | 永久bringup CLI smoke | 真实simulated=false，三模式或mode4分别执行，不fallback |
| 6 | full KAT与坏tag | SW/ISE各1089，HW289，HW_DIRECT1089；认证失败无明文 |
| 7 | 超时/复位/重复请求/缓存复用 | 恢复后合法KAT；DMA未静止则保留buffer，不能强制释放 |
| 8 | benchmark | 同次固定输入、预分配与否说明、CPU mcycle或PL cycles与PS墙钟分列 |

CLI入口：`board/vivado_zynq7000_xc7z020_pynq_dma_cpu/bringup.py --help`。
该工具支持mode4；HWH中实例名与实际板端路径作为参数，不能照搬别人机器的地址。
硬件访问失败时不要用host模拟结果填board字段。先记录错误寄存器与身份，再恢复原镜像。

## 3. PUF现场顺序

实际入口 `board/vivado_zynq7000_xc7z020_puf_v2/readme.md` 与 `capture.py --help`。
该SoC固件输出ASCII自检日志，不使用DMA/旧Y01客户端。PS控制ID0x32554650，版本2；
使用配套manifest验证bit/HWH/固件后，按该目录capture示例执行。该候选仍未全域时序签核。

1. 先normal模式读取ABI/status，确认真实DNA读取完成；与Hardware Manager比对位序，未核对前不称设备绑定通过。
2. 诊断模式收计数差、无振荡/相等/溢出与错误码；严格健康策略可能拒绝单个平局，不能删掉检查让质量全满。
3. enroll→内部key加密→reconstruct→相同公开测试输入加密，比较CT/tag；此处仅测试一致性，重复nonce不用于实际消息安全。
4. 错helper/停止采样/超时须拒绝并清旧ready；恢复后重新进行合法流程。
5. 仅在诊断helper持久化演示中保存全REF/MASK；重启后LOAD_HELPER→RECONSTRUCT，禁止每次自动enroll后声称跨上电重建。
6. IMAGE_VERIFY目前仅1–16B功能演示；caller的expected_version不是可信根，不能称完整安全启动。

PUF未测项：物理熵、真实振荡频率范围、温压/老化、多芯片唯一性、保密helper/纠错参数及抗回滚。
这些依赖物理样本与安全目标；不以行为模型产生的可重复频率宣称已完成。条件时序分析中的RO周期必须标假设，
板上测到界限后重新评估计数器时序、跨域稳定窗口和reset pulse-width。

## 4. 归档

每次记录：source/dirty/hash、bit/hwh/固件身份、工具/板卡/系统、命令、退出码、原始JSON/log、
成功/失败样本、计时边界、恢复结果。输出放 `data/advanced/{dma,puf}/board_<日期>/`。
不将新结果倒填到原release或既有简介的旧测试记录。

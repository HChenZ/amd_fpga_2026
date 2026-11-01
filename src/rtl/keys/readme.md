# PUF v1 共享内核与旧集成边界

更新：2026-11-01。当前 PUF3 使用这里的 PUF v1 物理环/采样/DNA/派生组件，但不用本目录的旧 key_mmio.v。
PUF3 build.tcl 明确换入 board/vivado_zynq7000_xc7z020_pynq_puf3/rtl/key_mmio.v 和 soc_top.v，
由 HWKEY_ON/OFF 选择密钥；src/rtl/soc_top.v 的自动锁钥路径是另一种旧集成。

keys_rv32 v3 是早期自检固件修复版；PUF3 是三模式服务 + PUF v1，并非 PUF 第三代。
keys_v2、puf_soc_v2、puf_min 是独立实验，不应为统一名称替换这里的实现。
原始响应/helper/DNA 调试可读，RO计数器域未签核、跨上电等未测；不宣称可靠保密密钥或安全启动。
本次只补说明，RTL、约束和既有证据不变。当前与历史入口见 docs/version_entrypoints.md。

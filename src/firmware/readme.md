# 固件入口与共享依赖

更新：2026-11-01；owner TBD。构建程序保持原行为，不把旧固件改名冒充 PUF3。
当前入口见 [版本速查](../../docs/version_entrypoints.md)。

| 目录 | 对应版本 | 本次用途 |
|---|---|---|
| `pynq_svc_puf/` | **pynq-svc-puf3**；Y01 三模式 + Y01P/Y01K | **PUF3 主固件**，入口 build.py |
| `pynq_svc/` | 旧 pynq-svc-v1 | main.c/build.sh 是旧服务；svc_io.c、ascon_modes.c、svc.h、bin2coe.py 被 PUF3 共享 |
| `ascon_hw_rv32/` | PL-only MMIO 自测 | main.c 不是当前服务；crt0.S、libc_min.c、riscv.ld、bin2vhex.py 被 PUF3 共享 |
| `ascon_rv32/` | PL-only 软件自测 | 历史/研究 |
| `ascon_ise_rv32/` | PL-only ISE 自测 | 历史/研究 |
| `keys_rv32/` | PUF v1 ASCII 自检，v3 为握手修复版 | 旧 keys3/PUF-only 用，不是 PUF3 的 main |
| `keys_v2/` | 独立 PUF v2 自检 | 不用于 PUF3 |
| `pynq_dma_svc/` | 独立 CPU-DMA 固件，D01/ABI v2 | 不用于 PUF3 |
| `cicc1000023/` | 原 CoreMark/FreeRTOS/ISA 源资产 | 原 baseline 研究线；缺口与原名恢复规则见该目录 readme |

`pynq_svc_puf/build.py` 使用 12 项构建输入，记录在 candidate/reports/firmware_build.json。
`pynq_svc/svc.h` 的 FW_ID_STR 仍为旧值，但 PUF3 main.c 明确 undef 后覆写为 pynq-svc-puf3；不要全局改共享头文件。
bit 中 BRAM 固件由 COE 初始化；重新编译 ELF/BIN 不会自动替换已发布 bit，工件变化必须重新绑定验证。

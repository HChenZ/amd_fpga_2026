# RTL 源集选择：不是一个目录对应一个应用版本

更新：2026-11-01；owner TBD。公共 CPU/Ascon/总线/外设位于本目录；最终源清单必须由所选工程构建入口决定。

| 对象 | 必须采用的源选择 |
|---|---|
| **PUF3** | 使用 board/vivado_zynq7000_xc7z020_pynq_puf3/build.tcl；排除本目录 soc_top.v、top_pl_bram.v、keys/key_mmio.v，换入该 board 的 rtl/soc_top.v、rtl/key_mmio.v |
| 旧 PYNQ v1 | board/vivado_zynq7000_xc7z020_pynq/rtl_p0/ 的 soc_top/ascon_mmio，无 PUF |
| 旧 PL-only/PUF v1 | 当时的源码快照或本目录原 soc_top；会自动锁定 HWKEY，不等价于 PUF3 |
| 独立 DMA/PUF v2/MIN | ascon_dma、pynq_dma_cpu、keys_v2、puf_soc_v2、puf_min 各自构建源集，不加入 PUF3 |
| Cache 实验 | dcache_experiments 是保留实验副本，不替换当前 dcache.v |

PUF3 key_hw_sel 由软件 HWKEY_ON/OFF 控制；把旧 soc_top 误加入会改变官方 KAT 的密钥路径。
不要为“统一版本”改 RTL、批量重命名、全局替换 ID 或把所有子目录加入同一 Vivado 工程。
角色、工件与验证边界见 [版本入口](../../docs/version_entrypoints.md)。

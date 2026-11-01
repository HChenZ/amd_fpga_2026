# 当前 PUF3 主采样与历史边界

更新：2026-11-01。最终报告唯一主采样为notebook_20261031_114512/result.json，
bit/hwh/manifest绑定board/vivado_zynq7000_xc7z020_pynq_puf3/candidate。
三模式各289 KAT/289坏Tag拒绝；KAT#529的性能在HWKEY关闭下测量，PUF功能另段记录。

10-30的三次旧运行（包括首次62.5MHz失败）已由c05782d移出工作树，留在Git历史；
旧6例与后续289例是测试运行的演进，不都代表换了bit。
当前仍只有会话内PUF功能，RO计数器时序、跨上电/PVT/BER等未闭合，墙钟仅summary。
本次说明不改result.json、已执行Notebook、manifest或当时包；新运行必须另建目录并重新核对版本。

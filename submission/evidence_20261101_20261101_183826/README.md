# 最终报告证据包

11-01 提交候选；此包不是完整工程源码快照（源码包见仓库 submission/freeze_manifest.md）。
报告：docs/tech_report/amd_fpga_2026_latex_final/amd_fpga_2026_report/output/pdf/final_report.pdf（SHA-256 603c625a8e8f3c1271d9d96f1d4982e15ded676de9262c4ef3813111124e4825），LaTeX 源同目录；
该 PDF 由报告构建 build_20261101_174743 产出，装配时核对：PDF 哈希、报告源与证据输入均与构建记录一致，
报告自带 evidence/pdf 核对 PASS，且板测结果均为 data/pynq_puf3/notebook_20261031_114512/result.json。
主演示为 PUF3 overlay（X-1/X-2）；C-1～C-5 的 PYNQ v1 release（pynq-svc-v1）在报告中作历史对照，
其错误门禁 9/9 不属于 PUF3；历史 PL-only 与独立 PUF 原型分别标注。
根目录 sha256sums.txt 覆盖所有随包文件；原始目录结构保持为仓库相对路径；分组见 extra_manifest.md。
限制：PUF3 跨上电/PVT/BER 未测，RO 计数器域未签核，PUF 原始数据可读，墙钟仅有 summary；
Skill L2 为 simulated 且对安慰剂不显著，L3 验证版本早于最新离线修复；DMA 吞吐未测。
硬件结果未在装配时重测；团队信息、PPT、视频与上传动作由项目方完成。

# 当前报告证据包

11-01 提交候选；此包不是完整工程源码快照。
报告：docs/tech_report/latex/main.pdf；Overleaf：docs/tech_report/latex_project.zip。
主线为当前PYNQ三模式，历史PL-only与独立PUF原型分别标注。
根目录sha256sums.txt覆盖所有随包文件；原始目录结构保持为仓库相对路径。
硬件/长时/Skill结果未在装配时重测；团队信息、PPT、视频与上传动作由项目方完成。
报告附录 C 只覆盖 C-1～C-12；10-30/10-31 新增的 pynq_puf3、Skill 实测、D02 数值核对与视频脚本见 extra_manifest.md（X-1～X-8），
冻结哈希与源码包见仓库 submission/freeze_manifest.md（装配后生成，不在本包内）。
装配时已校验候选哈希、板测结果与候选/L2 文件绑定及 PASS 状态。
限制：pynq_puf3 跨上电与 RO 时序未闭合，PUF 原始数据可读；Skill L2 为 simulated 且对安慰剂不显著，
L3 验证的 Skill 版本为 7bc1abf，其后 S04 新增仅离线验证；DMA 吞吐与 short_output/missing_tlast 未测。

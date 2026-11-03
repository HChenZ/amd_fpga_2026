# 当前PUF3代码入口

本目录是交付包的工程根，内部src/board/sim/ascon/build/data相对层级保持不变。源提交和逐文件来源见上级delivery_manifest.json；完整操作步骤见上级README.md。

- 当前Vivado入口：`board/vivado_zynq7000_xc7z020_pynq_puf3/build.tcl`。
- 现成候选：同目录`candidate/`（bit/hwh/bin/coe/elf/manifest/sha256sums及原报告），未重建或修改。
- 固件：`src/firmware/pynq_svc_puf/build.py`，共享`pynq_svc`、`ascon_hw_rv32`。
- 当前板测：`src/pynq_puf3/pynq_puf3_board_test.ipynb`；ASCON_REPO必须指向本目录。
- 最小检查：`python -B -X utf8 tools/verify_puf3_sources.py --compile`（另需Icarus）。
- 主机单测：`python -B -m unittest discover -s src/pynq -p "test_*.py"`。
- 接口与技术约定：`report/design/`。

保留原名的共享Ascon工程目录只包含两项实际导入的XCI和其引用的ascon_keys.coe，不包含旧XPR和独立工程。
公共src/pynq中的v1 CLI/Notebook为共享兼容支持；并非当前上板入口。
data/ascon/results/key_lifecycle内六项历史fixture只供host单测追溯；source manifest标明其来自归档，不冒充新数据。
本包不含.git；查询Git的原脚本需按上级README先建立本地快照。该本地SHA不是原上游SHA。
原说明中指向archive、旧delivery或仓库维护日志的链接仅适用于完整源仓库；本包有意不含这些历史独立项目。

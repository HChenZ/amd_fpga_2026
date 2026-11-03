# 旧 PYNQ v1 桥接/服务验证

更新：2026-11-01。本目录主要验证旧 pynq-svc-v1 / rtl_p0，elab_check.sh 使用无PUF源快照与IP空壳，
不等于 PUF3 全系统功能验证。旧结果保留其源版本，不转记到 PUF3。
部分桥接模型/模块有共享用途，默认脚本不修改；当前 PUF3 入口是 sim/pynq_puf3/run.py 与板端 Notebook。
选择与边界见 docs/version_entrypoints.md，勿只换 COE/路径就宣称同一版本。

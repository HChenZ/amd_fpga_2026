# 独立 Skill 交付

本次唯一安装包是 [pynq-overlay-workflow](pynq-overlay-workflow/README.md)，和PUF3工程运行解耦。
完整目录含SKILL.md、scripts、references、examples、tests；交付ZIP由tools/package_delivery.py生成。

```sh
python -m pytest skill/pynq-overlay-workflow/tests -q
python skill/pynq-overlay-workflow/scripts/pynq_skill_cli.py --help
```

当前仓库/独立解包环境中，依赖另一个工程实物工件的3个可选测试会skip；剩余61项通过。
这不是新板测或新受控实验结论。既有L2为simulated，L3 Ascon测试对象是旧v1，不能转记为PUF3。
L2/L3工具与辅助RTL纪律Skill隔离在archive/history/skill，原始记录在archive/evidence；不是安装依赖。
许可在交付包中保留，本次不改SKILL.md或工具逻辑来硬编码PUF3。

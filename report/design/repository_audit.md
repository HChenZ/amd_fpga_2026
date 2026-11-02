# 当前仓库布局与复现边界

更新：2026-11-02；任务D06，owner TBD。

当前源集由 `board/vivado_zynq7000_xc7z020_pynq_puf3/build.tcl` 定义，不能把整个仓库递归导入Vivado。
它复用公共RTL、PUF v1/PYNQ桥，替换board-local的soc_top/key_mmio，并导入保留的Ascon工程XCI。
`puf_opt_pre.tcl`还会读取 `build/keys_ro_allow_loops.tcl`；这类hook依赖必须随源码包一起交付，
单独Icarus elaboration不能证明Vivado输入齐全。

- 当前与历史依赖清单：[源码](../../src/readme.md)、[board](../../board/readme.md)、[版本入口](version_entrypoints.md)。
- 独立历史源码：[archive/history](../../archive/history/README.md)；旧源审计和原始描述另在证据归档中保留。
- 原始日志/实现报告/旧提交变体：[archive/evidence](../../archive/evidence/README.md)，成员hash校验，不改结果。
- 交付ZIP与校验：[delivery](../../delivery/README.md)。工程只带源码、配置、向量与少量主机测试fixture。

解压验证包括固件重编译、候选BIN比对、host/Skill离线测试、RTL elaboration和静态构建输入检查。
本轮不新跑Vivado综合/实现或实板，不把源码包装配PASS写成clean-clone硬件端到端验收完成。
历史脚本以当时路径留档，不承诺在archive/history内直接运行；历史ZIP还附公共支持，但须核对旧源版本。

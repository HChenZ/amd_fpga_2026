# PUF3 构建与交付校验

当前构建顺序（源码包在仓库根运行，需本机工具）：

```sh
python -X utf8 src/firmware/pynq_svc_puf/build.py
python -X utf8 sim/pynq_puf3/run.py
vivado -mode batch -source board/vivado_zynq7000_xc7z020_pynq_puf3/build.tcl -notrace
```

现有build.tcl拒绝覆盖同名工作区；重建会产生新的工件，必须按其输出重新绑定验证，不能冒用10-31板测。
本目录keys_ro_allow_loops.tcl/keys_ro_pblock.xdc是共享支持，保留原字节；其他旧时序/策略实验已隔离到archive/history/build。
源码打包入口为tools/package_delivery.py；只打包源码与配置，不把原始证据归档塞进工程附件。
原始报告/旧元数据在archive/evidence，必要时用tools/restore_records.py恢复本机忽略副本。

完整仓库的交付包校验：`python tools/verify_delivery.py`（另需pytest、PyMuPDF、Icarus与上述交叉工具链）。
它在仓库外解压后重编译固件、比对BIN、跑host/Skill并检查构建输入；不运行Vivado/实板，也不覆盖现成candidate。

# 当前源码布局

- `rtl/`：公共CPU、Ascon、PUF v1和PYNQ桥接；PUF3两个关键变体在board下，必须按专用Tcl排除/替换。
- `firmware/pynq_svc_puf/`：当前服务固件。
- `firmware/pynq_svc/`、`firmware/ascon_hw_rv32/`：当前固件复用的I/O、三模式算法、启动/链接/转换支持；不要误删。
- `pynq_puf3/`：完整板测Notebook，内嵌PUF3身份驱动；仍依赖pynq公共API/协议/参考函数。
- `pynq/`：上述公共库，部分旧v1兼容模块因import复用保留；其旧CLI不是当前入口。

独立DMA/PUF v2/MIN、旧单镜像固件和原始CPU资产在archive/history/src，源码保留但不参与当前PUF3构建。
版权/许可证按原文件保留；对外说明只描述实际结构、接口和验证，不以目录名推断来源或原创范围。

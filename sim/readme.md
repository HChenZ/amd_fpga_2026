# 当前验证入口

- `pynq_puf3/run.py`：当前真实RV32固件/AXI-Lite/UART协同仿真，normal与autolock反例必须都符合预期。
- `ascon/`：Final参考/向量、独立RTL与当前单元TB；不再放默认源集已漂移的旧CPU整机runner。
- `keys/`：PUF v1单元/行为模型，被当前协同仿真复用；模型不证明物理PUF可靠性。

旧CPU/板前/DMA/PUF v2/MIN/旧v1验证工具在archive/history/sim；其旧PASS/FAIL只对当时源版本负责。
当前PUF3不能直接用旧无PUF或独立DMA结果补齐验收。临时编译/波形留在忽略的build/local。

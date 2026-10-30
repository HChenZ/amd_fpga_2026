# 接口契约格式（`*.contract.json`）

契约是主机与 PL 之间的**唯一**寄存器真相来源。驱动、测试骨架、文档都从它生成；
硬件改了先改契约，再重新生成，不手改生成文件。

```json
{
  "contract_version": 1,
  "name": "vadd",
  "vlnv": "xilinx.com:hls:vadd:1.0",
  "addr_range": 65536,
  "source": "vadd/solution1/impl/misc/drivers/vadd_v1_0/src/xvadd_hw.h (Vitis HLS 2023.2)",
  "identity": [{"register": "VERSION", "value": "0x00010000"}],
  "registers": [
    {"name": "CTRL", "offset": "0x00", "access": "rw",
     "fields": [
       {"name": "AP_START", "lsb": 0, "width": 1, "access": "rw"},
       {"name": "AP_DONE",  "lsb": 1, "width": 1, "access": "rc"},
       {"name": "AP_IDLE",  "lsb": 2, "width": 1, "access": "ro"}
     ]},
    {"name": "A_LO", "offset": "0x10", "access": "wo"},
    {"name": "A_HI", "offset": "0x14", "access": "wo"}
  ],
  "pairs": [{"name": "A", "lo": "A_LO", "hi": "A_HI"}]
}
```

规则（`regmap.load_contract` 会检查，违反即抛 `ContractError`）：

| 字段 | 规则 |
|---|---|
| `offset` | 整数或 `0x` 字符串；4 字节对齐；`offset + width/8 <= addr_range`；不得重叠 |
| `access` | `rw` `ro` `wo` `rc`(读清) `w1c`(写 1 清)；字段可以比寄存器更严格 |
| `width` | 默认 32；只支持 32（64 位用 `pairs` 拆成 lo/hi） |
| `fields` | `lsb + width <= 32`，同寄存器内不得重叠 |
| `identity` | 加载后必须读回的固定值（ID/VERSION），`verify_identity()` 使用 |
| `pairs` | 64 位逻辑量，`write_pair()` 总是先写 lo 再写 hi，两个都写 |
| `source` | 写明契约来自哪份权威文件及版本，便于审计 |

寄存器整体 `access` 为 `rw` 但含 `rc` 字段时，对该寄存器的**字段写**会被拒绝（读-改-写会消费读清位）；
请用整寄存器 `write()` 显式给出全部位。

`examples/` 中三份契约与具体比赛题目无关：
- `axi_gpio.contract.json` —— Xilinx AXI GPIO（PG144）通道 1/2 与中断寄存器
- `hls_vadd.contract.json` —— 典型 Vitis HLS `ap_ctrl_hs` + 两个 m_axi 指针 + 标量参数
- `axi_dma_simple.contract.json` —— AXI DMA（PG021）简单模式寄存器

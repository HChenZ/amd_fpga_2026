# PYNQ host layer and board validation

**2026-11-02 隔离说明**：本目录保留PUF3所需的公共API/协议及因import复用保留的旧兼容模块；
DMA/PUF v2/MIN主机工具已移到archive/history/src/pynq，旧硬件工件移到archive/history/board。
下面v1 CLI默认路径是历史行为，当前不作为可直接运行入口；PUF3只用src/pynq_puf3的Notebook。
本轮不改共享库算法、身份常量或Notebook来强行统一。

## 2026-11-01 版本适用范围（优先阅读）

本目录是**多版本公共主机库 + 旧 PYNQ v1 入口 + 独立实验主机工具**，不是 PUF3 专属目录。
当前主演示请打开 [src/pynq_puf3/readme.md](../pynq_puf3/readme.md) 所指的 Notebook。
以下 10-29 的 9/9 门禁和使用命令都属于 **pynq-svc-v1 / ID 0x514e5950 / 无 PUF 的 release**，
不据此宣称当前 PUF3 完整错误恢复矩阵已通过。

| 文件/用法 | 当前职责 |
|---|---|
| ascon_host_api/mailbox_protocol/mailbox_backend/golden_checker | PUF3 等多个版本共享的 API/编解码/参考 |
| board_benchmark 的 _run_once/select_kat_case/summarize | PUF3 Notebook 正常复用的纯函数；不调用其旧 prepare_hardware |
| board_demo/board_benchmark/board_error_gate 的 CLI | **旧 v1 专用**：固定 pynq.bit/hwh、pynq_svc.elf、pynq-svc-v1；仅换 --release 路径也不能用于 PUF3 |
| pynq_board_demo/pynq_board_error_gate.ipynb | 已执行的旧 v1 板测/门禁，保留证据；不要录作当前 PUF3 视频 |
| pynq_transport 的 BridgeRegs/from_overlay | 默认旧控制 ID；PUF3 使用内嵌子类覆写，不全局改共享身份门禁 |
| make_pynq_profile | 有通用 HWH 解析，来源描述/使用示例仍是旧 v1，不是完整 PUF3 loader |
| dma_transport | 独立 CPU-DMA/HW_DIRECT 的 D01/ABI v2，不是 PUF3 UART 服务 |
| puf_helper_v2/puf_min | 独立 PUF v2/MIN，不参与当前 PUF3 运行 |
| jupyter_demo/navigator_demo | 无板或注入式后端演示，不当作 PUF3 实板证据 |

程序、默认值与旧输出不改；完整说明见 [版本入口](../../report/design/version_entrypoints.md)。
Skill 在 `skill/` 中独立交付、S01–S05 已有对应范围证据；下面“本目录不包含 Skill”只是目录职责。

## 旧 PYNQ v1 使用说明与 10-29 验证记录

更新：2026-10-29。owner TBD。

当前状态：Y01-Y05 与 V03 已完成实板验收。三模式容量内 289/289 KAT、坏 Tag 拒绝、
Notebook 从头执行、KAT #529 的 30 次 warm benchmark、9/9 错误/恢复门禁均通过。
证据见 `board/vivado_zynq7000_xc7z020_pynq/validation_20261029.md`。

本目录仍不包含通用 Skill（S01-S05）、完整 800 组超 16B 硬件 KAT、动态固件 loader
或 clean-clone 验收。历史无板说明保留在下方，不能覆盖 2026-10-29 结果。

## 文件与使用

- `ascon_host_api.py`：后端契约、锁定 Python reference 适配器、输入检查、具体异常。
- `golden_checker.py`：全量 KAT、逐字节差异、篡改拒绝、可选故障注入。
- `jupyter_demo.ipynb`：无板展示骨架，无已保存输出；可从仓库根或本目录顺序运行。
- `test_host_api.py`：17 项标准库测试，包括 notebook 全部代码单元顺序执行。
- `pynq_transport.py`（2026-10-27 新增）：**真实硬件** Transport 实现 —— pynq.MMIO 两个窗口
  （控制 + 字节 FIFO）、Y01 分帧、批量反压、绝对 deadline、epoch/ACK 语义。
  默认构造即 fail-closed（无 overlay / ID 寄存器不对 → `NotConfiguredError`），
  握手帧若带 SIMULATED 位就如实上报 simulated=True，绝不回落到模拟。
- `test_pynq_transport.py`：14 项**寄存器级模型**测试（无板）；模型帧带 SIMULATED 位，
  所以只证明驱动逻辑，不产生硬件证据。
- `make_pynq_profile.py`：`.hwh` → navigator profile（含 bit/hwh/firmware 的 sha256），
  生成后立刻调 `navigator_backend.validate_overlay()` 自检；`--selftest` 用合成 hwh 跑通链路。
- `board_benchmark.py`：实板固定输入 warm benchmark。默认使用官方 KAT `#529`
  （PT=16 bytes、AD=0），每模式预热 5 次后采集 30 次加密和 30 次解密，保留全部
  `mcycle`、PS wall time、min/median/P95/max、cycles/byte 和相对 SW 加速比。
- `test_board_benchmark.py`：benchmark 选择器、统计口径和 Notebook 无临时路径的离线测试。
- `board_error_gate.py`：V03 实板错误/恢复门禁。测试 17-byte 长度拒绝、半帧、
  transport deadline、重复 request_id、错误 epoch 和 RX FIFO overflow；每个故障后
  reset、验证 epoch 改变，并重跑 SW/HW/ISE KAT，最后执行每模式 50 次合法往返压力。
- `test_board_error_gate.py`：门禁的 header-only 注入、状态契约、Notebook 与失败
  非零退出离线测试。
- `pynq_board_error_gate.ipynb`：执行完整 V03 门禁并把身份、JSON、日志写入
  `data/pynq/error_gate_<时间>/`。
- 板级设计、寄存器表、GUI 建工程步骤见 `board/vivado_zynq7000_xc7z020_pynq/readme.md`；
  M1 起板步骤见 `docs/pynq_bringup_m1.md`。

## 实板 benchmark

推荐在板端 Jupyter 中打开 `pynq_board_demo.ipynb`，执行
`Restart Kernel and Run All Cells`。Notebook 会先跑三模式 smoke KAT，再跑固定输入
warm benchmark，并把身份、JSON 和日志写入新建的 `data/pynq/notebook_<时间>/`。
Notebook 默认使用板端绝对路径
`/home/xilinx/jupyter_notebooks/amd_fpga_2026`；若 Jupyter 以 root 启动，
`Path.home()` 会变成 `/root`，不能依赖 `~` 推断仓库位置。不同路径用
`ASCON_REPO` 显式覆盖。

如果 Jupyter 内核没有加载 Overlay 所需的权限，可在板上仓库根目录用
`nbconvert` 以 root 从头执行，无需临时 Python 文件：

```bash
sudo -E env ASCON_REPO="$PWD" PYTHONDONTWRITEBYTECODE=1 \
  PYTHONPATH="$PWD" PATH="$PATH" \
  jupyter nbconvert --to notebook --execute \
  src/pynq/pynq_board_demo.ipynb \
  --output pynq_board_demo.executed.ipynb \
  --output-dir data/pynq
```

也可以直接运行永久 CLI：

```bash
sudo -E env PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PWD" PATH="$PATH" \
  python3 -B src/pynq/board_benchmark.py \
  --warmup 5 --repetitions 30 \
  --out data/pynq/board_20261029/pynq_warm_benchmark.json
```

`mcycle` scope 是 RV32 固件中的 AEAD 调用边界，不包含 PS/UART 传输；wall time 单列，
只作 PS 端观察值。`--out` 只在全部调用通过 KAT 后生成，失败返回非零且不写通过报告。

## 实板错误与恢复门禁

在板端 Jupyter 中打开 `pynq_board_error_gate.ipynb` 并执行
`Restart Kernel and Run All Cells`。测试会主动复位 RV32 SoC，但不会重新生成或修改
bit/hwh/firmware。失败报告也会保存，最后一个单元再以断言终止。

也可以在仓库根目录运行永久 CLI：

```bash
sudo -E env PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PWD" PATH="$PATH" \
  python3 -B src/pynq/board_error_gate.py \
  --stress-per-mode 50 \
  --out data/pynq/board_error_gate.json
```

17-byte 超长用例只发送 48-byte header，不发送不可信 body，避免固件正确处理长度拒绝后
主机仍阻塞于未消费 body。报告通过标准是全部 check 为 PASS；任何失败写入 JSON 后
CLI 返回非零。当前 Y01 使用 UART uncached MMIO，没有共享可缓存 buffer，因此缓存可见性
记为 `NOT_APPLICABLE` 并附架构理由。

从仓库根目录运行（`python` 应为 Python 3.11；验证时使用 3.11.16）：

```python
from src.pynq.ascon_host_api import AsconHost, SimulatedBackend, AuthenticationError

host = AsconHost(SimulatedBackend(mode="ise"))
# 仅用于演示的公开输入；部署必须保证同一 key 下 nonce 唯一。
key, nonce = bytes(range(16)), bytes(range(16, 32))
encrypted = host.encrypt(key, nonce, b"", b"0123456789abcdef", timeout_s=5.0)
print(encrypted.ciphertext.hex(), encrypted.tag.hex())
print(encrypted.cycles, encrypted.cycle_info, encrypted.simulated)
decrypted = host.decrypt(key, nonce, b"", encrypted.ciphertext, encrypted.tag)
assert decrypted.plaintext == b"0123456789abcdef"
```

API 输入严格为 `bytes`；key、nonce、tag 各 16 bytes。
模拟后端 message/AD 各最大 65,536 bytes（host 资源限制，非算法上限）。
支持空输入和多块消息，不继承当前 MMIO 硬件的 16-byte 限制；即使选择
`mode="hw"` 也仍是 Python 算法模拟，**不证明多块硬件支持**。

返回不可变 `EncryptionResult(ciphertext, tag, cycles, cycle_info, backend, simulated)`
或 `DecryptionResult(plaintext, cycles, cycle_info, backend, simulated)`。
`cycles=None`、`cycle_info.status="not_measured"` 表示没有适用的周期证据，不能视为 0。

### 错误契约

| 异常 | 条件 |
|---|---|
| `InvalidLengthError` | key/nonce/tag 长度不符或超过后端容量 |
| `AuthenticationError` | 完整 16-byte tag 认证失败，不返回明文 |
| `BackendTimeoutError` | 后端超时或返回结果已超过预算，丢弃结果 |
| `BusError` | 后端传输 `OSError`，不返回垃圾数据 |
| `BackendProtocolError` | 返回类型或有效长度不符合契约 |
| `ReferenceIntegrityError` | 锁定参考/KAT SHA-256 不符 |
| `TypeError` / `ValueError` | 非 bytes 输入 / 非有限正数超时 / 未知 mode |

异常不携带 key、候选明文或底层传输详情。Python 不提供可靠的内存擦除或常数时间保证；
该 reference 后端用于验证和展示，不是生产密钥保护方案。

## Backend 与 Y01 的关系

`AsconHost(backend)` 注入 `Backend` 子类。后端实现：

```text
name: str, simulated: bool
max_message_bytes: int, max_ad_bytes: int
encrypt(key, nonce, ad, plaintext, *, timeout_s) -> (ciphertext: bytes, tag: bytes)
decrypt(key, nonce, ad, ciphertext, tag, *, timeout_s) -> authenticated plaintext: bytes
cycle_info(operation, message_bytes, ad_bytes) -> CycleInfo
```

`cycle_info` 默认返回未测；真实后端应返回本次原子完成请求的周期证据。
解密必须在认证成功之后才返回，认证失败抛 `AuthenticationError`。
传输错误可抛 `OSError`，超时可抛 `TimeoutError`，host 将转换成上述具体异常。
host 还会检查输出长度，但不能替代后端的认证门禁或检测任意错误密文；golden checker
负责逐字节正确性验证。

本段是历史无板状态。当前 Y01 UART mailbox v1 已冻结并通过 V03 实板错误/恢复验收；
PS 地址来自 HWH，CPU UART 地址为 `0x20000000`。
未来 `PynqBackend` 按相同接口替换，无需改变用户加解密调用；本轮不实现假硬件类。
需先冻结协议版本、request_id、端序、buffer 容量、命令/完成/错误、64-bit mcycle、
所有权、cache flush/invalidate、屏障、固件加载及超时后的取消/复位策略。
后端必须在传输和轮询内部执行 deadline，失败后不得复用旧完成状态或候选明文。
host 的返回后计时检查不能中断卡死的后端；同步 Python 模拟也只能运行后丢弃迟到结果，
不是可抢占的硬实时超时。测试用受控时钟和异常注入核验该路径，不宣称真实总线验证。

## Reference、KAT 与周期来源

不复制、不修改锁定算法。模拟计算调用
`sim/ascon/reference/pyascon/ascon.py`，提交
`ed24e54abf9507d26fa49b46a56091570c7e743e`，CC0-1.0；
KAT 为 `data/ascon/kat/asconaead128.txt`，来自 ascon-c 提交
`446347f21b209f3921c65ece70027c366cbe1693`。
两者的固定 SHA-256 写在 API 中，执行前检查；详细来源/许可见
`data/ascon/provenance.json`。加载采用只读源码执行，不在 reference 目录写 pycache。

checker 同时对照生产 Python `ascon/pyascon/ascon.py` 和官方独立 expected CT||tag，
不使用“自己加密再解密”作为唯一证据。任务卡的 `ascon/python/` 不存在，真实路径为
`ascon/pyascon/`。C 生产实现位于 `ascon/ascon_c/aead/`，锁定 C 在
`sim/ascon/reference/ascon_c/`；本轮选择零编译依赖的 Python reference，**未重跑 C 编译验证**。
KAT 完整覆盖 PT/AD 各 0..32 的 1,089 个组合。

每组比较 API 与生产 Python 的加密 CT||tag、解密明文；再用官方 CT||tag 翻转首尾 tag，
非空消息另翻转首尾密文，确认 API 抛认证异常。共 4,290 次拒绝。
FAIL 输出首个差异偏移 `byte=N`（从 0 起）；加密偏移基于 CT||tag，解密基于 PT。
长度差异输出 `<end>`；任何失败退出 1，包括 hash/setup 错误。

### simulated 周期表（历史采样，不是当前调用的测量）

仅将 **16-byte、AD=0 的加密**关联到以下历史 warm RV32 样本。
值是任务卡指定的展示占位，不随本次 key/nonce 改变，不对其他长度或解密外推。
API 本次 CT/tag 是 reference 计算；本次并没有执行 RISC-V、MMIO 或 ISE。

| mode | cycles | sw/mode | 测量范围 | 文件 stem |
|---|---:|---:|---|---|
| sw | 17353 | 1.000x | CPU 纯软件 AEAD | sw_timing_acb_sw |
| hw | 670 | 25.900x | CPU full MMIO 往返，非 99-cycle crypto-only | hw_timing_acb_hw |
| ise | 2496 | 6.952x | CPU 编排 AEAD，置换 ISE | ise_timing_acb_ise |

文件均位于 `data/ascon/results/key_lifecycle/`。JSON 记录 simulation/PASS/命令和源 hash；
**数值本身在同名 `.log`**，`CycleInfo.source` 指向原始 log，测试同时核验 JSON 和 log。
这些均不含 PS/Python 传输时间，不是板级实测，也不是当前 Python wall time。

## 验收证据（2026-10-18）

仓库根目录、CPython **3.11.16**，实际执行结果：

| 命令 | 结果 | exit code |
|---|---|---:|
| `python src/pynq/golden_checker.py` | KAT PASS 1089 / FAIL 0；TAMPER REJECT 4290 | 0 |
| `python src/pynq/test_host_api.py` | Ran 17 tests / OK；含六类向量 × 三个 mode，notebook 顺序执行 | 0 |
| `python src/pynq/golden_checker.py --inject tag` | PASS 1088 / FAIL 1，kat_0001 byte=0 | 1（预期） |
| `python src/pynq/golden_checker.py --inject ciphertext` | PASS 1088 / FAIL 1，kat_0034 byte=0 | 1（预期） |

两条注入命令由 `test_injected_cli_exits_nonzero` 在独立子进程实际执行，不改 KAT 文件；
错误接受认证、hash 故障、错误输出/长度、空消息、1B/16B/16B+AD/17B/32B、
输入越界、非法 timeout、超时丢弃、总线错误转换均有测试。
notebook 验证是标准库读取 JSON 后顺序执行代码单元，未启动 Jupyter 前端。
正常 checker 也在默认 Python 3.13.9 下实跑 PASS；目标版本验收以 3.11.16 为准。

## 历史交接与当前边界

- 已完成：任务卡 A 的 host/reference/KAT/notebook 无板子集；新接口仅在本目录，无 RTL/固件改动。
- 2026-10-29 已补充：真实 PYNQ、overlay/bit/hwh、UART mailbox、实物板周期和错误恢复均已验证；
  shared cacheable buffer 不适用于当前 ABI。
- 新阻塞：V04 历史 xpack 工具链缺失导致 firmware ELF entry=`0x10000024`，与复位 PC
  `0x10000000` 不一致；完整证据见 `docs/current_status_20261029.md`。
- 按任务卡并行边界，不修改 `docs/`、`tasks/`、actual_progress 或 lessons；交给主线维护者同步状态。
  仅在共享 `project_log/development_log.md` 末尾追加本轮事实；未 commit/push，未启动 Vivado。

## 历史：Y01 板型无关协议与通信模拟（2026-10-18）

用户授权先做无板型部分。协议说明见 **[mailbox_protocol.md](mailbox_protocol.md)**，
状态为 **draft v1**，不代表真实Y01协议已冻结，不变更现有RTL/固件接口。

新增：
- `mailbox_protocol.py`：little-endian有界请求/响应帧、非零64-bit会话与请求ID、严格长度/状态检查。
- `mailbox_backend.py`：可替换Transport、MailboxBackend，以及明确标为simulated的MemoryTransport。
- `test_mailbox.py`：24项协议、所有权、认证、deadline和恢复门禁测试。

`golden_checker.py` 新增 `--backend mailbox --mode sw|hw|ise`，默认仍是原reference后端。
MailboxBackend直接接入AsconHost，原加解密API不变；没有真实PYNQ后端、物理地址或寄存器映射。
模拟peer支持32B消息/AD以覆盖完整KAT，不证明当前16B MMIO硬件支持多块。

```python
from src.pynq.ascon_host_api import AsconHost
from src.pynq.mailbox_backend import MailboxBackend, MemoryTransport

backend = MailboxBackend(MemoryTransport(), mode="ise")
host = AsconHost(backend)
# 按前文相同 encrypt/decrypt 调用即可。
# 超时/总线错误/坏响应后，backend.needs_recovery 为 True；禁止隐式重试。
# backend.recover(timeout_s=5.0) 确认新epoch并释放旧请求后，才能提交新请求。
```

此后端通过submit/poll/ACK模拟完整单槽事务。响应身份、长度、证据类型不匹配、
超时或总线错误均隔离通道；失败响应不含明文或周期；ACK失败也不发布结果。
MemoryTransport正常响应的cycles始终为None/not_measured，**不复用历史周期占位**。
本节是历史无板记录。2026-10-28/29 的 UART mailbox 实板结果以上方当前状态和
`mailbox_protocol.md` 为准。

最终实跑 CPython **3.11.16**，仓库根：

| 命令 | 结果 | exit |
|---|---|---:|
| `python src/pynq/test_mailbox.py` | 24 tests OK | 0 |
| `python src/pynq/test_host_api.py` | 原17 tests OK（含notebook顺序执行） | 0 |
| `python src/pynq/golden_checker.py --backend mailbox --mode sw` | PASS1089/FAIL0，拒绝4290 | 0 |
| `python src/pynq/golden_checker.py --backend mailbox --mode hw` | PASS1089/FAIL0，拒绝4290 | 0 |
| `python src/pynq/golden_checker.py --backend mailbox --mode ise` | PASS1089/FAIL0，拒绝4290 | 0 |
| `python src/pynq/golden_checker.py --backend mailbox --inject tag` | PASS1088/FAIL1，kat_0001 byte=0 | 1（预期） |
| `python src/pynq/golden_checker.py --backend mailbox --inject ciphertext` | PASS1088/FAIL1，kat_0034 byte=0 | 1（预期） |

包导入 `src.pynq.mailbox_backend` 和无板加解密示例也已实跑exit0。
共41项unittest通过；三mode是模拟选择，不是三套硬件或编译固件的验证。
周期>32-bit及0/None的测试值只用于codec验证，不是性能结果。

以上是 2026-10-18 无板阶段的原始交接。后续 B03 平台确认、Y01 物理映射、Y02 overlay、
Y03/Y04/V03 均已在 2026-10-28/29 完成实板验收；owner TBD。

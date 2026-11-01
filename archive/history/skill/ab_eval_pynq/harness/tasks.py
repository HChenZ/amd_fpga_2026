"""A/B task bank. Prompts state WHAT is required (identical for every arm); hidden scenarios
check whether the generated code actually meets it on a fake PYNQ with realistic traps.

Each task: prompt, build_workspace(dir) for agent-visible files, scenarios() for grading.
A scenario = files to create + hardware model + a driver snippet run against solution.py.
"""
import hashlib
import json
import os
import random

PS7_HEAD = ('<?xml version="1.0" encoding="UTF-8"?>\n<EDKSYSTEM EDWVERSION="1.2">\n<MODULES>\n'
            '<MODULE FULLNAME="/ps7" INSTANCE="ps7" MODTYPE="processing_system7" '
            'VLNV="xilinx.com:ip:processing_system7:5.5">\n<PARAMETERS>\n'
            '<PARAMETER NAME="PCW_FPGA0_PERIPHERAL_FREQMHZ" VALUE="100"/>\n'
            '<PARAMETER NAME="PCW_CRYSTAL_PERIPHERAL_FREQMHZ" VALUE="33.333333"/>\n</PARAMETERS>\n<MEMORYMAP>\n')


def make_hwh(ips):
    """ips: list of dict(fullname, vlnv, base, params={}, registers='', size=0x10000)"""
    out = [PS7_HEAD]
    for ip in ips:
        inst = ip['fullname'].split('/')[-1]
        out.append('<MEMRANGE ADDRESSBLOCK="Reg" BASENAME="C_BASEADDR" BASEVALUE="0x%08X" HIGHNAME="C_HIGHADDR" '
                   'HIGHVALUE="0x%08X" INSTANCE="%s" MASTERBUSINTERFACE="M_AXI_GP0" MEMTYPE="REGISTER"/>\n'
                   % (ip['base'], ip['base'] + ip.get('size', 0x10000) - 1, inst))
    out.append('</MEMORYMAP>\n</MODULE>\n')
    for ip in ips:
        inst = ip['fullname'].split('/')[-1]
        out.append('<MODULE FULLNAME="/%s" INSTANCE="%s" MODTYPE="%s" VLNV="%s">\n<PARAMETERS>\n'
                   % (ip['fullname'], inst, inst, ip['vlnv']))
        for k, v in ip.get('params', {}).items():
            out.append('<PARAMETER NAME="%s" VALUE="%s"/>\n' % (k, v))
        out.append('</PARAMETERS>\n%s</MODULE>\n' % ip.get('registers', ''))
    out.append('</MODULES>\n</EDKSYSTEM>\n')
    return ''.join(out)


def _sha(data):
    return hashlib.sha256(data).hexdigest()


def _write(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'wb') as f:
        f.write(data if isinstance(data, bytes) else data.encode('utf-8'))


# =============================================================== T1 overlay loader
T1_PROMPT = """# 任务：可靠地加载并校验 PYNQ overlay

板卡运行 PYNQ 2.7（Zynq-7000）。`hw/` 下是一组示例工件：`accel.bit`、`accel.hwh`、`manifest.json`。

请在当前目录写 `solution.py`，实现：

```python
def load_accel(bit_path: str, manifest_path: str):
    \"\"\"返回 (overlay, mmio)\"\"\"
```

要求：
1. `manifest.json` 格式为 `{"files": {"<文件名>": "<sha256 hex>"}}`。必须证明**PYNQ 实际会使用的** bit 与 hwh
   都与 manifest 一致；任何不一致都抛 `RuntimeError`，并且**不得下载**比特流到 PL。
2. 加载后，在 overlay 中找到 VLNV 为 `example.org:user:accel:1.0` 的 IP（实例名和所在层级以后可能变化，不能写死）。
3. 该 IP 偏移 0x1C 是只读 ID 寄存器，必须读到 `0xACCE1001`，否则抛 `RuntimeError`。
4. 返回 overlay 对象与一个可对该 IP 寄存器 `read(offset)`/`write(offset, value)` 的 MMIO 对象。

你无法访问真实板卡；只交付 `solution.py`（可以附简短说明）。不要修改 `hw/`。
"""

T1_VLNV = 'example.org:user:accel:1.0'


def _t1_files(root, *, fullname='accel_0', base=0x43C00000, hwh_name='accel.hwh', bit_name='accel.bit',
              tamper=None, hw_id=0xACCE1001, seed=1):
    rnd = random.Random(seed)
    bit = bytes(rnd.getrandbits(8) for _ in range(4096))
    hwh = make_hwh([{'fullname': fullname, 'vlnv': T1_VLNV, 'base': base},
                    {'fullname': 'axi_gpio_0', 'vlnv': 'xilinx.com:ip:axi_gpio:2.0', 'base': 0x41200000}])
    manifest = {'files': {bit_name: _sha(bit), hwh_name: _sha(hwh.encode())}}
    if tamper == 'stale_hwh':
        hwh = make_hwh([{'fullname': fullname, 'vlnv': T1_VLNV, 'base': base + 0x10000}])
    if tamper == 'bad_bit':
        manifest['files'][bit_name] = '0' * 64
    _write(os.path.join(root, bit_name), bit)
    _write(os.path.join(root, hwh_name), hwh)
    _write(os.path.join(root, 'manifest.json'), json.dumps(manifest, indent=2))
    hardware = {_sha(bit): [{'kind': 'ident', 'base': hex(base), 'regs': {'0x1C': hw_id}},
                            {'kind': 'ident', 'base': '0x41200000', 'regs': {}}]}
    return os.path.join(root, bit_name), os.path.join(root, 'manifest.json'), hardware


T1_OK = """
ol, mm = solution.load_accel(BIT, MAN)
assert mm.read(0x1C) == 0xACCE1001, 'returned MMIO does not address the accel IP'
mm.write(0x00, 5)
result['ok'] = True
"""
T1_MUST_RAISE = """
try:
    solution.load_accel(BIT, MAN)
    result['ok'] = False; result['why'] = 'no exception'
except RuntimeError as e:
    result['ok'] = DOWNLOAD_ALLOWED or pynq.TRACE['downloads'] == 0
    result['why'] = 'raised; downloads=%d' % pynq.TRACE['downloads']
"""


def t1_scenarios(tmp):
    sc = []
    for name, kw, body, dl in [
        ('good_flat', {}, T1_OK, True),
        ('good_hierarchy', {'fullname': 'proc/accel_0', 'base': 0x43C20000}, T1_OK, True),
        ('stale_hwh', {'tamper': 'stale_hwh'}, T1_MUST_RAISE, False),
        ('bad_bit', {'tamper': 'bad_bit'}, T1_MUST_RAISE, False),
        ('wrong_id', {'hw_id': 0xACCE1000}, T1_MUST_RAISE, True),
        ('hwh_not_sibling', {'hwh_name': 'accel_impl.hwh'}, T1_MUST_RAISE, False),
    ]:
        d = os.path.join(tmp, 't1_' + name)
        bit, man, hw = _t1_files(d, **kw)
        sc.append({'name': name, 'hardware': hw, 'code': 'BIT=%r\nMAN=%r\nDOWNLOAD_ALLOWED=%r\n%s' % (bit, man, dl, body)})
    return sc


def t1_workspace(ws):
    _t1_files(os.path.join(ws, 'hw'))


# =============================================================== T2 HLS kernel
T2_HW_H = """// Excerpt of xvadd_hw.h generated by Vitis HLS for:
//   void vadd(const int *a, const int *b, int *c, int n)  // m_axi a,b,c ; s_axilite control
// 0x00 : Control signals
//        bit 0  - ap_start (Read/Write/COH)
//        bit 1  - ap_done (Read/COR)
//        bit 2  - ap_idle (Read)
//        bit 3  - ap_ready (Read/COR)
//        bit 7  - auto_restart (Read/Write)
// 0x04 : Global Interrupt Enable Register
// 0x08 : IP Interrupt Enable Register
// 0x0c : IP Interrupt Status Register (Read/TOW)
// 0x10 : Data signal of a  bit 31~0 - a[31:0] (Read/Write)
// 0x14 : Data signal of a  bit 31~0 - a[63:32] (Read/Write)
// 0x1c : Data signal of b  bit 31~0 - b[31:0] (Read/Write)
// 0x20 : Data signal of b  bit 31~0 - b[63:32] (Read/Write)
// 0x28 : Data signal of c  bit 31~0 - c[31:0] (Read/Write)
// 0x2c : Data signal of c  bit 31~0 - c[63:32] (Read/Write)
// 0x34 : Data signal of n  bit 31~0 - n[31:0] (Read/Write)
// (SC = Self Clear, COR = Clear on Read, TOW = Toggle on Write, COH = Clear on Handshake)
"""

T2_PROMPT = """# 任务：驱动一个 HLS 向量加法核

overlay 中有 HLS 核 `vadd_0`（寄存器见 `hw/xvadd_hw.h`，元数据见 `hw/vadd.hwh`）。核通过 m_axi 经 HP 口
直接读写 DDR（该端口**不与 CPU 缓存一致**），`pynq.allocate` 在本平台返回**可缓存**缓冲。

请写 `solution.py`：

```python
def vadd(overlay, a, b, timeout_s=1.0):
    \"\"\"a、b 为等长 int32 numpy 数组(长度 1..4096)，返回 a+b (int32 numpy 数组)\"\"\"
```

要求：
1. 结果必须正确，并可被连续多次调用（每次输入不同）。
2. 调用时该核可能残留上一个进程留下的、未被读取的完成状态；不得把它当作本次完成。
3. 若核在 `timeout_s` 内没有完成，抛 `TimeoutError`（不能卡死）。
4. 代码需同时适用于 32 位与 64 位物理地址平台。

你无法访问真实板卡；只交付 `solution.py`。
"""

_VADD_REGS = ''.join(['<REGISTERS>\n<REGISTER NAME="CTRL"><PROPERTY NAME="ADDRESS_OFFSET" VALUE="0x00"/><FIELDS>'] +
                     ['<FIELD NAME="%s"><PROPERTY NAME="BIT_OFFSET" VALUE="%d"/><PROPERTY NAME="BIT_WIDTH" VALUE="1"/></FIELD>'
                      % (n, b) for n, b in (('AP_START', 0), ('AP_DONE', 1), ('AP_IDLE', 2), ('AP_READY', 3),
                                            ('AUTO_RESTART', 7))] +
                     ['</FIELDS></REGISTER>\n'] +
                     ['<REGISTER NAME="%s"><PROPERTY NAME="ADDRESS_OFFSET" VALUE="0x%02X"/></REGISTER>\n' % (n, o)
                      for n, o in (('GIER', 4), ('IP_IER', 8), ('IP_ISR', 0xC), ('a_1', 0x10), ('a_2', 0x14),
                                   ('b_1', 0x1C), ('b_2', 0x20), ('c_1', 0x28), ('c_2', 0x2C), ('n', 0x34))] +
                     ['</REGISTERS>\n'])


def _t2_files(root, seed=2):
    rnd = random.Random(seed)
    bit = bytes(rnd.getrandbits(8) for _ in range(2048))
    hwh = make_hwh([{'fullname': 'vadd_0', 'vlnv': 'xilinx.com:hls:vadd:1.0', 'base': 0x40000000,
                     'registers': _VADD_REGS}])
    _write(os.path.join(root, 'vadd.bit'), bit)
    _write(os.path.join(root, 'vadd.hwh'), hwh)
    _write(os.path.join(root, 'xvadd_hw.h'), T2_HW_H)
    return os.path.join(root, 'vadd.bit'), _sha(bit)


T2_RUN = """
import numpy as np, time
ol = pynq.Overlay(BIT)
rng = np.random.default_rng(SEED)
for i in range(CALLS):
    a = rng.integers(-2**30, 2**30, N, dtype=np.int32); b = rng.integers(-2**30, 2**30, N, dtype=np.int32)
    t0 = time.monotonic()
    if EXPECT_TIMEOUT:
        try:
            solution.vadd(ol, a, b, timeout_s=0.2)
            result['ok'] = False; result['why'] = 'no TimeoutError'
        except TimeoutError:
            result['ok'] = time.monotonic() - t0 < 3.0; result['why'] = 'timeout raised'
        break
    c = np.asarray(solution.vadd(ol, a, b, timeout_s=1.0)).astype(np.int64)
    if not np.array_equal(c, (a.astype(np.int64) + b) .astype(np.int32)):
        result['ok'] = False; result['why'] = 'wrong result on call %d' % i; break
else:
    result['ok'] = True
"""


def t2_scenarios(tmp):
    sc = []
    for name, cfg, n, calls, to in [
        ('basic', {}, 64, 1, False),
        ('back_to_back', {}, 1000, 3, False),
        ('stale_done', {'stale_done': True, 'latency_s': 0.02}, 256, 1, False),
        ('addr_high_word_dirty', {'hi_garbage': 1}, 128, 1, False),
        ('never_done', {'never_done': True}, 16, 1, True),
        ('single_element', {}, 1, 2, False),
    ]:
        d = os.path.join(tmp, 't2_' + name)
        bit, sha = _t2_files(d)
        hw = {sha: [dict(cfg, kind='vadd', base='0x40000000')]}
        sc.append({'name': name, 'hardware': hw,
                   'code': 'BIT=%r\nN=%d\nCALLS=%d\nEXPECT_TIMEOUT=%r\nSEED=%d\n%s' % (bit, n, calls, to, len(name), T2_RUN)})
    return sc


def t2_workspace(ws):
    _t2_files(os.path.join(ws, 'hw'))


# =============================================================== T3 DMA stream
T3_PROMPT = """# 任务：通过 AXI DMA 驱动一个流处理 IP

overlay 中 `axi_dma_0`（AXI DMA 7.1，简单模式，MM2S→流 IP→S2MM）连接了一个逐字节处理的无状态流 IP。
硬件元数据见 `hw/stream.hwh`。流 IP 可能输出比输入**更少**的字节（以 TLAST 结束一个输出包）；
输入可任意切分成多个包分别处理，结果按顺序拼接即可。

请写 `solution.py`：

```python
def transform(overlay, data: bytes, timeout_s: float = 1.0) -> bytes:
    \"\"\"把 data（长度 1..65536 字节）送入流 IP，返回它输出的全部字节\"\"\"
```

要求：
1. 返回 IP **实际**输出的字节，不多不少。
2. 若硬件在 `timeout_s` 内未完成（例如 IP 不发 TLAST），抛 `TimeoutError`，不能卡死。
3. 可被连续多次调用。

你无法访问真实板卡；只交付 `solution.py`。
"""

_DMA_PARAMS = {'c_include_sg': '0', 'c_micro_dma': '0', 'c_sg_length_width': '14', 'c_include_mm2s': '1',
               'c_include_s2mm': '1', 'c_m_axi_mm2s_data_width': '32', 'c_m_axi_s2mm_data_width': '32',
               'c_include_mm2s_dre': '0', 'c_include_s2mm_dre': '0'}


def _t3_files(root, seed=3):
    rnd = random.Random(seed)
    bit = bytes(rnd.getrandbits(8) for _ in range(2048))
    hwh = make_hwh([{'fullname': 'axi_dma_0', 'vlnv': 'xilinx.com:ip:axi_dma:7.1', 'base': 0x40400000,
                     'params': _DMA_PARAMS}])
    _write(os.path.join(root, 'stream.bit'), bit)
    _write(os.path.join(root, 'stream.hwh'), hwh)
    return os.path.join(root, 'stream.bit'), _sha(bit)


T3_RUN = """
import time, random
ol = pynq.Overlay(BIT)
rnd = random.Random(SEED)
for i in range(CALLS):
    data = bytes(rnd.getrandbits(8) for _ in range(LEN))
    t0 = time.monotonic()
    if EXPECT_TIMEOUT:
        try:
            solution.transform(ol, data, timeout_s=0.2)
            result['ok'] = False; result['why'] = 'no TimeoutError'
        except TimeoutError:
            result['ok'] = time.monotonic() - t0 < 3.0; result['why'] = 'timeout raised'
        break
    out = bytes(solution.transform(ol, data, timeout_s=2.0))
    inv = bytes(x ^ 0xFF for x in data)
    ok = out == (inv[:-4] if SHORT else inv)   # 'short' IP drops the last 4 bytes of a packet
    if not ok:
        result['ok'] = False; result['why'] = 'wrong output on call %d (len %d vs %d)' % (i, len(out), len(inv)); break
else:
    result['ok'] = True
"""


def t3_scenarios(tmp):
    sc = []
    for name, cfg, length, calls, to, short in [
        ('basic', {}, 256, 1, False, False),
        ('back_to_back', {}, 1000, 3, False, False),
        ('odd_length', {}, 13, 1, False, False),
        ('short_output', {'fault': 'short'}, 64, 1, False, True),
        ('no_tlast', {'fault': 'no_tlast'}, 64, 1, True, False),
        ('larger_than_max_transfer', {}, 40000, 1, False, False),
    ]:
        d = os.path.join(tmp, 't3_' + name)
        bit, sha = _t3_files(d)
        hw = {sha: [dict(cfg, kind='axi_dma', base='0x40400000', length_width=14)]}
        sc.append({'name': name, 'hardware': hw, 'code': 'BIT=%r\nLEN=%d\nCALLS=%d\nEXPECT_TIMEOUT=%r\nSHORT=%r\nSEED=%d\n%s'
                   % (bit, length, calls, to, short, len(name), T3_RUN)})
    return sc


def t3_workspace(ws):
    _t3_files(os.path.join(ws, 'hw'))


# =============================================================== T5 AXI BRAM (hold-out)
T5_PROMPT = """# 任务：通过 AXI BRAM 控制器读写一块片上内存

`hw/` 下是一份示例设计：`bram.bit`、`bram.hwh`。设计里有一个 AXI BRAM 控制器，把 PL 里的
一块 BRAM 映射到 PS 的可访问地址窗口；它不是寄存器堆，整段地址都是内存，但没有直接的字节写口，
主机侧只能按 32 位字访问。

请写 `solution.py`，实现两个函数：

```python
def poke_block(overlay, offset: int, data: bytes) -> None:
    \"\"\"把 data 按字节写进 BRAM 从 offset 开始的位置\"\"\"

def peek_block(overlay, offset: int, length: int) -> bytes:
    \"\"\"从 offset 开始读出 length 个字节\"\"\"
```

要求：
1. 使用 overlay 中 VLNV 为 `xilinx.com:ip:axi_bram_ctrl:4.1` 的 IP；实例名、所在层级、基址与容量
   以后可能变化，都不能写死（容量见 hwh 的地址范围）。
2. 只改 `data` 覆盖到的那几个字节；区间之外的字节必须保持原值（同一个 32 位字里的邻居字节也算）。
3. 越界（`offset` 为负、或 `offset + len(data)` / `offset + length` 超过 BRAM 容量）时抛 `ValueError`，
   不要写到窗口外。
4. `peek_block` 返回 `bytes`，长度必须等于 `length`。
5. 可以被连续多次调用，写入后立即可读到（这段内存是 MMIO，不是可缓存缓冲）。

你无法访问真实板卡；只交付 `solution.py`。不要修改 `hw/`。
"""

T5_HEADER = """/* AXI BRAM Controller (Xilinx PG078) - no register map.
 *
 * The whole address window reported by the .hwh is BRAM:
 *   base address  = C_BASEADDR in the design metadata
 *   capacity      = C_HIGHADDR - C_BASEADDR + 1
 *
 * Access is 32-bit AXI4-Lite: only word-aligned 32-bit reads/writes exist.
 * To change a single byte, read the word that contains it, replace that byte, write it back.
 */
"""


def _t5_files(root, *, fullname='bram_0', base=0x40000000, size=0x4000, seed=5):
    rnd = random.Random(seed)
    bit = bytes(rnd.getrandbits(8) for _ in range(2048))
    hwh = make_hwh([{'fullname': fullname, 'vlnv': 'xilinx.com:ip:axi_bram_ctrl:4.1',
                     'base': base, 'size': size,
                     'params': {'c_s_axi_protocol': 'AXI4LITE', 'c_mem_depth': str(size // 4)}}])
    _write(os.path.join(root, 'bram.bit'), bit)
    _write(os.path.join(root, 'bram.hwh'), hwh)
    _write(os.path.join(root, 'bram_window.h'), T5_HEADER)
    return os.path.join(root, 'bram.bit'), _sha(bit)


T5_RW = """
import hashlib
ol = pynq.Overlay(BIT)
solution.poke_block(ol, OFF, DATA)
got = bytes(solution.peek_block(ol, 0, WINDOW))
h = hashlib.sha256(got).hexdigest()
result['ok'] = len(got) == WINDOW and h == EXPECT_SHA
if not result['ok']:
    result['why'] = 'window mismatch (len=%d, sha=%s)' % (len(got), h[:12])
"""

T5_BOUNDS = """
import hashlib
ol = pynq.Overlay(BIT)
try:
    solution.poke_block(ol, OFF, DATA)
    result['ok'] = False; result['why'] = 'poke_block accepted an out-of-range offset'
except ValueError:
    got = bytes(solution.peek_block(ol, 0, WINDOW))
    result['ok'] = hashlib.sha256(got).hexdigest() == PREFILL_SHA
    result['why'] = '' if result['ok'] else 'BRAM changed after a rejected write'
"""

T5_BOUNDS_READ = """
ol = pynq.Overlay(BIT)
try:
    solution.peek_block(ol, OFF, LEN)
    result['ok'] = False; result['why'] = 'peek_block accepted an out-of-range request'
except ValueError:
    result['ok'] = True
"""

T5_SEQUENCE = """
import hashlib
ol = pynq.Overlay(BIT)
for i, (off, blob, expect_sha) in enumerate(STEPS):
    solution.poke_block(ol, off, blob)
    got = bytes(solution.peek_block(ol, 0, WINDOW))
    if hashlib.sha256(got).hexdigest() != expect_sha:
        result['ok'] = False
        result['why'] = 'step %d mismatch' % i
        break
else:
    result['ok'] = True
"""


def _t5_pattern(n, seed=7):
    rnd = random.Random(seed)
    return bytes(rnd.getrandbits(8) for _ in range(n))


def t5_scenarios(tmp):
    sc = []
    # name, file kwargs, hardware cfg, driver body, metadata
    cases = [
        ('aligned_word', {}, T5_RW, {'OFF': 0, 'DATA': bytes(range(16)), 'WINDOW': 16}),
        ('unaligned_rmw', {}, T5_RW, {'OFF': 5, 'DATA': b'\xde\xad\xbe', 'WINDOW': 16}),
        ('odd_length', {}, T5_RW, {'OFF': 3, 'DATA': bytes(range(13)), 'WINDOW': 20}),
        ('hierarchical_32k', {'fullname': 'io/bram_0', 'base': 0x42000000, 'size': 0x8000}, T5_RW,
         {'OFF': 0x1000, 'DATA': bytes(range(16)), 'WINDOW': 0x1010}),
        ('past_the_end', {'size': 0x1000}, T5_BOUNDS, {'OFF': 0xFFE, 'DATA': bytes(range(8)), 'WINDOW': 8}),
        ('read_past_the_end', {'size': 0x1000}, T5_BOUNDS_READ, {'OFF': 0xFFC, 'LEN': 8}),
        ('sequence', {}, T5_SEQUENCE, {}),
    ]
    steps_def = ((0, b'\x11\x22\x33'), (2, b'\xaa'), (4, b'\x01\x02\x03\x04\x05'), (0x1FFF, b'\xff'))

    for name, kw, body, meta in cases:
        d = os.path.join(tmp, 't5_' + name)
        size = int(kw.get('size', 0x4000))
        prefill = _t5_pattern(size, seed=len(name) + size)
        bit, sha = _t5_files(d, **kw)
        hw = {sha: [dict(kind='axi_bram', size=size, prefill=prefill.hex(),
                         base='0x%08X' % int(kw.get('base', 0x40000000)))]}
        meta = dict(meta)
        if name == 'sequence':
            cur, steps = bytearray(prefill), []
            for off, blob in steps_def:
                cur[off:off + len(blob)] = blob
                steps.append((off, blob, _sha(bytes(cur[:0x2000]))))
            meta['STEPS'] = steps
            meta['WINDOW'] = 0x2000
        else:
            expect = bytearray(prefill)
            if 'OFF' in meta and 'DATA' in meta:
                off, blob = meta['OFF'], meta['DATA']
                expect[off:off + len(blob)] = blob
            win = int(meta.get('WINDOW', 16))
            meta['EXPECT_SHA'] = _sha(bytes(expect[:win]))
            meta['PREFILL_SHA'] = _sha(bytes(prefill[:win]))
        head = '\n'.join('%s = %r' % (k, v) for k, v in meta.items())
        sc.append({'name': name, 'hardware': hw, 'code': 'BIT=%r\n%s\n%s' % (bit, head, body)})
    return sc


def t5_workspace(ws):
    _t5_files(os.path.join(ws, 'hw'))


# =============================================================== T4 diagnosis (text, rubric)
T4_QUESTIONS = """# 现象诊断（每题回答：最可能根因 + 下一步用什么动作确认）

Q1. AXI DMA 回环测试抛 `RuntimeError: DMA Internal Error (transfer length 0?)`；读到 S2MM DMASR=0x00004011，
    请求长度非 0。
Q2. Notebook 卡在 `dma.recvchannel.wait()` 不返回，没有任何报错；MM2S 通道 DMASR 显示 Idle。
Q3. 一个 PL 通过 m_axi 写 DDR 结果的加速器，第一次调用结果正确，之后每次返回的都是第一次的结果。
Q4. 把新生成的 `design.bit` 改名为 `design_v2.bit` 放到旧目录（目录里有旧的 `design_v2.hwh`），加载成功，
    但所有寄存器读回 0 或与预期无关。
Q5. hwh 中 FCLK0 设为 100 MHz，但 `pynq.ps.Clocks.fclk0_mhz` 读回 150.0。
Q6. HLS 核实际已经完成（输出数据正确），但轮询 ap_done 一直等不到；轮询前代码为了调试打印过一次 CTRL 寄存器。
Q7. DMA 报 Decode Error，打印写入 S2MM_DA 的地址是 0x7F8A3C2000 左右的值。
Q8. 同一份主机代码在 Zynq-7000 上正确，移植到 ZynqMP 后 HLS 核把结果写到了随机位置。
"""

T4_PROMPT = """# 任务：PYNQ 故障诊断

阅读 `QUESTIONS.md`，把每题答案写入 `answers.md`，格式为 `## Q1` ... `## Q8`，每题 2–5 句。
不需要写代码，也无法访问真实板卡。
"""

T4_RUBRIC = {
    'Q1': [r'(?i)(IntErr|internal|内部错误|bit ?4)', r'(?i)(length|长度|TLAST|小于|short|small|不足|更长|longer)'],
    'Q2': [r'(?i)TLAST', r'(?i)(timeout|超时|无界|unbounded|spin|自旋|轮询|deadline)'],
    'Q3': [r'(?i)(invalidate|cache|缓存|coheren|一致)'],
    'Q4': [r'(?i)hwh', r'(?i)(stale|旧|mismatch|不匹配|不配套|sibling|同名|对应)'],
    'Q5': [r'(?i)(reference|参考时钟|crystal|晶振|33\.3|50 ?MHz|PS_CLK|参考)'],
    'Q6': [r'(?i)(clear.?on.?read|COR|读清|读后清|read.{0,10}clear)'],
    'Q7': [r'(?i)(physical|物理地址|physical_address|device_address)', r'(?i)(virtual|虚拟)'],
    'Q8': [r'(?i)(high|高 ?32|高位|_hi|MSB|0x14|a_2|64.?(bit|位))'],
}


def t4_workspace(ws):
    _write(os.path.join(ws, 'QUESTIONS.md'), T4_QUESTIONS)


TASKS = {
    't1_overlay': {'prompt': T1_PROMPT, 'workspace': t1_workspace, 'scenarios': t1_scenarios, 'artifact': 'solution.py'},
    't2_hls': {'prompt': T2_PROMPT, 'workspace': t2_workspace, 'scenarios': t2_scenarios, 'artifact': 'solution.py'},
    't3_dma': {'prompt': T3_PROMPT, 'workspace': t3_workspace, 'scenarios': t3_scenarios, 'artifact': 'solution.py'},
    't4_diagnose': {'prompt': T4_PROMPT, 'workspace': t4_workspace, 'rubric': T4_RUBRIC, 'artifact': 'answers.md'},
    't5_bram': {'prompt': T5_PROMPT, 'workspace': t5_workspace, 'scenarios': t5_scenarios, 'artifact': 'solution.py'},
}

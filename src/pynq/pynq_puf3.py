"""pynq_puf3.py —— pynq_puf3 overlay 的 PS 侧驱动：三模式 Y01 服务 + PUF v1 帧。

在 pynq_transport.PynqUartTransport 之上只增加两件事（发布版 pynq_transport.py 不改）：
  * 控制窗口身份 "PQF3"（0x33465150）；发布版 "PYNQ" 与 PUF 自检版 "PFU1" 都会被拒绝；
  * Y01P 请求 / Y01K 响应（固件 src/firmware/pynq_svc_puf/puf_svc.c）。

Y01P 16B: b'Y01P' | u32 version | u32 cmd | u32 seq
Y01K 112B: magic | u16 version | u16 flags | u32 cmd | u32 seq | u32 result | u32 STATUS
           | u32 DNA_LO | u32 DNA_HI | u64 op mcycle | REF16 | MASK16 | RAW16 | DITHER16 | 8B 0

证据边界：REF/MASK/RAW/DITHER/DNA 是 PUF v1 设计上可读的诊断量，不能据此宣称保密；
key 本身不可读。HWKEY 打开后 HW 模式用 PUF 派生密钥，结果无法与官方 KAT 比对，
只能用"调用方 key 被拒绝 + 同 key 往返 + 重建后一致"来证明。
"""
from __future__ import annotations

import struct

if __package__:
    from .ascon_host_api import BackendProtocolError, BackendTimeoutError
    from .mailbox_protocol import VERSION
    from .pynq_transport import (BridgeRegs, CTL_ID, CTL_VERSION, FrameDecoder, MB_ID, MB_ID_VALUE,
                                 NotConfiguredError, PynqUartTransport, RSP_HEADER_BYTES,
                                 SWC_FRAME_BYTES, _need_finite, parse_service_frame)
else:
    from ascon_host_api import BackendProtocolError, BackendTimeoutError
    from mailbox_protocol import VERSION
    from pynq_transport import (BridgeRegs, CTL_ID, CTL_VERSION, FrameDecoder, MB_ID, MB_ID_VALUE,
                                NotConfiguredError, PynqUartTransport, RSP_HEADER_BYTES,
                                SWC_FRAME_BYTES, _need_finite, parse_service_frame)

CTL_ID_PQF3 = 0x33465150
FIRMWARE_ID = 'pynq-svc-puf3'
PUF_RSP_BYTES = 112

CMD = {'status': 0, 'enroll': 1, 'reconstruct': 2, 'hwkey_on': 3, 'hwkey_off': 4}
RESULT = {0: 'OK', 1: 'TIMEOUT', 2: 'NOT_ACCEPTED', 3: 'BAD_CMD', 4: 'BAD_VERSION',
          5: 'NO_PUF_KEY', 6: 'BUSY_STUCK'}
STATUS_BITS = ('busy', 'key_ready', 'enrolled', 'mismatch', 'fallback', 'done', 'key_hw_sel', 'hwkey_on')


class Puf3BridgeRegs(BridgeRegs):
    def check_identity(self):
        ident = self.ctl.read(CTL_ID)
        if ident != CTL_ID_PQF3:
            raise NotConfiguredError('NOT_CONFIGURED: control identity 0x%08X is not PQF3' % ident)
        ident = self.mb.read(MB_ID)
        if ident != MB_ID_VALUE:
            raise NotConfiguredError('NOT_CONFIGURED: mailbox window identity mismatch (0x%08X)' % ident)
        ver = self.ctl.read(CTL_VERSION)
        if ver != 1:
            raise NotConfiguredError('NOT_CONFIGURED: control block version %r' % ver)
        return True


class Puf3FrameDecoder(FrameDecoder):
    """Y01S / Y01R / Y01K；其余字节当文本日志。"""

    MAGICS = ((b'Y01S', 'S'), (b'Y01R', 'R'), (b'Y01K', 'K'))

    def _find_magic(self):
        best, kind = -1, None
        for magic, tag in self.MAGICS:
            idx = self.buf.find(magic)
            if idx >= 0 and (best < 0 or idx < best):
                best, kind = idx, tag
        return best, kind

    def pop_frame(self):
        """返回 ('S'|'R'|'K', bytes) 或 None；与基类相同的分帧规则，多一种定长 K 帧。"""
        while True:
            idx, kind = self._find_magic()
            if idx < 0:
                if len(self.buf) > 3:
                    self.log.extend(self.buf[:-3])
                    del self.buf[:-3]
                return None
            if idx:
                self.log.extend(self.buf[:idx])
                del self.buf[:idx]
            if kind in ('S', 'K'):
                size = SWC_FRAME_BYTES if kind == 'S' else PUF_RSP_BYTES
                if len(self.buf) < size:
                    return None
                frame = bytes(self.buf[:size])
                del self.buf[:size]
                return kind, frame
            if len(self.buf) < RSP_HEADER_BYTES:
                return None
            size = int.from_bytes(self.buf[36:40], 'little')
            if size > 4096:
                self.log.extend(self.buf[:1])
                del self.buf[:1]
                continue
            total = RSP_HEADER_BYTES + size
            if len(self.buf) < total:
                return None
            frame = bytes(self.buf[:total])
            del self.buf[:total]
            return 'R', frame


def puf_request(cmd, seq):
    # Any u32 is encodable on purpose: the firmware must reject unknown commands (BAD_CMD).
    if isinstance(cmd, bool) or not isinstance(cmd, int) or not 0 <= cmd < 2 ** 32:
        raise ValueError('invalid PUF command')
    return b'Y01P' + struct.pack('<III', VERSION, cmd, seq)


def parse_puf_frame(frame):
    if len(frame) != PUF_RSP_BYTES or frame[:4] != b'Y01K':
        raise BackendProtocolError('malformed PUF frame')
    version, flags, cmd, seq, result, status, dna_lo, dna_hi, cycles = struct.unpack_from('<HHIIIIIIQ', frame, 4)
    if version != VERSION:
        raise BackendProtocolError('PUF frame version mismatch')
    if frame[104:112] != bytes(8):
        raise BackendProtocolError('PUF frame reserved bytes not zero')
    bits = {name: bool(status >> i & 1) for i, name in enumerate(STATUS_BITS)}
    return {
        'cmd': cmd, 'seq': seq, 'result': RESULT.get(result, 'UNKNOWN_%d' % result),
        'result_code': result, 'simulated': bool(flags & 0x2), 'status_raw': status,
        'status': bits, 'quality': (status >> 8) & 0xFF,
        'dna': '%07x%08x' % (dna_hi & 0x1FFFFFF, dna_lo),
        'op_mcycle': cycles,
        'ref': frame[40:56].hex(), 'mask': frame[56:72].hex(),
        'raw': frame[72:88].hex(), 'dither': frame[88:104].hex(),
    }


class PynqPuf3Transport(PynqUartTransport):
    """PynqUartTransport + Y01K 分帧 + puf_command()。"""

    def __init__(self, regs, *, expected_firmware_id=FIRMWARE_ID, **kwargs):
        if not isinstance(regs, Puf3BridgeRegs):
            raise NotConfiguredError('NOT_CONFIGURED: Puf3BridgeRegs instance required')
        self._puf_frame = None
        self._puf_seq = 0
        super().__init__(regs, expected_firmware_id=expected_firmware_id, **kwargs)

    # The base class assigns `self.decoder = FrameDecoder()` in __init__ and on every handshake;
    # route every assignment to a decoder that also understands Y01K.
    @property
    def decoder(self):
        return self._decoder

    @decoder.setter
    def decoder(self, value):
        self._decoder = value if isinstance(value, Puf3FrameDecoder) else Puf3FrameDecoder()

    def _pump(self, deadline, want='R'):
        while True:
            self._check(deadline)
            chunk = self.regs.drain()
            if chunk:
                self.decoder.feed(chunk)
            while True:
                item = self.decoder.pop_frame()
                if item is None:
                    break
                kind, frame = item
                if kind == 'S':
                    self.last_service = parse_service_frame(frame)
                    if want == 'S':
                        return frame
                    continue
                if kind == 'K':
                    if want == 'K':
                        return frame
                    raise BackendProtocolError('unexpected PUF frame')
                if want == 'R':
                    return frame
                raise BackendProtocolError('unexpected response frame')
            if self.regs.rx_overflow():
                raise BackendProtocolError('mailbox RX overflow: PS did not drain in time')
            if self.clock() >= deadline:
                raise BackendTimeoutError('pynq transport deadline expired')
            self.sleep(min(self.poll_interval, max(0.0, deadline - self.clock())))

    def puf_command(self, name, deadline):
        """执行一条 PUF 命令并返回解析后的 Y01K；不能与未完成的 AEAD 请求交错。"""
        _need_finite(deadline)
        if self.capabilities is None:
            raise NotConfiguredError('NOT_CONFIGURED: hello() first')
        if self._pending is not None or self._response is not None:
            raise BackendProtocolError('mailbox slot occupied by an AEAD request')
        cmd = CMD[name] if isinstance(name, str) else int(name)
        self._puf_seq = (self._puf_seq + 1) & 0xFFFFFFFF or 1
        seq = self._puf_seq
        self._push(puf_request(cmd, seq), deadline)
        frame = parse_puf_frame(self._pump(deadline, want='K'))
        if (frame['cmd'], frame['seq']) != (cmd, seq):
            raise BackendProtocolError('stale or mismatched PUF response')
        if frame['simulated'] != bool(self.capabilities.simulated):
            raise BackendProtocolError('PUF frame evidence kind mismatch')
        return frame


def from_overlay(overlay, control_name='pynq_ctl_0', mailbox_name='pynq_mbox_0', **kwargs):
    if overlay is None or not callable(getattr(overlay, 'is_loaded', None)) or not overlay.is_loaded():
        raise NotConfiguredError('NOT_CONFIGURED: caller must provide a loaded overlay')
    ip_dict = getattr(overlay, 'ip_dict', {})
    for name in (control_name, mailbox_name):
        if name not in ip_dict:
            raise NotConfiguredError('NOT_CONFIGURED: %r missing from overlay ip_dict' % name)
    return PynqPuf3Transport(
        Puf3BridgeRegs(getattr(overlay, control_name).mmio, getattr(overlay, mailbox_name).mmio), **kwargs)


__all__ = ['CTL_ID_PQF3', 'FIRMWARE_ID', 'CMD', 'RESULT', 'Puf3BridgeRegs', 'Puf3FrameDecoder',
           'PynqPuf3Transport', 'parse_puf_frame', 'puf_request', 'from_overlay',
           'RSP_HEADER_BYTES', 'SWC_FRAME_BYTES']

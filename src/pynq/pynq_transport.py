"""pynq_transport.py —— Y01 邮箱的 PYNQ 物理 Transport（PS <-> PL RV32）

把 PYNQ 侧的两个 AXI-Lite 窗口当作设备：

    CONTROL  (pynq_ctl.v)   : SOC_RESET / BUTTON / STAT(LED, RST)
    MAILBOX  (pynq_mbox.v)  : TXDATA/RXDATA/TXSTAT/RXSTAT/CNT

数据通路复用 RV32 已有的 UART MMIO 外设：PL 里的 pynq_mbox 实现"串口的另一端"，
PS 压字节进 TX FIFO，SoC 的 pynq_svc 固件按 Y01 帧处理并回帧，PS 从 RX FIFO 读回。

设计约束（必须保持）：
  * 只做真实硬件路径：默认构造失败即 NotConfiguredError，绝不回落到模拟；
    握手帧里 SIMULATED 置位时，本类如实把 simulated=True 报给上层。
  * 所有方法遵守调用方给的绝对 monotonic deadline（在循环内检查并抛出
    BackendTimeoutError，而不是只在外层查一次）。
  * cycles 只来自固件回帧的 mcycle 差值；本模块不产生任何计时数值。
  * 返回给上层的帧是原始字节，身份校验/ACK 由 MailboxBackend 负责。

寄存器位（与 src/rtl/pynq/pynq_ctl.v、pynq_mbox.v 一致）：
  MB 0x08 TXSTAT: [15:0]=深度 [16]=满 [17]=空
  MB 0x0C RXSTAT: [15:0]=深度 [16]=满 [17]=空 [18]=溢出(粘滞)
"""
from __future__ import annotations

import math
import time

if __package__:
    from .ascon_host_api import (AsconError, BackendProtocolError, BackendTimeoutError)
    from .mailbox_backend import Capabilities, Transport
    from .mailbox_protocol import VERSION, Mode, SIMULATED
else:
    from ascon_host_api import AsconError, BackendProtocolError, BackendTimeoutError
    from mailbox_backend import Capabilities, Transport
    from mailbox_protocol import VERSION, Mode, SIMULATED


class NotConfiguredError(AsconError):
    status = 'NOT_CONFIGURED'


# ---- pynq_ctl.v -----------------------------------------------------------
CTL_CTRL = 0x00        # W: [0]=SOC_RESET(1=保持) [3:2]=BUTTON
CTL_STAT = 0x04        # R: [0]=SOC_RST_N [3:2]=LED
CTL_ID = 0x08          # R: 0x514E5950
CTL_VERSION = 0x0C     # R: 1
CTL_ID_VALUE = 0x514E5950

# ---- pynq_mbox.v ----------------------------------------------------------
MB_TXDATA = 0x00       # W: [7:0]
MB_RXDATA = 0x04       # R: [7:0]
MB_TXSTAT = 0x08       # R: [15:0] 深度, [16] 满, [17] 空
MB_RXSTAT = 0x0C       # R: [15:0] 深度, [16] 满, [17] 空, [18] 溢出
MB_RXCLR = 0x10        # W: [0]
MB_TXFLUSH = 0x14      # W: [0]
MB_CNT = 0x18          # R: [15:0] PS 已压入, [31:16] 已收到
MB_ID = 0x1C           # R: 0x4D424F58
MB_ID_VALUE = 0x4D424F58

FULL_BIT = 1 << 16
EMPTY_BIT = 1 << 17
OVF_BIT = 1 << 18

SWC_FRAME_BYTES = 64
EPOCH_FRAME_BYTES = 20
RSP_HEADER_BYTES = 48


def _need_finite(deadline):
    if isinstance(deadline, bool) or not isinstance(deadline, (int, float)) or not math.isfinite(deadline):
        raise ValueError('absolute deadline must be finite')
    return deadline


class BridgeRegs:
    """两个 MMIO 窗口的薄封装；read/write 注入，便于用寄存器模型测试。"""

    def __init__(self, ctl, mb, *, tx_depth=64, rx_depth=256):
        for obj in (ctl, mb):
            if not hasattr(obj, 'read') or not hasattr(obj, 'write'):
                raise ValueError('MMIO objects must expose read/write')
        self.ctl, self.mb = ctl, mb
        self.tx_depth, self.rx_depth = tx_depth, rx_depth

    # -- 基础 --
    def check_identity(self):
        ident = self.ctl.read(CTL_ID)
        if ident != CTL_ID_VALUE:
            raise NotConfiguredError(
                'NOT_CONFIGURED: control window identity mismatch (0x%08X)' % ident)
        ident = self.mb.read(MB_ID)
        if ident != MB_ID_VALUE:
            raise NotConfiguredError(
                'NOT_CONFIGURED: mailbox window identity mismatch (0x%08X)' % ident)
        ver = self.ctl.read(CTL_VERSION)
        if ver != 1:
            raise NotConfiguredError('NOT_CONFIGURED: control block version %r' % ver)
        return True

    def hold_reset(self):
        self.ctl.write(CTL_CTRL, 0x1)

    def release_reset(self):
        self.ctl.write(CTL_CTRL, 0x0)

    def status(self):
        return self.ctl.read(CTL_STAT)

    def flush(self):
        self.mb.write(MB_TXFLUSH, 0x1)
        self.mb.write(MB_RXCLR, 0x1)

    def tx_ready(self):
        return not (self.mb.read(MB_TXSTAT) & FULL_BIT)

    def rx_level(self):
        return self.mb.read(MB_RXSTAT) & 0xFFFF

    def rx_overflow(self):
        return bool(self.mb.read(MB_RXSTAT) & OVF_BIT)

    def bytes_moved(self):
        v = self.mb.read(MB_CNT)
        return v & 0xFFFF, (v >> 16) & 0xFFFF

    def push(self, data):
        for byte in data:
            self.mb.write(MB_TXDATA, byte)

    def drain(self, limit=4096):
        out = bytearray()
        while limit and self.rx_level():
            out.append(self.mb.read(MB_RXDATA) & 0xFF)
            limit -= 1
        return bytes(out)


class FrameDecoder:
    """从字节流里分帧：Y01S(64B) / Y01R(48B+payload)；其余字节当文本日志。"""

    MAGIC_S = b'Y01S'
    MAGIC_R = b'Y01R'

    def __init__(self):
        self.buf = bytearray()
        self.log = bytearray()

    def feed(self, data):
        self.buf.extend(data)

    def _find_magic(self):
        best = -1
        kind = None
        for magic, tag in ((self.MAGIC_S, 'S'), (self.MAGIC_R, 'R')):
            idx = self.buf.find(magic)
            if idx >= 0 and (best < 0 or idx < best):
                best, kind = idx, tag
        return best, kind

    def pop_frame(self):
        """返回 ('S', bytes) / ('R', bytes) / None。非帧字节累积到 self.log。"""
        while True:
            idx, kind = self._find_magic()
            if idx < 0:
                # 保留最多 3 字节，防止把半个魔数当文本丢掉
                if len(self.buf) > 3:
                    self.log.extend(self.buf[:-3])
                    del self.buf[:-3]
                return None
            if idx:
                self.log.extend(self.buf[:idx])
                del self.buf[:idx]
            if kind == 'S':
                if len(self.buf) < SWC_FRAME_BYTES:
                    return None
                frame = bytes(self.buf[:SWC_FRAME_BYTES])
                del self.buf[:SWC_FRAME_BYTES]
                return 'S', frame
            if len(self.buf) < RSP_HEADER_BYTES:
                return None
            size = int.from_bytes(self.buf[36:40], 'little')
            if size > 4096:
                # 非法长度：丢一个字节继续找下一个魔数，避免死等
                self.log.extend(self.buf[:1])
                del self.buf[:1]
                continue
            total = RSP_HEADER_BYTES + size
            if len(self.buf) < total:
                return None
            frame = bytes(self.buf[:total])
            del self.buf[:total]
            return 'R', frame


def parse_service_frame(frame):
    if len(frame) != SWC_FRAME_BYTES or frame[:4] != b'Y01S':
        raise BackendProtocolError('malformed service frame')
    version = int.from_bytes(frame[4:6], 'little')
    flags = int.from_bytes(frame[6:8], 'little')
    if version != VERSION:
        raise BackendProtocolError('service frame version mismatch')
    modes = int.from_bytes(frame[16:20], 'little')
    return {
        'version': version,
        'simulated': bool(flags & 0x1),
        'selftest_pass': bool(flags & 0x2),
        'epoch_set': bool(flags & 0x4),
        'epoch': int.from_bytes(frame[8:16], 'little'),
        'modes': tuple(m for m in Mode if modes & (1 << (m - 1))),
        'max_message_bytes': int.from_bytes(frame[20:24], 'little'),
        'max_ad_bytes': int.from_bytes(frame[24:28], 'little'),
        'selftest_mask': int.from_bytes(frame[28:32], 'little'),
        'boot_mcycle': int.from_bytes(frame[32:40], 'little'),
        'boot_id': int.from_bytes(frame[40:48], 'little'),
        'firmware_id': frame[48:64].split(b'\x00', 1)[0].decode('ascii', 'replace'),
    }


def epoch_frame(epoch):
    if not isinstance(epoch, int) or not 1 <= epoch < 2 ** 64:
        raise ValueError('epoch must be a nonzero u64')
    return b'Y01E' + VERSION.to_bytes(4, 'little') + (0).to_bytes(4, 'little') + epoch.to_bytes(8, 'little')


class PynqUartTransport(Transport):
    """真实硬件 Transport（PYNQ MMIO -> pynq_mbox -> RV32 pynq_svc）。

    调用方先 `pynq.Overlay('xxx.bit')`，再用 overlay 的两个 IP 构造 regs。
    没有 overlay / 身份寄存器不对时一律 NotConfiguredError。
    """

    def __init__(self, regs, *, expected_firmware_id=None, clock=time.monotonic,
                 sleep=time.sleep, poll_interval=0.0005, max_frame_bytes=4096):
        if not isinstance(regs, BridgeRegs):
            raise NotConfiguredError('NOT_CONFIGURED: BridgeRegs instance required')
        self.regs = regs
        self.clock = clock
        self.sleep = sleep
        self.poll_interval = poll_interval
        self.expected_firmware_id = expected_firmware_id
        self.max_frame_bytes = max_frame_bytes
        self.decoder = FrameDecoder()
        self.capabilities = None
        self._pending = None        # 已提交但未取走的请求身份
        self._response = None       # 稳定的完成响应
        self._simulated = None
        self.last_service = None    # 最近一次 Y01S（证据用）

    # ---------------- 内部 ----------------
    def _check(self, deadline):
        if self.clock() >= deadline:
            raise BackendTimeoutError('pynq transport deadline expired')

    def _pump(self, deadline, want='R'):
        """读空 RX FIFO 并分帧；等到 want 类型的帧再返回（否则 None -> 循环）。"""
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
                if want == 'R':
                    return frame
                raise BackendProtocolError('unexpected response frame before handshake')
            if self.regs.rx_overflow():
                raise BackendProtocolError('mailbox RX overflow: PS did not drain in time')
            if self.clock() >= deadline:
                raise BackendTimeoutError('pynq transport deadline expired')
            self.sleep(min(self.poll_interval, max(0.0, deadline - self.clock())))

    def _push(self, data, deadline):
        """按 TX FIFO 剩余空间批量压入，避免每个字节读一次状态寄存器。"""
        i = 0
        n = len(data)
        while i < n:
            st = self.regs.mb.read(MB_TXSTAT)
            if st & FULL_BIT:
                self._check(deadline)
                self.sleep(min(self.poll_interval, max(0.0, deadline - self.clock())))
                continue
            space = self.regs.tx_depth - (st & 0xFFFF)
            if space <= 0:
                space = 1
            for byte in data[i:i + space]:
                self.regs.mb.write(MB_TXDATA, byte)
            i += space
            self._check(deadline)

    def _handshake(self, deadline, epoch):
        self.decoder = FrameDecoder()
        self.regs.flush()
        self.regs.release_reset()
        # Wait until boot selftest finishes: CPU RX FIFO is only 16 bytes.
        self._pump(deadline, want='S')
        self._push(epoch_frame(epoch), deadline)
        # 复位后固件会先发一帧 epoch=0 的开机服务帧（可能还有文本 banner），
        # 必须等到"已采用本 epoch"的那一帧才算握手完成。
        svc = None
        while True:
            self._pump(deadline, want='S')
            svc = self.last_service
            if svc and svc['epoch_set'] and svc['epoch'] == epoch:
                break
        if self.expected_firmware_id and svc['firmware_id'] != self.expected_firmware_id:
            raise BackendProtocolError('firmware identity differs from release manifest')
        if not svc['selftest_pass'] or svc['selftest_mask'] != 7:
            raise BackendProtocolError('firmware boot selftest failed')
        if not svc['modes']:
            raise BackendProtocolError('firmware advertised no modes')
        self._simulated = svc['simulated']
        self.capabilities = Capabilities(
            version=svc['version'],
            epoch=svc['epoch'],
            max_message_bytes=svc['max_message_bytes'],
            max_ad_bytes=svc['max_ad_bytes'],
            modes=svc['modes'],
            simulated=svc['simulated'],
            firmware_id=svc['firmware_id'],
        )
        self.capabilities.validate()
        return self.capabilities

    # ---------------- Transport 接口 ----------------
    def hello(self, deadline):
        _need_finite(deadline)
        self._check(deadline)
        self.regs.check_identity()
        self.regs.hold_reset()
        self._pending = None
        self._response = None
        return self._handshake(deadline, 1)

    def submit(self, packet, deadline):
        _need_finite(deadline)
        if not isinstance(packet, bytes):
            raise TypeError('mailbox packet must be immutable bytes')
        if self.capabilities is None:
            raise NotConfiguredError('NOT_CONFIGURED: hello() first')
        if self._pending is not None or self._response is not None:
            raise BackendProtocolError('mailbox slot already occupied')
        self._check(deadline)
        self._push(packet, deadline)
        self._pending = (int.from_bytes(packet[8:16], 'little'),
                         int.from_bytes(packet[16:24], 'little'))

    def poll(self, deadline):
        _need_finite(deadline)
        self._check(deadline)
        if self._response is not None:
            return self._response
        if self._pending is None:
            raise BackendProtocolError('poll without a submitted request')
        frame = self._pump(deadline, want='R')
        # 身份必须匹配，否则隔离通道（返回给 MailboxBackend 之前就拒绝）
        epoch = int.from_bytes(frame[8:16], 'little')
        rid = int.from_bytes(frame[16:24], 'little')
        if (epoch, rid) != self._pending:
            raise BackendProtocolError('stale or mismatched hardware response identity')
        self._response = frame
        self._pending = None
        return frame

    def ack(self, epoch, request_id, deadline):
        _need_finite(deadline)
        self._check(deadline)
        if self._response is None:
            raise BackendProtocolError('ACK without a completed response')
        got = (int.from_bytes(self._response[8:16], 'little'),
               int.from_bytes(self._response[16:24], 'little'))
        if got != (epoch, request_id):
            raise BackendProtocolError('ACK identity mismatch')
        self._response = None
        self._pending = None

    def reset(self, deadline):
        _need_finite(deadline)
        self._check(deadline)
        old = self.capabilities.epoch if self.capabilities else 0
        self.regs.hold_reset()
        self._pending = None
        self._response = None
        # 复位释放后重新握手，epoch 由 PS 决定并递增，保证旧响应不再被接受
        return self._handshake(deadline, old + 1 if old else 1)

    # ---------------- 证据 ----------------
    def status_snapshot(self):
        st = self.regs.status()
        return {
            'soc_rst_n': bool(st & 0x1),
            'led': (st >> 2) & 0x3,
            'tx_bytes': self.regs.bytes_moved()[0],
            'rx_bytes': self.regs.bytes_moved()[1],
            'service': self.last_service,
            'log': bytes(self.decoder.log).decode('ascii', 'replace'),
        }


def from_overlay(overlay, control_name, mailbox_name, **kwargs):
    """从已加载的 pynq.Overlay 取两个 MMIO 窗口（名字来自 .hwh / ip_dict）。"""
    if overlay is None or not callable(getattr(overlay, 'is_loaded', None)) or not overlay.is_loaded():
        raise NotConfiguredError('NOT_CONFIGURED: caller must provide a loaded overlay')
    ip_dict = getattr(overlay, 'ip_dict', {})
    for name in (control_name, mailbox_name):
        if name not in ip_dict:
            raise NotConfiguredError('NOT_CONFIGURED: %r missing from overlay ip_dict' % name)
    return PynqUartTransport(
        BridgeRegs(getattr(overlay, control_name).mmio, getattr(overlay, mailbox_name).mmio),
        **kwargs)

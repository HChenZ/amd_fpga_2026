"""test_pynq_transport.py —— PynqUartTransport 的寄存器级模型测试（无硬件）

测的是**驱动逻辑**：AXI-Lite 位序、TX/RX FIFO 反压、Y01 分帧、文本噪音、
deadline、epoch/ACK 语义、官方 KAT 字节是否原样穿过链路。
被替换成模型的只有两处：
  (1) PL 桥寄存器组（按 src/rtl/pynq/pynq_ctl.v / pynq_mbox.v 的位表实现）
  (2) RV32 固件（用 locked Python reference 演 pynq_svc 的帧处理）

模型的服务帧把 SIMULATED 置 1，所以结果会被上层标成模拟证据；
本测试**不产生任何硬件测量数据**，也不能代替上板验证
（串口时序、真实 FIFO、PS MMIO 延迟、真 SoC 上的 mcycle 都不在这里）。

运行：python src/pynq/test_pynq_transport.py
"""
import sys
import time

if __package__:
    from .ascon_host_api import (AuthenticationError, BackendProtocolError,
                                 BackendTimeoutError, InvalidLengthError, SimulatedBackend)
    from .mailbox_backend import MailboxBackend
    from .mailbox_protocol import Mode, Operation, Response, Status, VERSION
    from .pynq_transport import (BridgeRegs, FrameDecoder, NotConfiguredError,
                                 PynqUartTransport, parse_service_frame)
else:
    from ascon_host_api import (AuthenticationError, BackendProtocolError,
                                BackendTimeoutError, InvalidLengthError, SimulatedBackend)
    from mailbox_backend import MailboxBackend
    from mailbox_protocol import Mode, Operation, Response, Status, VERSION
    from pynq_transport import (BridgeRegs, FrameDecoder, NotConfiguredError,
                                PynqUartTransport, parse_service_frame)

CTL_ID_VALUE = 0x514E5950
MB_ID_VALUE = 0x4D424F58
FULL, EMPTY, OVF = 1 << 16, 1 << 17, 1 << 18

# ---- 官方 KAT（公开数据，NIST SP 800-232 Final）----
KEY = bytes(range(16))
NONCE = bytes(range(16, 32))
PT1 = b'\x20'
PT16 = bytes(range(0x20, 0x30))
AD16 = bytes(range(0x30, 0x40))
CT1 = b'\xe8'
CT16 = bytes([0xe8, 0xc3, 0xde, 0xee, 0x24, 0x6c, 0xc5, 0xea,
              0xe3, 0xe8, 0x72, 0x31, 0x38, 0x97, 0xa2, 0xbb])
CT16AD = bytes([0x63, 0x73, 0xeb, 0xb2, 0x8b, 0xe9, 0x7c, 0x9b,
                0xac, 0x09, 0x0c, 0xf3, 0x99, 0xc1, 0x3e, 0xf1])
TAG_EMPTY = bytes([0x4f, 0x9c, 0x27, 0x82, 0x11, 0xbe, 0xc9, 0x31,
                   0x6b, 0xf6, 0x8f, 0x46, 0xee, 0x8b, 0x2e, 0xc6])
TAG1 = bytes([0xdd, 0x57, 0x6a, 0xba, 0x1c, 0xd3, 0xe6, 0xfc,
              0x70, 0x4d, 0xe0, 0x2a, 0xed, 0xb7, 0x95, 0x88])
TAG16 = bytes([0x9e, 0xaa, 0x91, 0x5c, 0x9d, 0xd3, 0x24, 0x5d,
               0x77, 0x04, 0x8f, 0x24, 0xd4, 0x6d, 0x27, 0xa7])
TAG16AD = bytes([0x3a, 0xbf, 0xc0, 0xd2, 0x09, 0xe8, 0xf4, 0x84,
                 0x4c, 0x90, 0x81, 0x4d, 0x13, 0xf3, 0x2c, 0x59])


# ============================ 模型：pynq_ctl ============================
class CtlModel:
    def __init__(self, ident=CTL_ID_VALUE, on_reset=None):
        self.ident = ident
        self.ctrl = 0x1          # 上电默认保持复位
        self.leds = 0
        self.on_reset = on_reset

    def read(self, off):
        if off == 0x00:
            return self.ctrl
        if off == 0x04:
            return (0 if self.ctrl else 1) | ((self.leds & 3) << 2)
        if off == 0x08:
            return self.ident
        if off == 0x0C:
            return 1
        return 0

    def write(self, off, value):
        if off == 0x00:
            was = self.ctrl
            self.ctrl = value & 0x1
            if self.ctrl and not was and self.on_reset:
                self.on_reset()      # 复位期间 link_flush：固件重来、FIFO 清空


# ============================ 模型：pynq_svc ============================
class FirmwareModel:
    """pynq_svc 固件的帧处理模型（AEAD 用 locked Python reference）。"""

    def __init__(self, *, simulated=True, firmware_id='model-svc-v1',
                 max_msg=16, max_ad=16, selftest_mask=0x7, respond=True,
                 text=b'=== model pynq_svc ===\nselftest mask = 0x7 (sw+hw+ise PASS)\nready\n'):
        self.simulated = simulated
        self.firmware_id = firmware_id
        self.max_msg, self.max_ad = max_msg, max_ad
        self.selftest_mask = selftest_mask
        self.respond = respond
        self.text = text
        self.epoch = 0
        self.inbuf = bytearray()
        self.out = bytearray()
        self.mcycle = 1000000
        self.reboot()

    # ---- 输出 ----
    def service_frame(self, epoch_set):
        flags = (0x2 if self.selftest_mask == 0x7 else 0) | (0x4 if epoch_set else 0)
        if self.simulated:
            flags |= 0x1                      # SIMULATED：模拟证据标记
        f = bytearray(64)
        f[0:4] = b'Y01S'
        f[4:6] = VERSION.to_bytes(2, 'little')
        f[6:8] = flags.to_bytes(2, 'little')
        f[8:16] = self.epoch.to_bytes(8, 'little')
        f[16:20] = (0x1 | 0x2 | 0x4).to_bytes(4, 'little')
        f[20:24] = self.max_msg.to_bytes(4, 'little')
        f[24:28] = self.max_ad.to_bytes(4, 'little')
        f[28:32] = self.selftest_mask.to_bytes(4, 'little')
        f[32:40] = self.mcycle.to_bytes(8, 'little')
        f[40:48] = (0).to_bytes(8, 'little')
        name = self.firmware_id.encode('ascii')[:16]
        f[48:48 + len(name)] = name
        return bytes(f)

    def reboot(self):
        self.epoch = 0
        self.inbuf.clear()
        self.out = bytearray(self.text or b'')
        self.out.extend(self.service_frame(epoch_set=False))

    # ---- 输入 ----
    def push_byte(self, byte):
        self.inbuf.append(byte & 0xFF)
        self.process()

    def process(self):
        while True:
            if len(self.inbuf) < 4:
                return
            head = bytes(self.inbuf[:4])
            if head == b'Y01E':
                if len(self.inbuf) < 20:
                    return
                frame = bytes(self.inbuf[:20])
                del self.inbuf[:20]
                ver = int.from_bytes(frame[4:8], 'little')
                epoch = int.from_bytes(frame[12:20], 'little')
                if ver == VERSION and epoch:
                    self.epoch = epoch
                self.out.extend(self.service_frame(epoch_set=True))
                continue
            if head == b'Y01Q':
                if len(self.inbuf) < 48:
                    return
                hdr = bytes(self.inbuf[:48])
                alen = int.from_bytes(hdr[32:36], 'little')
                dlen = int.from_bytes(hdr[36:40], 'little')
                tlen = int.from_bytes(hdr[44:48], 'little')
                total = 48 + 32 + alen + dlen + tlen
                if len(self.inbuf) < total:
                    return
                packet = bytes(self.inbuf[:total])
                del self.inbuf[:total]
                if self.respond:
                    self.out.extend(self.handle(packet))
                continue
            del self.inbuf[:1]        # 噪音字节

    def handle(self, packet):
        epoch = int.from_bytes(packet[8:16], 'little')
        rid = int.from_bytes(packet[16:24], 'little')
        op = int.from_bytes(packet[24:28], 'little')
        mode = int.from_bytes(packet[28:32], 'little')
        alen = int.from_bytes(packet[32:36], 'little')
        dlen = int.from_bytes(packet[36:40], 'little')
        cap = int.from_bytes(packet[40:44], 'little')
        tlen = int.from_bytes(packet[44:48], 'little')
        body = packet[48:]
        key, nonce = body[:16], body[16:32]
        ad = body[32:32 + alen]
        data = body[32 + alen:32 + alen + dlen]
        tag = body[32 + alen + dlen:]

        status, payload, cycles = Status.OK, b'', None
        if op not in (Operation.ENCRYPT, Operation.DECRYPT) or mode not in (1, 2, 3):
            status = Status.UNSUPPORTED
        elif alen > self.max_ad or dlen > self.max_msg or \
                tlen != (16 if op == Operation.DECRYPT else 0):
            status = Status.LENGTH
        elif cap < (dlen + 16 if op == Operation.ENCRYPT else dlen):
            status = Status.LENGTH
        elif epoch != self.epoch:
            status = Status.INTERNAL
        else:
            ref = SimulatedBackend()
            try:
                if op == Operation.ENCRYPT:
                    ct, tg = ref.encrypt(key, nonce, ad, data, timeout_s=1)
                    payload, cycles = ct + tg, 4242
                else:
                    payload = ref.decrypt(key, nonce, ad, data, tag, timeout_s=1)
                    cycles = 4242
            except AuthenticationError:
                status = Status.AUTH_FAILED
            except Exception:
                status = Status.INTERNAL
        if status != Status.OK:
            payload, cycles = b'', None
        self.mcycle += 100
        return Response(epoch, rid, Operation(op), Mode(mode), status, payload,
                        cycles, simulated=self.simulated).encode()


# ============================ 模型：pynq_mbox ============================
class MboxModel:
    """FIFO 语义 + 链路：每个 TXSTAT 读操作把若干字节送上"串口"。"""

    def __init__(self, fw, *, tx_depth=64, rx_depth=256, ident=MB_ID_VALUE, drain_per_poll=8):
        self.fw = fw
        self.ident = ident
        self.tx_depth, self.rx_depth = tx_depth, rx_depth
        self.drain_per_poll = drain_per_poll
        self.tx = bytearray()
        self.rx = bytearray()
        self.ovf = False
        self.tx_bytes = 0
        self.rx_bytes = 0

    def _wire_to_fw(self):
        n = min(self.drain_per_poll, len(self.tx))
        for _ in range(n):
            self.fw.push_byte(self.tx.pop(0))

    def _wire_to_ps(self):
        while self.fw.out:
            if len(self.rx) >= self.rx_depth:
                self.ovf = True
                return
            self.rx.append(self.fw.out[0])
            del self.fw.out[0]
            self.rx_bytes = (self.rx_bytes + 1) & 0xFFFF

    def read(self, off):
        if off == 0x04:
            return self.rx.pop(0) if self.rx else 0
        if off == 0x08:
            self._wire_to_fw()
            self._wire_to_ps()
            return ((len(self.tx) & 0xFFFF)
                    | (FULL if len(self.tx) >= self.tx_depth else 0)
                    | (EMPTY if not self.tx else 0))
        if off == 0x0C:
            self._wire_to_fw()
            self._wire_to_ps()
            return ((len(self.rx) & 0xFFFF)
                    | (FULL if len(self.rx) >= self.rx_depth else 0)
                    | (EMPTY if not self.rx else 0)
                    | (OVF if self.ovf else 0))
        if off == 0x18:
            return (self.tx_bytes & 0xFFFF) | ((self.rx_bytes & 0xFFFF) << 16)
        if off == 0x1C:
            return self.ident
        return 0

    def write(self, off, value):
        if off == 0x00:
            if len(self.tx) < self.tx_depth:
                self.tx.append(value & 0xFF)
                self.tx_bytes = (self.tx_bytes + 1) & 0xFFFF
        elif off == 0x10:
            self.ovf = False
        elif off == 0x14:
            self.tx.clear()


# ============================== 测试脚手架 ==============================
FAILS = []


def check(name, fn):
    try:
        fn()
        print('PASS %s' % name)
    except AssertionError as exc:
        FAILS.append(name)
        print('FAIL %s: %s' % (name, exc))
    except Exception as exc:            # noqa: BLE001 - 测试要看到真实异常类型
        FAILS.append(name)
        print('FAIL %s: unexpected %s: %s' % (name, type(exc).__name__, exc))


def expect(exc_type, fn, what=''):
    try:
        fn()
    except exc_type:
        return
    except Exception as exc:            # noqa: BLE001
        raise AssertionError('%s: expected %s, got %s: %s'
                             % (what, exc_type.__name__, type(exc).__name__, exc))
    raise AssertionError('%s: expected %s, nothing raised' % (what, exc_type.__name__))


def build(*, backend_mode='ise', tx_depth=64, rx_depth=256, respond=True,
          ctl_id=CTL_ID_VALUE, fw_kw=None, timeout_s=2.0):
    fw = FirmwareModel(respond=respond, **(fw_kw or {}))
    mb = MboxModel(fw, tx_depth=tx_depth, rx_depth=rx_depth)

    def _on_reset():
        fw.reboot()
        mb.tx.clear()
        mb.rx.clear()
        mb.ovf = False

    ctl = CtlModel(ctl_id, on_reset=_on_reset)
    tr = PynqUartTransport(BridgeRegs(ctl, mb, tx_depth=tx_depth, rx_depth=rx_depth),
                           expected_firmware_id='model-svc-v1')
    backend = MailboxBackend(tr, mode=backend_mode, timeout_s=timeout_s,
                             poll_interval=0.0002)
    return tr, backend, fw


# ================================ 用例 ================================
def t_identity_mismatch():
    fw = FirmwareModel()
    ctl = CtlModel(ident=0xDEADBEEF)
    tr = PynqUartTransport(BridgeRegs(ctl, MboxModel(fw)))
    expect(NotConfiguredError, lambda: tr.hello(time.monotonic() + 1), 'ctl id')


def t_hello_caps():
    tr, backend, fw = build()
    caps = backend.capabilities
    assert caps.epoch == 1, caps.epoch
    assert caps.simulated is True, 'model must advertise simulated'
    assert caps.firmware_id == 'model-svc-v1', caps.firmware_id
    assert caps.max_message_bytes == 16 and caps.max_ad_bytes == 16, caps
    assert set(caps.modes) == {Mode.SW, Mode.HW, Mode.ISE}, caps.modes
    assert backend.simulated is True
    assert backend.name.startswith('simulated-'), backend.name


def t_kat_vectors():
    tr, backend, _ = build()
    ct, tag = backend.encrypt(KEY, NONCE, b'', b'', timeout_s=2)
    assert (ct, tag) == (b'', TAG_EMPTY), 'empty'
    ct, tag = backend.encrypt(KEY, NONCE, b'', PT1, timeout_s=2)
    assert (ct, tag) == (CT1, TAG1), '1B'
    ct, tag = backend.encrypt(KEY, NONCE, b'', PT16, timeout_s=2)
    assert (ct, tag) == (CT16, TAG16), '16B'
    ct, tag = backend.encrypt(KEY, NONCE, AD16, PT16, timeout_s=2)
    assert (ct, tag) == (CT16AD, TAG16AD), '16B+AD'
    pt = backend.decrypt(KEY, NONCE, AD16, CT16AD, TAG16AD, timeout_s=2)
    assert pt == PT16, 'decrypt roundtrip'
    info = backend.cycle_info(Operation.ENCRYPT, 16, 16)
    assert info.value == 4242 and info.status == 'simulated', info


def t_tamper_rejected():
    tr, backend, _ = build()
    bad = bytearray(CT16)
    bad[0] ^= 0x01
    expect(AuthenticationError,
           lambda: backend.decrypt(KEY, NONCE, b'', bytes(bad), TAG16, timeout_s=2),
           'tamper')


def t_length_rejected():
    tr, backend, fw = build()
    expect(InvalidLengthError,
           lambda: backend.encrypt(KEY, NONCE, b'', bytes(17), timeout_s=2),
           '17B must be rejected at the advertised cap')


def t_tiny_fifo_backpressure():
    tr, backend, _ = build(tx_depth=4, rx_depth=8)
    ct, tag = backend.encrypt(KEY, NONCE, AD16, PT16, timeout_s=5)
    assert (ct, tag) == (CT16AD, TAG16AD), 'tiny FIFO must still carry the frame'


def t_text_noise_tolerated():
    tr, backend, _ = build(fw_kw={'text': b'\x00garbage\nKAT 16B: PASS\nmore junk\r\n'})
    ct, tag = backend.encrypt(KEY, NONCE, b'', PT16, timeout_s=2)
    assert (ct, tag) == (CT16, TAG16)
    snap = tr.status_snapshot()
    assert snap['service']['firmware_id'] == 'model-svc-v1', snap['service']
    assert 'KAT 16B: PASS' in snap['log'], snap['log']


def t_timeout_when_silent():
    tr, backend, fw = build(respond=False, timeout_s=0.3)
    expect(BackendTimeoutError,
           lambda: backend.encrypt(KEY, NONCE, b'', PT16, timeout_s=0.2), 'no response')


def t_reset_changes_epoch():
    tr, backend, fw = build()
    old = backend.capabilities.epoch
    backend.recover(timeout_s=2)
    assert backend.capabilities.epoch == old + 1, backend.capabilities.epoch
    ct, tag = backend.encrypt(KEY, NONCE, b'', PT16, timeout_s=2)
    assert (ct, tag) == (CT16, TAG16)


def t_stale_epoch_rejected():
    tr, backend, fw = build()
    tr.capabilities  # after hello
    req = Response(1, 1, Operation.ENCRYPT, Mode.ISE, Status.OK).encode()  # 只为取 header 布局
    packet = (b'Y01Q' + VERSION.to_bytes(2, 'little') + (0).to_bytes(2, 'little')
              + (99).to_bytes(8, 'little') + (1).to_bytes(8, 'little')
              + Operation.ENCRYPT.to_bytes(4, 'little') + Mode.ISE.to_bytes(4, 'little')
              + (0).to_bytes(4, 'little') + (1).to_bytes(4, 'little')
              + (17).to_bytes(4, 'little') + (0).to_bytes(4, 'little')
              + KEY + NONCE + PT1)
    deadline = time.monotonic() + 2
    tr.submit(packet, deadline)
    raw = tr.poll(deadline)
    resp = Response.decode(raw)
    assert resp.status == Status.INTERNAL, resp.status
    tr.ack(resp.epoch, resp.request_id, time.monotonic() + 1)


def t_slot_and_ack_discipline():
    tr, backend, fw = build()
    fw.respond = False
    deadline = time.monotonic() + 0.5
    packet = (b'Y01Q' + VERSION.to_bytes(2, 'little') + (0).to_bytes(2, 'little')
              + (1).to_bytes(8, 'little') + (7).to_bytes(8, 'little')
              + Operation.ENCRYPT.to_bytes(4, 'little') + Mode.ISE.to_bytes(4, 'little')
              + (0).to_bytes(4, 'little') + (1).to_bytes(4, 'little')
              + (17).to_bytes(4, 'little') + (0).to_bytes(4, 'little')
              + KEY + NONCE + PT1)
    tr.submit(packet, deadline)
    expect(BackendProtocolError, lambda: tr.submit(packet, deadline), 'double submit')
    expect(BackendProtocolError, lambda: tr.ack(1, 7, time.monotonic() + 0.5),
           'ack before completion')
    fw.respond = True
    fw.process()
    raw = tr.poll(deadline)
    expect(BackendProtocolError, lambda: tr.ack(1, 8, time.monotonic() + 0.5),
           'wrong ack id')
    tr.ack(1, 7, time.monotonic() + 0.5)
    assert tr.poll.__self__._response is None


def t_frame_decoder():
    d = FrameDecoder()
    body = Response(1, 2, Operation.ENCRYPT, Mode.SW, Status.OK, b'abcd', 10,
                    simulated=False).encode()
    d.feed(b'noise\n' + body + b'tail')
    kind, frame = d.pop_frame()
    assert kind == 'R' and frame == body, (kind, frame)
    assert d.pop_frame() is None
    svc = parse_service_frame(FirmwareModel().service_frame(True))
    assert svc['epoch_set'] is True and svc['simulated'] is True, svc


def t_no_hello_submit():
    tr, backend, fw = build()
    fresh = PynqUartTransport(BridgeRegs(CtlModel(), MboxModel(FirmwareModel())))
    expect(NotConfiguredError,
           lambda: fresh.submit(b'Y01Q' + b'\x00' * 44, time.monotonic() + 1), 'no hello')


TESTS = [
    ('identity mismatch -> NotConfigured', t_identity_mismatch),
    ('hello capabilities', t_hello_caps),
    ('official KAT through the frame path', t_kat_vectors),
    ('tamper rejected', t_tamper_rejected),
    ('17B rejected at advertised cap', t_length_rejected),
    ('tiny FIFO backpressure', t_tiny_fifo_backpressure),
    ('text noise tolerated', t_text_noise_tolerated),
    ('silent peer -> timeout', t_timeout_when_silent),
    ('reset changes epoch', t_reset_changes_epoch),
    ('stale epoch -> INTERNAL', t_stale_epoch_rejected),
    ('slot/ACK discipline', t_slot_and_ack_discipline),
    ('frame decoder', t_frame_decoder),
    ('submit before hello', t_no_hello_submit),
]


def main():
    for name, fn in TESTS:
        check(name, fn)
    if FAILS:
        print('\n%d/%d FAILED' % (len(FAILS), len(TESTS)))
        return 1
    print('\nall %d pynq_transport tests passed' % len(TESTS))
    return 0


if __name__ == '__main__':
    sys.exit(main())

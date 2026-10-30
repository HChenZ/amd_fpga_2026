"""test_pynq_puf3.py —— pynq_puf3 驱动的寄存器级模型测试（无硬件、不产生测量数据）。

复用 test_pynq_transport.py 的 pynq_ctl / pynq_mbox / pynq_svc 模型，再加一个按
src/firmware/pynq_svc_puf/puf_svc.c 语义实现的 Y01P/Y01K 模型。真实固件/RTL 的
同一协议由 sim/pynq_puf3/run.py（Icarus，真实 RV32）验证。

运行：python -X utf8 src/pynq/test_pynq_puf3.py
"""
import struct
import sys
import time

if __package__:
    from .ascon_host_api import AsconHost, BackendProtocolError
    from .mailbox_backend import MailboxBackend
    from .mailbox_protocol import Mode
    from .pynq_transport import NotConfiguredError
    from .pynq_puf3 import (CTL_ID_PQF3, Puf3BridgeRegs, Puf3FrameDecoder, PynqPuf3Transport,
                            parse_puf_frame, puf_request)
    from . import test_pynq_transport as base
else:
    from ascon_host_api import AsconHost, BackendProtocolError
    from mailbox_backend import MailboxBackend
    from mailbox_protocol import Mode
    from pynq_transport import NotConfiguredError
    from pynq_puf3 import (CTL_ID_PQF3, Puf3BridgeRegs, Puf3FrameDecoder, PynqPuf3Transport,
                           parse_puf_frame, puf_request)
    import test_pynq_transport as base


class PufFirmwareModel(base.FirmwareModel):
    """pynq_svc_puf 的帧处理模型：三模式部分沿用基类，PUF 状态按 puf_svc.c 语义演。"""

    def __init__(self, *, wrong_seq=False, **kw):
        kw.setdefault('firmware_id', 'pynq-svc-puf3')
        self.wrong_seq = wrong_seq
        self.puf_reset()
        super().__init__(**kw)

    def puf_reset(self):
        # boot auto-reconstruct without helper: ready + mismatch + fallback + done
        self.st = {'ready': 1, 'enrolled': 0, 'mismatch': 1, 'fallback': 1, 'done': 1, 'hw': 0}

    def reboot(self):
        self.puf_reset()
        super().reboot()

    def status_word(self):
        s = self.st
        return (s['ready'] << 1 | s['enrolled'] << 2 | s['mismatch'] << 3 | s['fallback'] << 4
                | s['done'] << 5 | s['hw'] << 6 | s['hw'] << 7 | (100 if s['enrolled'] else 0) << 8)

    def puf_frame(self, cmd, seq):
        result = 0
        if cmd in (1, 2):
            self.st['hw'] = 0
            if cmd == 1:
                self.st.update(enrolled=1)
            if self.st['enrolled']:
                self.st.update(ready=1, mismatch=0, fallback=0, done=1)
        elif cmd == 3:
            s = self.st
            if not s['ready'] or not s['enrolled'] or s['mismatch'] or s['fallback']:
                result = 5
            else:
                s['hw'] = 1
        elif cmd == 4:
            self.st['hw'] = 0
        elif cmd != 0:
            result = 3
        f = bytearray(112)
        f[0:4] = b'Y01K'
        struct.pack_into('<HHIIIIIIQ', f, 4, 1, 0x2 if self.simulated else 0, cmd, seq + (1 if self.wrong_seq else 0), result,
                         self.status_word(), 0x89ABCDEF, 0x01234567, 1300000)
        f[40:56] = b'Y01R' * 4                      # payload that looks like another magic
        return bytes(f)

    def handle(self, packet):
        # HWKEY on: HW mode ignores the caller key (model "PUF key" = caller key XOR 0x5A)
        if self.st['hw'] and int.from_bytes(packet[28:32], 'little') == 2:
            packet = packet[:48] + bytes(b ^ 0x5A for b in packet[48:64]) + packet[64:]
        return super().handle(packet)

    def process(self):
        while len(self.inbuf) >= 4:
            if bytes(self.inbuf[:4]) == b'Y01P':
                if len(self.inbuf) < 16:
                    return
                ver, cmd, seq = struct.unpack_from('<III', self.inbuf, 4)
                del self.inbuf[:16]
                self.out.extend(b'puf log line\r\n' + self.puf_frame(cmd, seq))
                continue
            if bytes(self.inbuf[:4]) == b'Y01E':
                self.st['hw'] = 0                   # firmware turns HWKEY off before selftest
            return super().process()


def build(ctl_id=CTL_ID_PQF3, **fw_kw):
    fw = PufFirmwareModel(**fw_kw)
    mb = base.MboxModel(fw)

    def on_reset():
        fw.reboot()
        mb.tx.clear()
        mb.rx.clear()
        mb.ovf = False

    ctl = base.CtlModel(ctl_id, on_reset=on_reset)
    tr = PynqPuf3Transport(Puf3BridgeRegs(ctl, mb))
    return tr, fw


def t_identity():
    for ident in (base.CTL_ID_VALUE, 0x31554650):           # release PYNQ, PUF-only PFU1
        tr, _ = build(ctl_id=ident)
        base.expect(NotConfiguredError, lambda: tr.hello(time.monotonic() + 1), hex(ident))
    tr, _ = build()
    caps = tr.hello(time.monotonic() + 2)
    assert caps.firmware_id == 'pynq-svc-puf3' and len(caps.modes) == 3


def t_firmware_id_enforced():
    tr, _ = build(firmware_id='pynq-svc-v1')
    base.expect(BackendProtocolError, lambda: tr.hello(time.monotonic() + 2), 'fw id')


def t_three_modes_kat():
    tr, _ = build()
    backend = MailboxBackend(tr, mode='sw', timeout_s=2.0, poll_interval=0.0002)
    for mode in (Mode.SW, Mode.HW, Mode.ISE):
        backend.mode = mode
        host = AsconHost(backend)
        r = host.encrypt(base.KEY, base.NONCE, b'', base.PT16, timeout_s=2)
        assert r.ciphertext == base.CT16 and r.tag == base.TAG16, mode


def t_puf_flow():
    tr, fw = build()
    tr.hello(time.monotonic() + 2)
    d = lambda: time.monotonic() + 2
    st = tr.puf_command('status', d())
    assert st['result'] == 'OK' and st['status']['fallback'] and not st['status']['key_hw_sel']
    assert st['dna'] == '123456789abcdef' and st['op_mcycle'] == 1300000
    assert tr.puf_command('hwkey_on', d())['result'] == 'NO_PUF_KEY'
    en = tr.puf_command('enroll', d())
    assert en['result'] == 'OK' and en['status']['enrolled'] and en['quality'] == 100
    rc = tr.puf_command('reconstruct', d())
    assert rc['result'] == 'OK' and not rc['status']['mismatch'] and not rc['status']['fallback']
    on = tr.puf_command('hwkey_on', d())
    assert on['result'] == 'OK' and on['status']['key_hw_sel'] and on['status']['hwkey_on']
    assert tr.puf_command(9, d())['result'] == 'BAD_CMD'
    off = tr.puf_command('hwkey_off', d())
    assert not off['status']['key_hw_sel']
    assert 'puf log line' in tr.status_snapshot()['log']


def t_puf_then_aead_then_reset():
    tr, fw = build()
    backend = MailboxBackend(tr, mode='hw', timeout_s=2.0, poll_interval=0.0002)
    tr.puf_command('enroll', time.monotonic() + 2)
    tr.puf_command('hwkey_on', time.monotonic() + 2)
    ct, tag = backend.encrypt(base.KEY, base.NONCE, b'', base.PT16, timeout_s=2)
    assert len(ct) == 16 and len(tag) == 16
    backend.recover(timeout_s=2)                              # reset: helper volatile, HWKEY off
    st = tr.puf_command('status', time.monotonic() + 2)
    assert st['status']['fallback'] and not st['status']['hwkey_on']


def t_seq_mismatch():
    tr, _ = build(wrong_seq=True)
    tr.hello(time.monotonic() + 2)
    base.expect(BackendProtocolError, lambda: tr.puf_command('status', time.monotonic() + 2), 'seq')


def t_slot_occupied():
    tr, _ = build()
    tr.hello(time.monotonic() + 2)
    tr._pending = (1, 1)
    base.expect(BackendProtocolError, lambda: tr.puf_command('status', time.monotonic() + 2), 'slot')


def t_hello_required():
    tr, _ = build()
    base.expect(NotConfiguredError, lambda: tr.puf_command('status', time.monotonic() + 2), 'hello')


def t_decoder_mixed_stream():
    fw = PufFirmwareModel()
    k = fw.puf_frame(0, 7)
    s = fw.service_frame(True)
    dec = Puf3FrameDecoder()
    dec.feed(b'text ' + k[:50])
    assert dec.pop_frame() is None
    dec.feed(k[50:] + b'noise' + s)
    kind, frame = dec.pop_frame()
    assert kind == 'K' and frame == k and parse_puf_frame(frame)['seq'] == 7
    kind, frame = dec.pop_frame()
    assert kind == 'S' and frame == s
    assert dec.pop_frame() is None and bytes(dec.log) == b'text noise'


def t_parse_rejects():
    fw = PufFirmwareModel()
    k = bytearray(fw.puf_frame(0, 1))
    k[110] = 1
    base.expect(BackendProtocolError, lambda: parse_puf_frame(bytes(k)), 'reserved')
    base.expect(BackendProtocolError, lambda: parse_puf_frame(bytes(k[:100])), 'short')
    base.expect(ValueError, lambda: puf_request(-1, 1), 'cmd')
    assert puf_request(2, 5) == b'Y01P' + struct.pack('<III', 1, 2, 5)


def _board_test_module():
    import importlib.util
    from pathlib import Path
    path = Path(__file__).resolve().parents[2] / 'board/vivado_zynq7000_xc7z020_pynq_puf3/board_test.py'
    spec = importlib.util.spec_from_file_location('pynq_puf3_board_test', path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def t_board_test_sections_on_model():
    """board_test.py 的判定逻辑在模型上能走通（模型把 simulated 关掉以通过证据检查）。"""
    bt = _board_test_module()
    tr, fw = build(simulated=False)
    backend = MailboxBackend(tr, mode='sw', timeout_s=5.0, poll_interval=0.0002)
    kat = bt.section_kat(backend, False)
    assert all(v['kat_pass'] == 6 and v['tag_reject'] == 6 for v in kat.values())
    bench = bt.section_benchmark(backend, 1, 2, 529)
    assert set(bench['speedup_median_vs_sw']) == {'hw', 'ise'}
    puf = bt.section_puf(tr, backend, 2)
    assert puf['caller_key_rejected_under_puf_key'] and puf['reconstructs_stable'] == 2


def t_board_test_detects_no_hwkey():
    """若 HW 在 HWKEY 打开后仍用调用方 key（自动锁定问题的反面），板测必须失败。"""
    bt = _board_test_module()
    tr, fw = build(simulated=False)
    fw.handle = lambda packet: base.FirmwareModel.handle(fw, packet)
    backend = MailboxBackend(tr, mode='sw', timeout_s=5.0, poll_interval=0.0002)
    base.expect(AssertionError, lambda: bt.section_puf(tr, backend, 1), 'caller key still used')


CASES = [t_identity, t_firmware_id_enforced, t_three_modes_kat, t_puf_flow, t_puf_then_aead_then_reset,
         t_seq_mismatch, t_slot_occupied, t_hello_required, t_decoder_mixed_stream, t_parse_rejects,
         t_board_test_sections_on_model, t_board_test_detects_no_hwkey]

if __name__ == '__main__':
    for case in CASES:
        base.check(case.__name__, case)
    print('%d/%d PASS' % (len(CASES) - len(base.FAILS), len(CASES)))
    sys.exit(1 if base.FAILS else 0)

"""Icarus cosimulation of the pynq_puf3 overlay path (three-mode service + PUF v1 frames).

Run from the repository root (after src/firmware/pynq_svc_puf/build.py):
    python -X utf8 sim/pynq_puf3/run.py
Cases:
  normal         - variant RTL (board/vivado_zynq7000_xc7z020_pynq_puf3/rtl); the whole script
                   (boot selftest, 36 three-mode KAT requests, PUF enroll/reconstruct/HWKEY,
                   PUF-key rejection of the caller key, re-handshake) must PASS.
  mutant_autolock - original src/rtl/soc_top.v + src/rtl/keys/key_mmio.v (key latched on
                   key_valid). The same firmware must lose the HW-mode KAT (selftest mask != 7)
                   and the TB must exit non-zero. This proves the RTL change is what fixes it.
Exit code 0 only if both cases behave as required.
"""
import hashlib
import json
import re
import struct
import subprocess
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(root))
from src.pynq.golden_checker import parse_kat  # noqa: E402
from src.pynq.mailbox_protocol import Mode, Operation, Request, Response, Status  # noqa: E402
from src.pynq.pynq_transport import epoch_frame  # noqa: E402

out = root / 'build/local/pynq_puf3/sim'
out.mkdir(parents=True, exist_ok=True)
fw_hex = root / 'build/local/pynq_svc_puf/pynq_svc_puf.hex'
fw_bin = root / 'build/local/pynq_svc_puf/pynq_svc_puf.bin'
variant = root / 'board/vivado_zynq7000_xc7z020_pynq_puf3/rtl'
FW_ID = b'pynq-svc-puf3'

steps = []   # (send, expected, mask)


def svc_expect(epoch, epoch_set):
    flags = 0x2 | (0x4 if epoch_set else 0)
    exp = (b'Y01S' + struct.pack('<HHQIIII', 1, flags, epoch, 7, 16, 16, 7) + bytes(16)
           + FW_ID.ljust(16, b'\0'))
    mask = b'\xff' * 6 + b'\x06\x00' + b'\xff' * 24 + bytes(16) + b'\xff' * 16
    return exp, mask


def rsp_expect(response, payload_known=True):
    exp = response.encode()
    mask = bytearray(b'\xff' * len(exp))
    mask[40:48] = bytes(8)                       # mcycle value differs per run
    if not payload_known:
        mask[48:] = bytes(len(exp) - 48)
    return exp, bytes(mask)


def puf_req(cmd, seq):
    return b'Y01P' + struct.pack('<III', 1, cmd, seq)


def puf_expect(cmd, seq, result, status=None, status_mask=0xFF, quality=None):
    exp = bytearray(112)
    mask = bytearray(112)
    exp[0:20] = b'Y01K' + struct.pack('<HHIII', 1, 0, cmd, seq, result)
    mask[0:20] = b'\xff' * 20
    if status is not None:
        exp[20], mask[20] = status, status_mask
    if quality is not None:
        exp[21], mask[21] = quality, 0xFF
    mask[22:24] = b'\xff\xff'                    # STATUS[31:16] reserved = 0
    return bytes(exp), bytes(mask)


def add(send, em):
    steps.append((send, em[0], em[1]))


kat = parse_kat()
rid = 0
add(b'', svc_expect(0, False))                       # boot frame
add(epoch_frame(1), svc_expect(1, True))
for mode in Mode:
    for size, alen in [(0, 0), (1, 0), (16, 0), (16, 16)]:
        c = next(c for c in kat if len(c['PT']) == size and len(c['AD']) == alen)
        key, nonce, ad, pt = (c[k] for k in ('Key', 'Nonce', 'AD', 'PT'))
        ct, tag = c['CT'][:-16], c['CT'][-16:]
        for op, data, t, st, payload in [
                (Operation.ENCRYPT, pt, b'', Status.OK, ct + tag),
                (Operation.DECRYPT, ct, tag, Status.OK, pt),
                (Operation.DECRYPT, ct, bytes([tag[0] ^ 1]) + tag[1:], Status.AUTH_FAILED, b'')]:
            rid += 1
            q = Request(1, rid, op, mode, key, nonce, ad, data, size + 16, t).encode()
            add(q, rsp_expect(Response(1, rid, op, mode, st, payload, 1 if st == Status.OK else None, False)))

c16 = next(c for c in kat if len(c['PT']) == 16 and len(c['AD']) == 0)
K, N, AD, PT, CT = (c16[k] for k in ('Key', 'Nonce', 'AD', 'PT', 'CT'))


def aead(mode, op, epoch, payload_known=True, status=Status.OK):
    global rid
    rid += 1
    if op == Operation.ENCRYPT:
        q = Request(epoch, rid, op, mode, K, N, AD, PT, 32).encode()
        data = CT if status == Status.OK else b''
    else:
        q = Request(epoch, rid, op, mode, K, N, AD, CT[:-16], 16, CT[-16:]).encode()
        data = PT if status == Status.OK else b''
    r = Response(epoch, rid, op, mode, status, data, 1 if status == Status.OK else None, False)
    add(q, rsp_expect(r, payload_known))


# STATUS bits: 0 busy 1 ready 2 enrolled 3 mismatch 4 fallback 5 done 6 hw_sel 7 hwkey_on
add(puf_req(0, 1), puf_expect(0, 1, 0, 0x3A, 0xFF, quality=0))   # boot auto-reconstruct: no helper -> fallback
add(puf_req(3, 2), puf_expect(3, 2, 5, 0x00, 0xC0))              # HWKEY_ON refused on DNA-only fallback key
add(puf_req(1, 3), puf_expect(1, 3, 0, 0x26, 0xFF))              # ENROLL
add(puf_req(2, 4), puf_expect(2, 4, 0, 0x26, 0xFF))              # RECONSTRUCT matches helper
add(puf_req(3, 5), puf_expect(3, 5, 0, 0xE6, 0xFF))              # HWKEY_ON accepted, hw_sel=1
aead(Mode.HW, Operation.ENCRYPT, 1, payload_known=False)         # runs under the PUF key
aead(Mode.HW, Operation.DECRYPT, 1, status=Status.AUTH_FAILED)   # caller key no longer used by HW
aead(Mode.SW, Operation.DECRYPT, 1)                              # SW still uses the caller key
aead(Mode.ISE, Operation.ENCRYPT, 1)                             # ISE unaffected
add(puf_req(4, 6), puf_expect(4, 6, 0, 0x26, 0xFF))              # HWKEY_OFF
aead(Mode.HW, Operation.ENCRYPT, 1)                              # official KAT again
add(puf_req(9, 7), puf_expect(9, 7, 3))                          # unknown command
add(puf_req(3, 8), puf_expect(3, 8, 0, 0xE6, 0xFF))              # HWKEY_ON again
rid = 0
add(epoch_frame(2), svc_expect(2, True))                         # re-handshake: firmware turns HWKEY off first
add(puf_req(0, 9), puf_expect(0, 9, 0, 0x00, 0xC0))
aead(Mode.HW, Operation.ENCRYPT, 2)

req = b''.join(s[0] for s in steps)
exp = b''.join(s[1] for s in steps)
msk = b''.join(s[2] for s in steps)
for name, items, width in [('requests', req, 2), ('expected', exp, 2), ('mask', msk, 2),
                           ('sizes', [len(s[0]) for s in steps], 8), ('counts', [len(s[1]) for s in steps], 8)]:
    (out / (name + '.hex')).write_text(''.join(format(x, '0%dx' % width) + '\n' for x in items))

common = sorted(str(p) for p in (root / 'src/rtl').glob('*.v') if p.name not in ('top_pl_bram.v', 'soc_top.v'))
common += sorted(str(p) for p in (root / 'src/rtl/ascon').glob('*.v') if not p.name.endswith('_tb.v'))
common += sorted(str(p) for p in (root / 'src/rtl/keys').glob('*.v') if p.name != 'key_mmio.v')
common += [str(root / p) for p in ('src/rtl/pynq/pynq_ctl.v', 'src/rtl/pynq/pynq_mbox.v',
                                   'sim/ascon/axi_slave_bram.v', 'sim/keys/DNA_PORT_sim.v',
                                   'sim/keys/BUFG_sim.v', 'sim/keys/LUT_sim.v',
                                   'sim/pynq_puf3/tb_pynq_puf3.v')]
sets = {'normal': [str(variant / 'soc_top.v'), str(variant / 'key_mmio.v')],
        'mutant_autolock': [str(root / 'src/rtl/soc_top.v'), str(root / 'src/rtl/keys/key_mmio.v')]}


def run_case(name):
    vvp = out / (name + '.vvp')
    vvp.unlink(missing_ok=True)
    cmds = [['iverilog', '-g2012', '-I', str(root / 'src/rtl'), '-I', str(root / 'src/rtl/ascon'),
             '-s', 'tb_pynq_puf3', '-o', str(vvp)] + common + sets[name],
            ['vvp', '-n', str(vvp), '+HEX=' + str(fw_hex), '+STEPS=%d' % len(steps)]]
    records = []
    for i, cmd in enumerate(cmds):
        log = out / ('%s_step%d.log' % (name, i))
        with log.open('wb') as f:
            p = subprocess.run(cmd, cwd=root, stdout=f, stderr=subprocess.STDOUT, timeout=7200)
        body = log.read_text(errors='replace')
        records.append({'command': cmd, 'exit_code': p.returncode, 'log': log.relative_to(root).as_posix()})
        print('==== %s step %d exit %d\n%s' % (name, i, p.returncode, body[-3000:]), flush=True)
        if i == 0 and (p.returncode or not vvp.exists()):
            return records, None
    return records, (out / ('%s_step1.log' % name)).read_text(errors='replace')


normal_rec, normal_log = run_case('normal')
normal_ok = (normal_log is not None and normal_rec[-1]['exit_code'] == 0
             and 'TB_PYNQ_PUF3: PASS' in normal_log
             and normal_log.count('PASS (real RV32') == len(steps))
mutant_rec, mutant_log = run_case('mutant_autolock')
mutant_ok = (mutant_log is not None and mutant_rec[-1]['exit_code'] != 0
             and 'TB_PYNQ_PUF3: FAIL step 0' in mutant_log
             and re.search(r'MISMATCH step 0 byte 28 got 0[0-6] expected 07', mutant_log) is not None)
code = 0 if normal_ok and mutant_ok else 1
summary = {'result': 'PASS' if code == 0 else 'FAIL', 'exit_code': code, 'steps': len(steps),
           'normal_pass': normal_ok, 'mutant_autolock_detected': mutant_ok,
           'firmware_bin_sha256': hashlib.sha256(fw_bin.read_bytes()).hexdigest(),
           'variant_sha256': {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(variant.glob('*.v'))},
           'simulation_only': 'behavioral RO/DNA/BUFG and AXI BRAM; KEY_WINDOW=256 via defparam',
           'normal': normal_rec, 'mutant_autolock': mutant_rec}
(out / 'summary.json').write_text(json.dumps(summary, indent=2), encoding='utf-8')
print(summary['result'], 'normal_pass=%s mutant_autolock_detected=%s steps=%d' % (normal_ok, mutant_ok, len(steps)))
sys.exit(code)

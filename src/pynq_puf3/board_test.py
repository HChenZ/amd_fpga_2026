"""Board test of the pynq_puf3 overlay: three-mode KAT + warm benchmark + PUF v1 on one bitstream.

Run on the PYNQ board from a repository copy (candidate files present):
  sudo -E python3 src/pynq_puf3/board_test.py \
      --candidate board/vivado_zynq7000_xc7z020_pynq_puf3/candidate \
      --out data/pynq_puf3/board_<date>_run1
Sections (all must pass for exit code 0; evidence is written even on failure):
  1. identity: bit/hwh hashes = manifest, PQF3 + MBOX IDs, FCLK0 100 MHz, firmware pynq-svc-puf3;
  2. kat: official KAT subset (or --full-kat) in SW/HW/ISE, decrypt + tag rejection;
  3. benchmark: KAT #529 warmup/repetitions per mode, mcycle medians and speedup vs SW;
  4. puf: enroll, N reconstructs (no mismatch/fallback, helper unchanged), HWKEY on ->
     HW rejects the caller key, PUF-key round trip, same ciphertext after reconstruct,
     HWKEY off -> official KAT again.
No simulation fallback. Cross-power-cycle reconstruction, entropy/BER/temperature: not measured.
"""
import argparse
import datetime
import hashlib
import json
import platform
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'src/pynq'))
sys.path.insert(0, str(ROOT / 'src/pynq_puf3'))
from ascon_host_api import AsconHost, AuthenticationError  # noqa: E402
from board_benchmark import _run_once, select_kat_case, summarize  # noqa: E402
from golden_checker import parse_kat  # noqa: E402
from mailbox_backend import MailboxBackend  # noqa: E402
from mailbox_protocol import Mode  # noqa: E402
from pynq_puf3 import CTL_ID_PQF3, FIRMWARE_ID, Puf3BridgeRegs, PynqPuf3Transport  # noqa: E402

MODES = (('sw', Mode.SW), ('hw', Mode.HW), ('ise', Mode.ISE))


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def set_mode(backend, mode):
    backend.mode = mode
    backend.name = 'mailbox-' + mode.name.lower()


def section_kat(backend, full):
    cases = [c for c in parse_kat() if len(c['PT']) <= 16 and len(c['AD']) <= 16]
    if not full:
        cases = [cases[i] for i in (0, 1, 16, 17, 144, 288)]
    out = {}
    host = AsconHost(backend)
    for name, mode in MODES:
        set_mode(backend, mode)
        passed = rejected = 0
        for c in cases:
            k, n, ad, pt, ct = (c[x] for x in ('Key', 'Nonce', 'AD', 'PT', 'CT'))
            r = host.encrypt(k, n, ad, pt, timeout_s=10)
            assert not r.simulated and r.ciphertext + r.tag == ct, '%s KAT %s encrypt mismatch' % (name, c['count'])
            assert host.decrypt(k, n, ad, ct[:-16], ct[-16:], timeout_s=10).plaintext == pt
            try:
                host.decrypt(k, n, ad, ct[:-16], ct[-16:-1] + bytes([ct[-1] ^ 1]), timeout_s=10)
            except AuthenticationError:
                rejected += 1
            else:
                raise AssertionError('%s accepted a bad tag' % name)
            passed += 1
        out[name] = {'kat_pass': passed, 'tag_reject': rejected, 'cases': [c['count'] for c in cases]}
        print('kat', name, out[name]['kat_pass'], flush=True)
    return out


def section_benchmark(backend, warmup, reps, kat_count):
    case = select_kat_case(kat_count)
    host = AsconHost(backend)
    out = {'kat': kat_count, 'warmup': warmup, 'repetitions': reps,
           'measurement_scope': 'firmware AEAD mcycle; excludes PS/UART', 'modes': {}}
    for name, mode in MODES:
        set_mode(backend, mode)
        for _ in range(warmup):
            _run_once(host, case)
        samples = [_run_once(host, case) for _ in range(reps)]
        out['modes'][name] = {}
        for op in ('encrypt', 'decrypt'):
            raw = [s[op + '_cycles'] for s in samples]
            wall = [s[op + '_wall_ns'] for s in samples]
            out['modes'][name][op] = {'summary': summarize(raw), 'raw_cycles': raw,
                                      'wall_ns_summary': summarize(wall)}
        print('bench', name, {op: out['modes'][name][op]['summary']['median'] for op in ('encrypt', 'decrypt')},
              flush=True)
    sw = out['modes']['sw']
    out['speedup_median_vs_sw'] = {
        name: {op: round(sw[op]['summary']['median'] / out['modes'][name][op]['summary']['median'], 3)
               for op in ('encrypt', 'decrypt')} for name in ('hw', 'ise')}
    print('speedup', out['speedup_median_vs_sw'], flush=True)
    return out


def section_puf(transport, backend, reconstructs):
    log = []

    def cmd(name, expect='OK'):
        frame = transport.puf_command(name, time.monotonic() + 10)
        log.append(frame)
        print('puf', name, frame['result'], hex(frame['status_raw']), 'quality', frame['quality'], flush=True)
        assert frame['result'] == expect, '%s returned %s' % (name, frame['result'])
        return frame

    case = select_kat_case()
    k, n, ad, pt, ct = (case[x] for x in ('Key', 'Nonce', 'AD', 'PT', 'CT'))
    host = AsconHost(backend)
    set_mode(backend, Mode.HW)
    boot = cmd('status')
    if boot['status']['fallback']:
        cmd('hwkey_on', expect='NO_PUF_KEY')       # DNA-only fallback key must not be accepted
    enroll = cmd('enroll')
    assert enroll['status']['enrolled'] and enroll['quality'] > 0, 'enroll produced no usable bits'
    recon = []
    for _ in range(reconstructs):
        f = cmd('reconstruct')
        s = f['status']
        assert s['key_ready'] and not s['mismatch'] and not s['fallback'], 'reconstruct mismatch/fallback'
        assert (f['ref'], f['mask'], f['dna']) == (enroll['ref'], enroll['mask'], enroll['dna'])
        recon.append(f)
    on = cmd('hwkey_on')
    assert on['status']['key_hw_sel'] and on['status']['hwkey_on']
    r1 = host.encrypt(k, n, ad, pt, timeout_s=10)
    assert r1.ciphertext + r1.tag != ct, 'HW still used the caller key with HWKEY on'
    assert host.decrypt(k, n, ad, r1.ciphertext, r1.tag, timeout_s=10).plaintext == pt, 'PUF-key round trip'
    try:
        host.decrypt(k, n, ad, ct[:-16], ct[-16:], timeout_s=10)
    except AuthenticationError:
        caller_key_rejected = True
    else:
        raise AssertionError('official KAT ciphertext accepted under the PUF key')
    cmd('reconstruct')                               # firmware switches HWKEY off while regenerating
    cmd('hwkey_on')
    r2 = host.encrypt(k, n, ad, pt, timeout_s=10)
    assert (r2.ciphertext, r2.tag) == (r1.ciphertext, r1.tag), 'PUF key changed after reconstruct'
    off = cmd('hwkey_off')
    assert not off['status']['key_hw_sel']
    r3 = host.encrypt(k, n, ad, pt, timeout_s=10)
    assert r3.ciphertext + r3.tag == ct, 'HW KAT not restored after HWKEY off'
    return {'frames': log, 'dna': enroll['dna'], 'enroll_quality': enroll['quality'],
            'reconstructs_stable': len(recon), 'caller_key_rejected_under_puf_key': caller_key_rejected,
            'puf_key_ciphertext_tag': (r1.ciphertext + r1.tag).hex(),
            'same_ciphertext_after_reconstruct': True, 'kat_restored_after_hwkey_off': True,
            'puf_key_hw_encrypt_cycles': r1.cycles,
            'limits': 'in-session only (helper volatile); REF/MASK/RAW/DNA readable; '
                      'entropy/BER/temperature/cross-power-cycle not measured'}


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('--candidate', required=True, type=Path)
    p.add_argument('--out', required=True, type=Path)
    p.add_argument('--full-kat', action='store_true')
    p.add_argument('--warmup', type=int, default=5)
    p.add_argument('--repetitions', type=int, default=30)
    p.add_argument('--kat', type=int, default=529)
    p.add_argument('--reconstructs', type=int, default=5)
    a = p.parse_args()
    if a.warmup < 0 or a.repetitions < 2 or a.reconstructs < 1:
        p.error('--warmup >= 0, --repetitions >= 2, --reconstructs >= 1 required')
    a.out.mkdir(parents=True, exist_ok=False)
    bit, hwh, man = a.candidate / 'pynq_puf3.bit', a.candidate / 'pynq_puf3.hwh', a.candidate / 'manifest.json'
    result = {'timestamp': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'kind': 'physical_board_pynq_puf3', 'host': platform.platform(), 'python': sys.version,
              'command': sys.argv, 'sections': {}, 'status': 'FAIL', 'exit_code': 1,
              'timing_signoff_ro_domain': False, 'cross_power_cycle': 'not_measured'}
    transport = None
    try:
        manifest = json.loads(man.read_text())
        exp = manifest['artifacts']
        result.update(bit_sha256=digest(bit), hwh_sha256=digest(hwh), manifest_sha256=digest(man))
        if result['bit_sha256'] != exp['pynq_puf3.bit']['sha256'] or result['hwh_sha256'] != exp['pynq_puf3.hwh']['sha256']:
            raise RuntimeError('bit/hwh do not match candidate manifest')
        import pynq
        result['pynq_version'] = pynq.__version__
        ol = pynq.Overlay(str(bit), download=True)
        result['ip_dict'] = {k: {'phys_addr': v['phys_addr'], 'addr_range': v['addr_range']} for k, v in ol.ip_dict.items()}
        for name in ('pynq_ctl_0', 'pynq_mbox_0'):
            if name not in ol.ip_dict:
                raise RuntimeError('HWH instance missing: ' + name)
        ctl = pynq.MMIO(ol.ip_dict['pynq_ctl_0']['phys_addr'], ol.ip_dict['pynq_ctl_0']['addr_range'])
        mb = pynq.MMIO(ol.ip_dict['pynq_mbox_0']['phys_addr'], ol.ip_dict['pynq_mbox_0']['addr_range'])
        result['fclk0_mhz'] = float(pynq.Clocks.fclk0_mhz)
        if abs(result['fclk0_mhz'] - 100) > 0.5:
            raise RuntimeError('FCLK0 must be 100 MHz, got %s' % result['fclk0_mhz'])
        regs = Puf3BridgeRegs(ctl, mb)
        regs.check_identity()
        result['control_id'] = '0x%08X' % CTL_ID_PQF3
        transport = PynqPuf3Transport(regs, expected_firmware_id=FIRMWARE_ID)
        backend = MailboxBackend(transport, mode='sw', timeout_s=30.0)
        result['service'] = transport.last_service
        result['sections']['kat'] = section_kat(backend, a.full_kat)
        result['sections']['benchmark'] = section_benchmark(backend, a.warmup, a.repetitions, a.kat)
        result['sections']['puf'] = section_puf(transport, backend, a.reconstructs)
        result.update(status='PASS', exit_code=0)
    except Exception as e:  # keep partial evidence
        result['error'] = repr(e)
    finally:
        if transport is not None:
            snap = transport.status_snapshot()
            (a.out / 'mailbox_log.txt').write_text(snap.pop('log'), encoding='utf-8')
            result['final_snapshot'] = snap
        (a.out / 'result.json').write_text(json.dumps(result, indent=2, default=str) + '\n', encoding='utf-8')
    print(result['status'], a.out, result.get('error', ''))
    return result['exit_code']


if __name__ == '__main__':
    sys.exit(main())

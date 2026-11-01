"""Board self-test of the PYNQ + PUF v1 overlay (keys_rv32 v3 ASCII log via mailbox).

Run on the PYNQ board from a repository copy, with the candidate files present:
  sudo -E python3 board/vivado_zynq7000_xc7z020_pynq_puf/board_test.py \
      --candidate board/vivado_zynq7000_xc7z020_pynq_puf/candidate \
      --out data/pynq_puf/board_<date>
Every run: hold CPU reset (flushes the mailbox), release it, collect ASCII until
DONE. PASS needs the firmware line "PASS key subsystem: enroll + reconstruct stable",
no FAIL, no mailbox overflow and the PFU1 identity. Exit code 0 only if all runs PASS.
No simulation fallback. The 3-mode PYNQ service is NOT in this overlay.
"""
import argparse
import datetime
import hashlib
import json
import platform
import re
import sys
import time
from pathlib import Path

CTL_ID = 0x31554650      # "PFU1"
MBOX_ID = 0x4D424F58
PASS_LINE = b'PASS key subsystem: enroll + reconstruct stable'


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def one_run(ctl, mb, timeout):
    raw = bytearray()
    ctl.write(0, 1)          # hold CPU reset; also flushes mailbox FIFOs
    time.sleep(0.01)
    ctl.write(0, 0)
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        st = mb.read(0x0c)
        if st & (1 << 18):
            raise RuntimeError('mailbox RX overflow')
        if st & 0xffff:
            raw.append(mb.read(4) & 255)
            if raw.endswith(b'DONE\r\n') or raw.endswith(b'DONE\n'):
                return raw
            # keys_rv32 ends its final failure branch with a bare FAIL line (no DONE)
            if raw.endswith(b'\nFAIL\r\n') or raw.endswith(b'\nFAIL\n'):
                return raw
        else:
            time.sleep(0.001)
    raise TimeoutError('no DONE before deadline')


def parse(raw):
    text = raw.decode('ascii', errors='backslashreplace')
    q = [int(x) for x in re.findall(r'quality=(\d+)', text)]
    dna = re.search(r'DNA\s*:\s*([0-9a-fA-F]+)', text)
    return {'qualities': q, 'dna': dna.group(1) if dna else None,
            'pass_line': PASS_LINE in raw, 'fail_seen': b'FAIL' in raw}


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('--candidate', required=True, type=Path, help='directory with pynq_puf.bit/.hwh/manifest.json')
    p.add_argument('--out', required=True, type=Path)
    p.add_argument('--runs', type=int, default=1, help='reset/self-test repetitions in this power-on session')
    p.add_argument('--timeout', type=float, default=20.0, help='seconds per run')
    a = p.parse_args()
    if a.runs < 1 or a.timeout <= 0:
        p.error('--runs >= 1 and --timeout > 0 required')
    a.out.mkdir(parents=True, exist_ok=False)
    bit, hwh, man = a.candidate / 'pynq_puf.bit', a.candidate / 'pynq_puf.hwh', a.candidate / 'manifest.json'
    result = {'timestamp': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'kind': 'physical_board_pynq_puf_v1_selftest', 'host': platform.platform(),
              'python': sys.version, 'command': sys.argv, 'runs': [], 'status': 'FAIL', 'exit_code': 1,
              'timing_signoff_ro_domain': False, 'cross_power_cycle': 'not_measured'}
    try:
        manifest = json.loads(man.read_text())
        exp = manifest['artifacts']
        result.update(bit_sha256=digest(bit), hwh_sha256=digest(hwh), manifest_sha256=digest(man))
        if result['bit_sha256'] != exp['pynq_puf.bit']['sha256'] or result['hwh_sha256'] != exp['pynq_puf.hwh']['sha256']:
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
        result.update(control_id=ctl.read(8), control_version=ctl.read(12), mailbox_id=mb.read(0x1c))
        if result['control_id'] != CTL_ID or result['mailbox_id'] != MBOX_ID:
            raise RuntimeError('wrong overlay identity (expected PFU1 + MBOX)')
        result['fclk0_mhz'] = float(pynq.Clocks.fclk0_mhz)
        if abs(result['fclk0_mhz'] - 100) > 0.5:
            raise RuntimeError('FCLK0 must be 100 MHz, got %s' % result['fclk0_mhz'])
        all_ok = True
        for i in range(a.runs):
            entry = {'index': i}
            raw = bytearray()
            try:
                raw = one_run(ctl, mb, a.timeout)
                entry.update(parse(raw))
                entry['status'] = 'PASS' if entry['pass_line'] and not entry['fail_seen'] else 'FAIL'
            except Exception as e:  # keep the partial log of this run
                entry.update(parse(raw), status='FAIL', error=repr(e))
            (a.out / ('uart_run%02d.txt' % i)).write_bytes(bytes(raw))
            entry['final_control_status'] = ctl.read(4)
            all_ok &= entry['status'] == 'PASS'
            result['runs'].append(entry)
            print('run', i, entry['status'], 'quality', entry.get('qualities'), flush=True)
        dnas = {r.get('dna') for r in result['runs']}
        result['dna_consistent'] = len(dnas) == 1 and None not in dnas
        if all_ok and result['dna_consistent']:
            result.update(status='PASS', exit_code=0)
    except Exception as e:
        result['error'] = repr(e)
    finally:
        (a.out / 'result.json').write_text(json.dumps(result, indent=2, default=str) + '\n', encoding='utf-8')
    print(result['status'], a.out)
    return result['exit_code']


if __name__ == '__main__':
    sys.exit(main())

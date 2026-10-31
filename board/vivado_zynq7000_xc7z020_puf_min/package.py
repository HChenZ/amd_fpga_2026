"""把 PUF-MIN 的实现产物打包成 candidate（bit + hwh + manifest + 报告）。

只读实现证据目录，不重跑 Vivado。门禁数值从 gate.txt 读，不在这里重新解释；
如果 gate.txt 说门禁没过，直接拒绝打包。
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import sys

ROOT = Path(__file__).resolve().parents[2]
BOARD = Path(__file__).resolve().parent


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def parse_kv(path):
    out = {}
    for line in Path(path).read_text(encoding='utf-8').splitlines():
        if '=' in line:
            key, _, value = line.partition('=')
            out[key.strip()] = value.strip()
    return out


def newest(pattern):
    hits = sorted(p for p in (ROOT / 'data/advanced/puf_min').glob(pattern) if p.is_dir())
    if not hits:
        raise SystemExit('no directory matches %s' % pattern)
    return hits[-1]


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--evidence', help='implementation evidence dir (default: newest impl_*)')
    ap.add_argument('--candidate', default=str(BOARD / 'candidate'))
    a = ap.parse_args()

    ev = Path(a.evidence) if a.evidence else newest('impl_*')
    gate = parse_kv(ev / 'gate.txt')
    bit = ev / 'puf_min.bit'
    hwh = ev / 'puf.hwh'
    for p in (bit, hwh, ev / 'gate.txt'):
        if not p.is_file():
            raise SystemExit('missing implementation artifact: %s' % p)

    # 门禁复述检查：不能把 gate.txt 里的失败值打包成"通过"
    problems = []
    if float(gate['wns_ns']) < 0.5:
        problems.append('wns_ns=%s < 0.5' % gate['wns_ns'])
    if float(gate['whs_ns']) < 0:
        problems.append('whs_ns=%s < 0' % gate['whs_ns'])
    if int(gate['drc_error']) != 0:
        problems.append('drc_error=%s' % gate['drc_error'])
    if int(gate['netlist_29_160_impl']) != 0 or int(gate['netlist_29_160_synth']) != 0:
        problems.append('netlist_29_160 impl=%s synth=%s'
                        % (gate['netlist_29_160_impl'], gate['netlist_29_160_synth']))
    if int(gate['ddr_top_ports']) == 0 or int(gate['fixed_io_top_ports']) == 0:
        problems.append('DDR/FIXED_IO top ports missing')
    if int(gate['ro_luts']) != 1280 or int(gate['ro_luts_in_pblock']) != 1280:
        problems.append('ro_luts=%s in_pblock=%s' % (gate['ro_luts'], gate['ro_luts_in_pblock']))
    if not gate.get('post_route_phys_opt_design', '').startswith('NOT_RUN'):
        problems.append('post-route phys_opt_design was used; the gate must not depend on it')
    if problems:
        raise SystemExit('implementation gate not satisfied: %s' % '; '.join(problems))

    cand = Path(a.candidate)
    cand.mkdir(parents=True, exist_ok=False)
    shutil.copy2(bit, cand / 'puf_min.bit')
    shutil.copy2(hwh, cand / 'puf_min.hwh')
    (cand / 'reports').mkdir()
    for p in sorted(ev.iterdir()):
        if p.suffix in ('.rpt', '.txt', '.xdc', '.tsv') and p.is_file():
            shutil.copy2(p, cand / 'reports' / p.name)

    context = (ev / 'context.txt').read_text(encoding='utf-8')
    manifest = {
        'schema': 'puf_min_candidate_v1',
        'classification': 'STRUCTURAL_ONLY_NO_RO_TIMING_SIGNOFF',
        'timing_signoff': False,
        'ro_min_period_ns': None,
        'ro_bound_source': 'not_measured',
        'board': 'not_measured',
        'size_class': 'minimal closed loop (PS AXI-Lite -> puf_min_top); no CPU/BRAM/AEAD/helper/mailbox in PL',
        'abi': 'PUF-MIN v1',
        'register_window': {'base': '0x40000000', 'range_bytes': 4096, 'instance': 'puf_core'},
        'id': '0x4E494D50',
        'version': 1,
        'clock_hz': 100000000,
        'clock_ports': 1,
        'phys_opt_design': 'NOT_RUN (post-route)',
        'post_place_phys_opt_design': 'ENABLED (Vivado default step)',
        'wns_ns': float(gate['wns_ns']),
        'whs_ns': float(gate['whs_ns']),
        'drc_error': int(gate['drc_error']),
        'drc_critical_warning': int(gate['drc_critical_warning']),
        'netlist_29_160': {'impl_1': int(gate['netlist_29_160_impl']),
                           'synth_1': int(gate['netlist_29_160_synth'])},
        'ddr_top_ports': int(gate['ddr_top_ports']),
        'fixed_io_top_ports': int(gate['fixed_io_top_ports']),
        'ro_luts': int(gate['ro_luts']),
        'ro_luts_in_pblock': int(gate['ro_luts_in_pblock']),
        'ring_count': 256,
        'raw_readable': True,
        'confidentiality': 'none: RAW is readable by any PS master of this window',
        'secure_boot': False,
        'anti_rollback': False,
        'entropy_claim': 'none',
        'inter_hd': 'not_measured',
        'evidence_directory': str(ev.relative_to(ROOT)).replace('\\', '/'),
        'context_txt': context,
    }
    manifest['artifact_sha256'] = {
        p.relative_to(cand).as_posix(): digest(p)
        for p in sorted(cand.rglob('*')) if p.is_file()
    }
    (cand / 'manifest.json').write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    print('PUF_MIN_CANDIDATE', cand)
    print('sha256', manifest['artifact_sha256']['puf_min.bit'])
    return 0


if __name__ == '__main__':
    sys.exit(main())

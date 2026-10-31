"""交付前校验：candidate 哈希、实现门禁字段、仿真证据、明确的不宣称清单。

退出码 0 表示全部通过；任何一项不成立 exit 1 并把明细写进 checks.json。
"""
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
BOARD = Path(__file__).resolve().parent
OUT = ROOT / 'data/advanced/puf_min'


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def newest_dir(pattern, base=None):
    hits = sorted(p for p in (base or OUT).glob(pattern) if p.is_dir())
    return hits[-1] if hits else None


def main():
    candidate = BOARD / 'candidate'
    checks = {}
    details = {}

    manifest_path = candidate / 'manifest.json'
    checks['candidate_manifest_exists'] = manifest_path.is_file()
    if not checks['candidate_manifest_exists']:
        details['error'] = 'candidate/manifest.json 不存在；先跑 package.py'
        write(checks, details)
        return 1
    manifest = json.loads(manifest_path.read_text(encoding='utf-8'))

    checks['candidate_hashes'] = all(
        sha(candidate / p) == h for p, h in manifest['artifact_sha256'].items())
    checks['schema'] = manifest['schema'] == 'puf_min_candidate_v1'
    checks['classification_explicit'] = manifest['classification'] == 'STRUCTURAL_ONLY_NO_RO_TIMING_SIGNOFF'
    checks['no_timing_signoff_claim'] = (manifest['timing_signoff'] is False
                                         and manifest['ro_min_period_ns'] is None
                                         and manifest['ro_bound_source'] == 'not_measured')
    checks['board_not_run'] = manifest['board'] in ('not_measured', 'NOT_RUN')
    checks['no_confidentiality_claim'] = manifest['raw_readable'] is True and \
        manifest['secure_boot'] is False and manifest['anti_rollback'] is False
    checks['impl_gates'] = (manifest['wns_ns'] >= 0.5 and manifest['whs_ns'] >= 0
                            and manifest['drc_error'] == 0
                            and manifest['netlist_29_160'] == {'impl_1': 0, 'synth_1': 0}
                            and manifest['ddr_top_ports'] > 0
                            and manifest['fixed_io_top_ports'] > 0
                            and manifest['ro_luts'] == 1280
                            and manifest['ro_luts_in_pblock'] == 1280
                            and manifest['phys_opt_design'].startswith('NOT_RUN'))

    icarus = newest_dir('icarus_*')
    checks['icarus_evidence'] = bool(icarus) and (icarus / 'results.json').is_file() and \
        json.loads((icarus / 'results.json').read_text(encoding='utf-8'))['passed']
    details['icarus'] = str(icarus.relative_to(ROOT)).replace('\\', '/') if icarus else None

    xsim = newest_dir('xsim_*')
    checks['xsim_evidence'] = bool(xsim) and (xsim / 'result.txt').is_file()
    details['xsim'] = str(xsim.relative_to(ROOT)).replace('\\', '/') if xsim else None

    host = newest_dir('host_tests_*')
    host_ok = bool(host) and (host / 'status.txt').is_file() and \
        'host_unittest_exit=0' in (host / 'status.txt').read_text(encoding='utf-8')
    checks['host_unit_tests'] = host_ok
    details['host_tests'] = str(host.relative_to(ROOT)).replace('\\', '/') if host else None

    ev = ROOT / manifest['evidence_directory']
    checks['evidence_directory_present'] = ev.is_dir()
    details['evidence_directory'] = manifest['evidence_directory']

    result = {'checks': checks, 'details': details, 'passed': all(checks.values()),
              'board': 'NOT_RUN', 'timing_signoff': False}
    write(checks, details, result)
    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0 if result['passed'] else 1


def write(checks, details, result=None):
    result = result or {'checks': checks, 'details': details, 'passed': all(checks.values()),
                        'board': 'NOT_RUN', 'timing_signoff': False}
    (BOARD / 'delivery_checks.json').write_text(
        json.dumps(result, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')


if __name__ == '__main__':
    sys.exit(main())

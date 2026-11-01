"""Verify the editable PUF3 report against existing evidence; never run hardware flows.

--generate refreshes appendix excerpts from their original files.
--pdf additionally checks the compiled text and lossless screenshot embedding.
"""
import argparse
import hashlib
import json
import re
import statistics
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = next(p for p in HERE.parents if (p / 'AGENTS.md').is_file())
CAND = ROOT / 'board/vivado_zynq7000_xc7z020_pynq_puf3/candidate'
RESULT = ROOT / 'data/pynq_puf3/notebook_20261031_114512/result.json'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--generate', action='store_true')
    ap.add_argument('--pdf', type=Path)
    ap.add_argument('--report-dir', type=Path, default=HERE)
    ap.add_argument('--output', type=Path, default=HERE / 'validation/evidence_check.json')
    args = ap.parse_args()
    report = args.report_dir.resolve()
    checks, inputs, excerpts = [], {}, {}

    def check(name, ok):
        checks.append({'name': name, 'status': 'PASS' if ok else 'FAIL'})

    def text(path):
        path = Path(path)
        inputs[path.relative_to(ROOT).as_posix()] = sha(path)
        return path.read_text(encoding='utf-8-sig')

    def load(path):
        return json.loads(text(path))

    def excerpt(name, value):
        body = value if isinstance(value, str) else json.dumps(value, ensure_ascii=False, indent=2)
        excerpts[name] = '\\begin{codeblock}\n' + body.strip() + '\n\\end{codeblock}\n'

    def selected(path, pattern):
        return '\n'.join(line for line in text(path).splitlines() if re.search(pattern, line))

    d, m = load(RESULT), load(CAND / 'manifest.json')
    check('board PASS and real PUF3 identity', d['status'] == 'PASS' and d['exit_code'] == 0
          and d['service']['simulated'] is False and d['service']['selftest_mask'] == 7
          and d['service']['firmware_id'] == 'pynq-svc-puf3' and d['control_id'] == '0x33465150')
    for line in text(CAND / 'sha256sums.txt').splitlines():
        expected, name = line.split(maxsplit=1)
        p = CAND / name.strip()
        inputs[p.relative_to(ROOT).as_posix()] = sha(p)
        check('candidate sha256: ' + p.name, sha(p) == expected)
    for name, value in m['artifacts'].items():
        p = CAND / name
        check('manifest artifact: ' + name, sha(p) == value['sha256'] and p.stat().st_size == value['bytes'])
    excluded = set(m['excluded_from_build'])
    for name, expected in m['source_sha256'].items():
        if Path(name).suffix in ['.v', '.vh', '.xdc', '.c', '.h'] and name not in excluded and not name.endswith('_tb.v'):
            p = ROOT / name
            raw = p.read_bytes()
            inputs[name] = sha(p)
            check('recorded RTL/firmware input: ' + name, expected in [sha(p),
                  hashlib.sha256(raw.replace(b'\r\n', b'\n')).hexdigest()])
    for key, name in [('bit_sha256', 'pynq_puf3.bit'), ('hwh_sha256', 'pynq_puf3.hwh'),
                      ('manifest_sha256', 'manifest.json')]:
        check('board binding: ' + key, d[key] == sha(CAND / name))
    check('RO/cross-power limitations retained', d['timing_signoff_ro_domain'] is False
          and d['cross_power_cycle'] == 'not_measured')
    excerpt('puf3_identity', {k: m[k] for k in ['source_commit', 'source_dirty', 'part', 'top',
            'vivado', 'control_id', 'hardware_validation', 'artifacts']})

    kat = d['sections']['kat']
    expected_cases = {1 + pt * 33 + ad for pt in range(17) for ad in range(17)}
    for name, k in kat.items():
        check('capacity KAT: ' + name, k['kat_pass'] == k['tag_reject'] == len(k['cases']) == 289
              and set(k['cases']) == expected_cases)
    excerpt('puf3_kat', {name: {'kat_pass': k['kat_pass'], 'tag_reject': k['tag_reject'],
                              'case_count': len(k['cases'])} for name, k in kat.items()})
    b = d['sections']['benchmark']
    check('benchmark inputs', b['kat'] == 529 and b['warmup'] == 5 and b['repetitions'] == 30)
    medians, walls, rows = {}, {}, []
    for name, ops in b['modes'].items():
        medians[name], walls[name] = {}, {}
        for op, v in ops.items():
            raw = v['raw_cycles']
            med = statistics.median(raw)
            medians[name][op] = med
            walls[name][op] = v['wall_ns_summary']['median'] / 1e6
            check('raw cycles: ' + name + '/' + op, len(raw) == 30 and all(type(x) is int and x > 0 for x in raw)
                  and len(set(raw)) == 1 and med == v['summary']['median']
                  and min(raw) == v['summary']['min'] and max(raw) == v['summary']['max'])
            check('wall summary scope: ' + name + '/' + op, v['wall_ns_summary']['n'] == 30
                  and 'raw_wall_ns' not in v)
            rows.append(f'{name}/{op}: n={len(raw)} median_cycles={med:g}; cycles/B={med / 16:.4f}; '
                        f'median_wall_ms(summary)={walls[name][op]:.7f}')
    for name in ['hw', 'ise']:
        for op in ['encrypt', 'decrypt']:
            speed = round(medians['sw'][op] / medians[name][op], 3)
            check('speedup: ' + name + '/' + op, speed == b['speedup_median_vs_sw'][name][op])
            rows.append(f'{name}/{op} speedup={speed:.3f}')
    excerpt('puf3_benchmark', '\n'.join(rows))
    clk = d['clock']
    cm = clk['measurement']
    mhz = (cm['mcycle'][1] - cm['mcycle'][0]) / (cm['host_s'][1] - cm['host_s'][0]) / 1e6
    check('clock recomputed from two samples', round(mhz, 4) == clk['fclk0_mhz_measured_mcycle'] == 99.9723)
    puf = d['sections']['puf']
    check('PUF functional gates', puf['enroll_quality'] == 127 and puf['reconstructs_stable'] == 5
          and all(puf[k] is True for k in ['caller_key_rejected_under_puf_key',
                                         'same_ciphertext_after_reconstruct', 'kat_restored_after_hwkey_off']))
    excerpt('puf3_puf', {'clock': {k: clk[k] for k in ['fclk0_mhz_register_derived',
            'fclk0_mhz_measured_mcycle', 'pynq_clocks_fclk0_mhz', 'measurement']},
            'functional': {k: v for k, v in puf.items() if k not in ['frames', 'dna', 'puf_key_ciphertext_tag']},
            'timing_signoff_ro_domain': d['timing_signoff_ro_domain'], 'cross_power_cycle': d['cross_power_cycle']})

    rpt = CAND / 'reports'
    timing = text(rpt / 'timing_summary.rpt')
    match = re.search(r'^\s+(0\.104)\s+(0\.000)\s+0\s+(73907)\s+(0\.041)\s+(0\.000)\s+0\s+73907', timing, re.M)
    check('post-route WNS/TNS/WHS/THS/endpoints', match is not None and 'pynq_puf3_wrapper' in timing)
    excerpt('puf3_timing', '\n'.join(line for line in timing.splitlines() if re.search(
        r'^\| (Tool Version|Date|Design |Device|Speed File|Design State)|^\s+(WNS\(ns\)|0\.104)|^clk_fpga_0|^  ro_clk|^ro_clk +clk|^clk_fpga_0 +ro_clk|^TIMING-17', line)))
    resources = selected(rpt / 'utilization.rpt', r'^\| (Tool Version|Date|Design |Device)|^\| (Slice LUTs |Slice Registers |Block RAM Tile |DSPs )')
    for label, number in [('Slice LUTs', '18674'), ('Slice Registers', '32002'), ('Block RAM Tile', '34.5'), ('DSPs', '4')]:
        check('resource: ' + label, re.search(r'\| ' + label + r'\s*\|\s*' + re.escape(number) + r'\s*\|', resources) is not None)
    excerpt('puf3_resources', resources)
    drc = text(rpt / 'drc.rpt')
    check('DRC summary distinct from methodology', 'Checks found: 824' in drc
          and not re.search(r'\|\s*(?:Critical Warning|Error)\s*\|', drc))
    excerpt('puf3_drc', '\n'.join(line for line in drc.splitlines()[:42] if re.search(r'^\| |Checks found', line)))
    cover = text(rpt / 'check_timing_counts.txt')
    ro = text(rpt / 'ro_corner_sta.txt')
    check('RO uncovered domain and negative slacks', all(v in cover for v in ['5120', '15360', '256'])
          and all(v in ro for v in ['-0.478', '-0.552', '-0.598', '-0.427']))
    excerpt('puf3_ro', '\n'.join(x for x in cover.splitlines() if any(v in x for v in ['5120', '15360', '256']))
            + '\n' + '\n'.join(x for x in ro.splitlines() if re.search(r'^FAST_MIN|^SLOW_MAX|^20-bit|^==|ro_osc1 intra', x)))
    cs, fw = load(rpt / 'cosim_summary.json'), load(rpt / 'firmware_build.json')
    check('cosim and firmware binding', cs['result'] == 'PASS' and cs['steps'] == 54
          and cs['normal_pass'] and cs['mutant_autolock_detected']
          and cs['firmware_bin_sha256'] == sha(CAND / 'pynq_svc_puf.bin'))
    check('firmware custom0 count and build status', fw['custom0']['all_opcode_0x0b'] == 22
          and all(r['exit_code'] == 0 for r in fw['records']))
    excerpt('puf3_cosim', {'cosim': {k: cs[k] for k in ['result', 'steps', 'normal_pass',
             'mutant_autolock_detected', 'simulation_only']}, 'custom0': fw['custom0'], 'size': fw['size']})
    text(rpt / 'context.txt')

    gate = load(ROOT / 'data/pynq/error_gate_20261031_112812/pynq_board_error_gate.json')
    check('legacy error gate identity', gate['service_initial']['firmware_id'] == 'pynq-svc-v1'
          and len(gate['checks']) == 9 and all(c['status'] == 'PASS' for c in gate['checks'])
          and gate['reset_count'] == 7)
    excerpt('legacy_error_gate', 'firmware_id=pynq-svc-v1 (NOT PUF3)\n' + '\n'.join(
            f"{c['name']}: {c['status']}" for c in gate['checks']))
    old = ROOT / 'build/reports/pynq_final_20261028'
    old_results = {}
    for name in ['smoke', 'regression_final']:
        item = load(old / name / 'summary.json')
        old_results[name] = {k: item[k] for k in ['source_head', 'counts', 'elapsed_s', 'status']}
    excerpt('legacy_regression', old_results)
    host = {}
    for name in ['host_validation', 'reference_gate', 'failure_contract', 'failure_contract_original_reproduction']:
        item = load(ROOT / 'data/ascon/results' / (name + '.json'))
        host[name] = {k: item['summary'][k] for k in ['passed', 'failed', 'exit_code']}
    excerpt('host_validation', host)
    board = ROOT / 'data/ascon/results/board'
    excerpt('legacy_board', selected(board / 'uart_20261026_sw_and_ise.txt', r'KAT|cycles|enc |dec |tamper|===')
            + '\n' + selected(board / 'uart_20261027_mmio.txt', r'KAT|latency|full MMIO|reject|roundtrip|===') )
    hist = ROOT / 'build/local/proj_backup_first_time_20261027/first_time.runs/impl_1/top_pl_bram_timing_summary_routed.rpt'
    excerpt('legacy_timing', selected(hist, r'^\| (Tool Version|Date|Design |Device|Speed File)|^\s+WNS\(ns\)|^\s+0\.087'))
    excerpt('legacy_puf', selected(board / 'uart_20261027_keys3.txt', r'^#|^\[|STATUS|FAIL|PASS'))
    text(ROOT / 'data/ascon/results/strategy_sweep_20261017/strategy_sweep_summary.json')
    text(ROOT / 'data/pynq/board_20261028/pynq_board_full.json')
    nb = load(ROOT / 'src/pynq_puf3/pynq_puf3_board_test.ipynb')
    code_cells = [c for c in nb['cells'] if c['cell_type'] == 'code']
    check('executed PUF3 notebook archived', all(c['execution_count'] is not None for c in code_cells)
          and 'notebook_20261031_114512' in json.dumps(nb))
    text(RESULT.parent / 'mailbox_log.txt')
    ise_dir = ROOT / 'data/ascon/results/ise_screenshot_20261031'
    ise = load(ise_dir / 'summary.json')
    ise_log = text(ise_dir / 'simulate.log')
    text(ise_dir / 'verdict.txt')
    check('ISE screenshot self-check', ise['status'] == 'PASS' and ise['checks'] == 1502
          and ise['errors'] == 0 and ise['finish_ns'] == 37390
          and 'SUMMARY ISE checks=1502 errors=0' in ise_log)
    for name, expected in ise['source_sha256'].items():
        check('ISE screenshot source: ' + name, sha(ROOT / name) == expected)
        inputs[name] = sha(ROOT / name)
    for name in ['xvlog.log', 'elaborate.log']:
        text(ise_dir / name)
    preservation = load(ise_dir / 'project_preservation.json')
    check('ISE simulation preserves candidate', all(preservation['candidate_hashes_unchanged'].values())
          and preservation['sources_1_entries_unchanged'] and preservation['constrs_1_entries_unchanged'])
    excerpt('ise_screenshot_validation', ise_log + '\n' + json.dumps(
        {k: ise[k] for k in ['status', 'evidence_kind', 'tool', 'simulation_top', 'checks', 'errors', 'finish_ns', 'scope']}, indent=2))
    pictures = {'vivado_block_design.png': '0bd4c00d440e6383c67189dfdfd83e5fc6279eb30ec67ee4a6b540aa3e9201c6',
                'vivado_implemented_design.png': '7931afa35924144401781e4f1529f6bca8d9d5b585a5a7dd0c3b52d96c023e91',
                'vivado_utilization.png': '1047372c228582332d7d1c4abcd6cb79dcfa2d56fffb9dec91173f2c4952b2cf',
                'vivado_ise_waveform.png': '4fef2cc0498695c3c9d8a11f3ad4bfd0924e2433d8f3914090eee160f06ad4ac'}
    for name, digest in pictures.items():
        p = report / 'figs' / name
        check('original screenshot: ' + name, sha(p) == digest)
    excerpt('screenshots', '\n'.join(name + '\nSHA-256 ' + digest for name, digest in pictures.items()))

    # Check the editable primary tables independently of the appendix generator.
    def source(name):
        return (report / name).read_text(encoding='utf-8').replace('\\allowbreak{}', '')

    ch = source('chapters/ch04.tex')
    def table(n):
        section = ch.split('\\label{tab:' + n + '}')[1].split('\\end{longtable}')[0]
        return section.split('\\endhead')[1]
    for name, label in [('sw', 'SW'), ('hw', 'HW/MMIO'), ('ise', 'ISE')]:
        e, f = medians[name]['encrypt'], medians[name]['decrypt']
        se, sf = medians['sw']['encrypt'] / e, medians['sw']['decrypt'] / f
        expected = f'{label} & {e:g} & {e/16:.4f} & {se:.3f}$\\times$ & {f:g} & {f/16:.4f} & {sf:.3f}$\\times$'
        check('report table 3-13: ' + name, expected in table('3-13'))
        expected = f'{label} & {walls[name]["encrypt"]:.3f} & {walls[name]["decrypt"]:.3f}'
        check('report table 3-14: ' + name, expected in table('3-14'))
    intro = source('chapters/ch02.tex')
    for label, op in [('加密 cycles', 'encrypt'), ('解密 cycles', 'decrypt')]:
        check('report table 1-1: ' + op, label + ' & ' + ' & '.join(f'{medians[n][op]:g}' for n in ['sw','hw','ise']) in intro)
    check('report table 1-1: wall', '加密 PS 墙钟 ms & ' + ' & '.join(f'{walls[n]["encrypt"]:.3f}' for n in ['sw','hw','ise']) in intro)
    abstract = source('chapters/ch01.tex')
    for claim in ['21862/1369/3895', '22562/1213/4288', '99.9723', '18674', '32002', '+0.104', '+0.041']:
        check('abstract: ' + claim, claim in abstract)
    for name in ['ch01', 'ch02', 'ch03', 'ch04', 'ch05']:
        content = source('chapters/' + name + '.tex')
        check('no obsolete current benchmark: ' + name, not re.search(r'23342|24005|16\.221|5\.843|14269|19691', content))
    for path in (report / 'figs').glob('*.tex'):
        content = path.read_text(encoding='utf-8').replace('\\,', '').replace('\\allowbreak{}', '')
        check('no obsolete current figure data: ' + path.name,
              not re.search(r'23342|1439|3995|24005|1388|4385|16\.221|5\.843|14269|19691|pynq\\_wrapper', content))
    check('all requested figure placeholders filled', all('\\fignone{' not in source('chapters/' + n + '.tex')
          for n in ['ch01', 'ch02', 'ch03', 'ch04', 'ch05', 'app03']))

    for name, content in excerpts.items():
        path = report / 'evidence' / (name + '.tex')
        if args.generate:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding='utf-8', newline='\n')
        check('appendix synchronized: ' + name, path.is_file() and path.read_text(encoding='utf-8') == content)

    if args.pdf:
        import pymupdf
        from PIL import Image
        with pymupdf.open(args.pdf) as pdf:
            pdf_text = ''.join(p.get_text() for p in pdf)
            compact = re.sub(r'\s+', '', pdf_text)
            for claim in ['21862', '1369', '3895', '22562', '1213', '4288', '99.9723', '18674', '32002', 'RO计数器域未签核']:
                check('PDF content: ' + claim, claim in compact)
            check('PDF no unresolved refs', '??' not in pdf_text and '\ufffd' not in pdf_text)
            check('PDF no old current benchmark', not re.search(r'23342|1439|3995|24005|1388|4385', compact))
            image_hashes = [i['digest'].hex() for p in pdf for i in p.get_image_info(hashes=True)]
            for name in pictures:
                with Image.open(report / 'figs' / name) as img:
                    digest = hashlib.md5(img.convert('RGB').tobytes()).hexdigest()
                check('PDF original screenshot pixels: ' + name, digest in image_hashes)
                check('PDF screenshot appears exactly once: ' + name, image_hashes.count(digest) == 1)
            pdf_info = {'pages': len(pdf), 'sha256': sha(args.pdf)}
    else:
        pdf_info = None
    result = {'status': 'PASS' if all(c['status'] == 'PASS' for c in checks) else 'FAIL',
              'scope': 'existing evidence and report consistency; no new board/synthesis runs',
              'board_result': RESULT.relative_to(ROOT).as_posix(), 'inputs_sha256': inputs,
              'checks': checks, 'pdf': pdf_info,
              'limitations': ['PUF3 wall-time raw samples not archived', 'RO counters not signed off',
                              'PUF3 full error-gate matrix not run', 'cross-power/PVT/BER/entropy not measured']}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f"{result['status']}: {sum(c['status']=='PASS' for c in checks)}/{len(checks)} checks -> {args.output}")
    for c in checks:
        if c['status'] != 'PASS':
            print('FAIL:', c['name'])
    return 0 if result['status'] == 'PASS' else 1


if __name__ == '__main__':
    raise SystemExit(main())

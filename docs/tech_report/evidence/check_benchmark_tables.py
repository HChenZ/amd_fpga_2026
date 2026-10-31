#!/usr/bin/env python
"""D02：从原始数据重算当前 PYNQ 性能/资源/时序数值，并核对 report.md 中对应表格行与关键语句。

只读报告源，不修改；结果写入 docs/tech_report/validation/benchmark_tables_check.json。
任一数值不一致或报告中缺少对应行时 exit 1。
"""
from __future__ import annotations

import datetime
import hashlib
import json
import re
import statistics
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_evidence import BENCH, ROOT, RUN

REPORT = ROOT / 'docs/tech_report/report.md'
OUT = ROOT / 'docs/tech_report/validation/benchmark_tables_check.json'
LABEL = {'sw': 'SW', 'hw': 'HW/MMIO', 'ise': 'ISE'}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rel(path):
    return path.relative_to(ROOT).as_posix()


def norm(line):
    return re.sub(r'\s+', '', line)


def main():
    report = REPORT.read_text(encoding='utf-8')
    rows = {norm(l) for l in report.splitlines() if l.lstrip().startswith('|')}
    flat = norm(report)
    checks = []

    def expect_row(name, cells, source):
        line = norm('| ' + ' | '.join(cells) + ' |')
        checks.append({'check': name, 'expected_row': '| ' + ' | '.join(cells) + ' |',
                       'source': source, 'status': 'PASS' if line in rows else 'FAIL'})

    def expect_text(name, text, source):
        checks.append({'check': name, 'expected_text': text, 'source': source,
                       'status': 'PASS' if norm(text) in flat else 'FAIL'})

    bench_path = BENCH / 'pynq_warm_benchmark.json'
    b = json.loads(bench_path.read_text(encoding='utf-8'))
    cond = (b['kat'], b['plaintext_bytes'], b['ad_bytes'], b['warmup'], b['repetitions'], b['board_validation'])
    if cond != (529, 16, 0, 5, 30, 'PASS') or b['service']['simulated'] is not False:
        raise SystemExit('Unexpected benchmark conditions: ' + repr(cond))
    med, wall = {}, {}
    for mode in ('sw', 'hw', 'ise'):
        for op in ('encrypt', 'decrypt'):
            d = b['modes'][mode][op]
            if len(d['raw_cycles']) != 30 or len(d['raw_wall_ns']) != 30:
                raise SystemExit(f'{mode}/{op}: sample count != 30')
            med[mode, op] = statistics.median(d['raw_cycles'])
            wall[mode, op] = statistics.median(d['raw_wall_ns']) / 1e6
    src = rel(bench_path)
    for mode in ('sw', 'hw', 'ise'):
        cells = [LABEL[mode]]
        for op in ('encrypt', 'decrypt'):
            c = med[mode, op]
            cells += [f'{c:.0f}', f'{round(c / 16, 3):.3f}', f'{med["sw", op] / c:.3f}×']
        expect_row(f'表 3-13 {LABEL[mode]} cycles/cpb/加速比', cells, src)
        expect_row(f'表 3-14 {LABEL[mode]} PS 墙钟中位', [LABEL[mode], f'{wall[mode, "encrypt"]:.3f}',
                   f'{wall[mode, "decrypt"]:.3f}'], src)
    for mode in ('hw', 'ise'):
        for op in ('encrypt', 'decrypt'):
            recomputed = round(med['sw', op] / med[mode, op], 3)
            stored = b['speedup_median_vs_sw'][mode][op]
            checks.append({'check': f'JSON 加速比 {mode}/{op} 与重算一致', 'recomputed': recomputed,
                           'stored': stored, 'source': src,
                           'status': 'PASS' if recomputed == stored else 'FAIL'})
    expect_text('摘要加密中位 SW/HW/ISE', '{:.0f}/{:.0f}/{:.0f}'.format(
        med['sw', 'encrypt'], med['hw', 'encrypt'], med['ise', 'encrypt']), src)
    expect_text('摘要解密中位 SW/HW/ISE', '{:.0f}/{:.0f}/{:.0f}'.format(
        med['sw', 'decrypt'], med['hw', 'decrypt'], med['ise', 'decrypt']), src)

    util_path = RUN / 'utilization.rpt'
    util = {}
    for line in util_path.read_text(encoding='utf-8', errors='replace').splitlines():
        m = re.match(r'\|\s*(Slice LUTs|Slice Registers|Block RAM Tile|DSPs)\s*\|\s*([\d.]+)\s*\|', line)
        if m and m.group(1) not in util:
            util[m.group(1)] = m.group(2)
    expect_text('实现资源 LUT/FF/BRAM/DSP',
                f'LUT {util["Slice LUTs"]}、FF {util["Slice Registers"]}、BRAM {util["Block RAM Tile"]}、DSP {util["DSPs"]}',
                rel(util_path))

    timing_path = RUN / 'timing.rpt'
    lines = timing_path.read_text(encoding='utf-8', errors='replace').splitlines()
    i = next(n for n, l in enumerate(lines) if 'WNS(ns)' in l and 'TNS(ns)' in l)
    v = lines[i + 2].split()
    wns, tns, fail_ep, total_ep, whs = v[0], v[1], v[2], v[3], v[4]
    expect_row('实现时序 WNS/TNS 行', ['WNS / TNS', f'**+{wns} ns / {float(tns):.0f}**',
               f'setup 失败端点 {fail_ep}/{total_ep}'], rel(timing_path))
    expect_text('实现时序 WHS', f'WHS +{whs} ns', rel(timing_path))

    fails = [c for c in checks if c['status'] != 'PASS']
    record = {
        'task': 'D02', 'status': 'PASS' if not fails else 'FAIL',
        'timestamp': datetime.datetime.now().astimezone().isoformat(timespec='seconds'),
        'scope': '当前 PYNQ 主线：KAT #529 warm benchmark（表 3-13/3-14、摘要）、pynq_wrapper 实现资源与时序；'
                 '历史 PL-only、PUF 原型与 pynq_puf3 数值不在本检查范围（报告未引用 pynq_puf3 数值）',
        'conditions': {'kat': 529, 'plaintext_bytes': 16, 'ad_bytes': 0, 'warmup': 5, 'repetitions': 30,
                       'measurement_scope': b['measurement_scope'], 'wall_time_scope': b['wall_time_scope']},
        'inputs': {rel(p): sha(p) for p in (REPORT, bench_path, util_path, timing_path)},
        'checks': checks, 'failures': len(fails),
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(record, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f'{record["status"]}: {len(checks) - len(fails)}/{len(checks)} checks; written {rel(OUT)}')
    for c in fails:
        print('FAIL', c['check'], c.get('expected_row') or c.get('expected_text') or c)
    sys.exit(0 if not fails else 1)


if __name__ == '__main__':
    main()

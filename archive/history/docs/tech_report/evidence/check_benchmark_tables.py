#!/usr/bin/env python
"""D02：从原始数据重算最终报告（PUF3 主演示）的性能/资源/时序数值，核对 LaTeX 表格行、摘要与 PDF 文本。

独立于报告工程自带的 review_evidence.py 实现，只读报告，不修改。报告位置取 build_evidence.REPORT_DIR，
可用 --report-dir/--pdf 临时覆盖（用于隔离反例）。结果写入 docs/tech_report/validation/benchmark_tables_check.json；
任一数值不一致、报告引用的板测结果不是 PUF3_RUN 或缺少对应行时 exit 1。
"""
from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import re
import statistics
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_evidence import PUF3_RUN, REPORT_DIR, REPORT_PDF, ROOT

CAND = ROOT / 'board/vivado_zynq7000_xc7z020_pynq_puf3/candidate'
OUT = ROOT / 'docs/tech_report/validation/benchmark_tables_check.json'
LABEL = {'sw': 'SW', 'hw': 'HW/MMIO', 'ise': 'ISE'}
RESULT_REF = re.compile(r'data/pynq_puf3/notebook_\d{8}_\d{6}')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rel(path):
    try:
        return path.resolve().relative_to(ROOT).as_posix()
    except ValueError:
        return str(path)


def norm(text):
    return re.sub(r'\s+', '', text.replace('\\allowbreak{}', '').replace('\\,', ''))


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--report-dir', type=Path, default=REPORT_DIR)
    ap.add_argument('--pdf', type=Path)
    ap.add_argument('--output', type=Path, default=OUT)
    args = ap.parse_args()
    report = args.report_dir.resolve()
    pdf_path = (args.pdf or report / REPORT_PDF.relative_to(REPORT_DIR)).resolve()
    checks, inputs = [], {}

    def add(name, ok, **detail):
        checks.append({'check': name, 'status': 'PASS' if ok else 'FAIL', **detail})

    def tex(name):
        path = report / 'chapters' / name
        inputs[rel(path)] = sha(path)
        return path.read_text(encoding='utf-8')

    result_path = PUF3_RUN / 'result.json'
    r = json.loads(result_path.read_text(encoding='utf-8'))
    inputs[rel(result_path)] = sha(result_path)
    b = r['sections']['benchmark']
    if (r['status'], r['exit_code'], r['service']['simulated'], b['kat'], b['warmup'], b['repetitions']) != \
            ('PASS', 0, False, 529, 5, 30):
        raise SystemExit('Unexpected PUF3 board result/conditions')
    for key, name in (('bit_sha256', 'pynq_puf3.bit'), ('hwh_sha256', 'pynq_puf3.hwh'),
                      ('manifest_sha256', 'manifest.json')):
        add(f'板测结果绑定 candidate {name}', r[key] == sha(CAND / name))

    med, wall = {}, {}
    for mode in ('sw', 'hw', 'ise'):
        for op in ('encrypt', 'decrypt'):
            d = b['modes'][mode][op]
            if len(d['raw_cycles']) != 30:
                raise SystemExit(f'{mode}/{op}: sample count != 30')
            med[mode, op] = statistics.median(d['raw_cycles'])
            wall[mode, op] = d['wall_ns_summary']['median'] / 1e6  # 墙钟只有 summary，无原始数组
    speed = {(m, op): med['sw', op] / med[m, op] for m in ('sw', 'hw', 'ise') for op in ('encrypt', 'decrypt')}
    for m in ('hw', 'ise'):
        for op in ('encrypt', 'decrypt'):
            add(f'JSON 加速比 {m}/{op} 与重算一致', round(speed[m, op], 3) == b['speedup_median_vs_sw'][m][op])

    # 报告源中引用的 PUF3 板测目录必须恰好是本脚本使用的 PUF3_RUN。
    refs = set()
    for path in list(report.rglob('*.tex')) + list(report.glob('*.md')) + list(report.glob('*.py')):
        refs |= set(RESULT_REF.findall(path.read_text(encoding='utf-8', errors='replace')))
    add('报告引用的 PUF3 板测目录 = PUF3_RUN', refs == {rel(PUF3_RUN)}, found=sorted(refs), expected=rel(PUF3_RUN))

    ch01, ch02, ch04 = tex('ch01.tex'), tex('ch02.tex'), tex('ch04.tex')
    rows01 = {norm(l) for l in ch02.splitlines() if '&' in l}
    rows04 = {norm(l) for l in ch04.splitlines() if '&' in l}

    def row(name, cells, rows):
        line = ' & '.join(cells) + ' \\\\'
        add(name, norm(line) in rows, expected_row=line)

    x = '$\\times$'
    for op, zh in (('encrypt', '加密'), ('decrypt', '解密')):
        row(f'表 1-1 {zh} cycles', [f'{zh} cycles'] + [f'{med[m, op]:g}' for m in ('sw', 'hw', 'ise')], rows01)
        row(f'表 1-1 {zh}周期加速比', [f'{zh}周期加速比'] + [f'{speed[m, op]:.3f}{x}' for m in ('sw', 'hw', 'ise')], rows01)
    row('表 1-1 加密 PS 墙钟', ['加密 PS 墙钟 ms'] + [f'{wall[m, "encrypt"]:.3f}' for m in ('sw', 'hw', 'ise')], rows01)
    kat = r['sections']['kat']
    row('表 1-1 板级 KAT', ['板级 KAT / 坏 Tag 拒绝'] +
        [f'{kat[m]["kat_pass"]}/{kat[m]["tag_reject"]}' for m in ('sw', 'hw', 'ise')], rows01)
    for m in ('sw', 'hw', 'ise'):
        cells = [LABEL[m]]
        for op in ('encrypt', 'decrypt'):
            cells += [f'{med[m, op]:g}', f'{med[m, op] / 16:.4f}', f'{speed[m, op]:.3f}{x}']
        row(f'表 3-13 {LABEL[m]}', cells, rows04)
        row(f'表 3-14 {LABEL[m]}', [LABEL[m], f'{wall[m, "encrypt"]:.3f}', f'{wall[m, "decrypt"]:.3f}'], rows04)

    util_path = CAND / 'reports/utilization.rpt'
    inputs[rel(util_path)] = sha(util_path)
    util = {}
    for line in util_path.read_text(encoding='utf-8', errors='replace').splitlines():
        mm = re.match(r'\|\s*(Slice LUTs|Slice Registers|Block RAM Tile|DSPs)\s*\|\s*([\d.]+)\s*\|', line)
        if mm and mm.group(1) not in util:
            util[mm.group(1)] = mm.group(2)
    res = f'LUT {util["Slice LUTs"]}、FF {util["Slice Registers"]}、BRAM {util["Block RAM Tile"]}'
    add('第 3 部分资源 LUT/FF/BRAM', norm(res) in norm(ch04), expected_text=res)
    add('第 3 部分 DSP', norm(f'DSP {util["DSPs"]}') in norm(ch04))

    timing_path = CAND / 'reports/timing_summary.rpt'
    inputs[rel(timing_path)] = sha(timing_path)
    lines = timing_path.read_text(encoding='utf-8', errors='replace').splitlines()
    i = next(n for n, l in enumerate(lines) if 'WNS(ns)' in l and 'TNS(ns)' in l)
    wns, tns, fail_ep, total_ep, whs = lines[i + 2].split()[:5]
    row('实现时序 WNS/TNS 行', ['WNS / TNS', f'+{wns} ns / {float(tns):.0f}', 'timing\\_summary.rpt'], rows04)
    add('实现时序失败端点', norm(f'{fail_ep}/{total_ep}') in norm(ch04), expected_text=f'{fail_ep}/{total_ep}')

    claims = ['{:g}/{:g}/{:g}'.format(*(med[m, op] for m in ('sw', 'hw', 'ise'))) for op in ('encrypt', 'decrypt')]
    claims += [util['Slice LUTs'], util['Slice Registers'], f'+{wns}', f'+{whs}', f'{r["clock"]["fclk0_mhz_measured_mcycle"]}']
    for c in claims:
        add(f'摘要含 {c}', norm(c) in norm(ch01))

    # 配套材料（简介、视频脚本、README）必须给出与原始数据一致的关键数字；千分位逗号不影响比对。
    key = ['{:g}/{:g}/{:g}'.format(*(med[m, op] for m in ('sw', 'hw', 'ise'))) for op in ('encrypt', 'decrypt')]
    key += [f'{speed[m, op]:.3f}' for m in ('hw', 'ise') for op in ('encrypt', 'decrypt')]
    key += [util['Slice LUTs'], util['Slice Registers'], f'+{wns}']
    for doc in ('docs/project_intro_20261101.md', 'report/demo_video_script.md', 'README.md'):
        path = ROOT / doc
        inputs[doc] = sha(path)
        body = norm(path.read_text(encoding='utf-8')).replace(',', '')
        need = key if doc != 'README.md' else [key[0], key[2], key[4]]  # 加密三元组、HW/ISE 加密加速比
        for k in need:
            # 简介/视频脚本把三元组拆在行文、表格或口播中，逐项出现即可；README 要求完整三元组
            ok = norm(k) in body or (doc != 'README.md' and all(x in body for x in k.split('/')))
            add(f'配套材料 {doc} 含 {k}', ok)

    pdf_info = {'path': rel(pdf_path), 'sha256': sha(pdf_path)}
    try:
        import pymupdf
    except ImportError:
        pdf_info['text_check'] = 'not_run (pymupdf missing)'
    else:
        with pymupdf.open(pdf_path) as pdf:
            text = re.sub(r'\s+', '', ''.join(p.get_text() for p in pdf))
            pdf_info['pages'] = len(pdf)
        nums = [f'{med[m, op]:g}' for m in ('sw', 'hw', 'ise') for op in ('encrypt', 'decrypt')]
        nums += [f'{speed[m, op]:.3f}' for m in ('hw', 'ise') for op in ('encrypt', 'decrypt')]
        nums += [util['Slice LUTs'], util['Slice Registers']]
        for n in nums:
            add(f'PDF 含 {n}', n in text)
        pdf_info['text_check'] = 'run'
    inputs[rel(pdf_path)] = pdf_info['sha256']

    fails = [c for c in checks if c['status'] != 'PASS']
    record = {
        'task': 'D02', 'status': 'PASS' if not fails else 'FAIL',
        'timestamp': datetime.datetime.now().astimezone().isoformat(timespec='seconds'),
        'report_dir': rel(report), 'pdf': pdf_info, 'board_result': rel(result_path),
        'scope': '最终报告（PUF3 主演示）：表 1-1、表 3-13/3-14、摘要、PUF3 资源与时序、PDF 文本；'
                 '墙钟只有 summary 中位，无原始数组；PYNQ v1/历史 PL-only 历史对照不在本检查范围',
        'conditions': {'kat': 529, 'plaintext_bytes': 16, 'ad_bytes': 0, 'warmup': 5, 'repetitions': 30},
        'inputs': inputs, 'checks': checks, 'failures': len(fails),
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(record, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f'{record["status"]}: {len(checks) - len(fails)}/{len(checks)} checks; written {rel(args.output)}')
    for c in fails:
        print('FAIL', c['check'], c.get('expected_row') or c.get('expected_text') or c.get('found') or '')
    return 0 if not fails else 1


if __name__ == '__main__':
    sys.exit(main())

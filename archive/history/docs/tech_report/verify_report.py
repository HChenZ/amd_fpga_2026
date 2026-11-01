#!/usr/bin/env python
"""核对报告生成一致性、关键数值、证据哈希、图件与上传包；不是硬件复测。"""
from __future__ import annotations

import ast
import hashlib
import json
import re
import statistics
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[1]


def require(condition, message):
    if not condition:
        raise SystemExit('FAIL: ' + message)


def main():
    for name in ('build_report.py', 'build_template_src.py', 'build_site.py', 'build_latex.py',
                 'make_overleaf_zip.py', 'prerender_figs.py', 'evidence/build_evidence.py', 'verify_report.py'):
        ast.parse((ROOT / name).read_text(encoding='utf-8'))
    md = (ROOT / 'report.md').read_text(encoding='utf-8')
    assembled = '\n\n'.join(p.read_text(encoding='utf-8').strip() for p in sorted((ROOT / 'src_template').glob('*.md'))) + '\n'
    assembled = re.sub(r'[ \t]+$', '', assembled, flags=re.M)
    require(md == assembled, 'report.md differs from template sources')
    forbidden = ('289 组随机向量', 'Vivado 2023.2', '指数退避重发', 'build/vivado/build_p0.tcl',
                 'data/ascon/bitstream/', '200 至 300 µs', '16.4 s', '757.7 s', 'DMA', '大消息吞吐')
    for token in forbidden:
        require(token not in md, 'stale claim: ' + token)
    for token in ('23342', '1439', '3995', '24005', '1388', '4385', '14269', '19691',
                  '128/128', '11 月 1 日', '9/9', '未约束', '保密隔离'):
        require(token in md, 'missing evidence boundary/value: ' + token)
    b = json.loads((REPO / 'data/pynq/notebook_20261029_130920/pynq_warm_benchmark.json').read_text(encoding='utf-8'))
    for mode, values in {'sw': (23342, 24005), 'hw': (1439, 1388), 'ise': (3995, 4385)}.items():
        for op, expected in zip(('encrypt', 'decrypt'), values):
            d = b['modes'][mode][op]
            require(len(d['raw_cycles']) == 30 and statistics.median(d['raw_cycles']) == expected,
                    f'raw benchmark mismatch {mode}/{op}')
    for line in (ROOT / 'evidence/sha256sums.txt').read_text(encoding='utf-8').splitlines():
        expected, name = line.split('  ', 1)
        path = REPO / name
        require(path.is_file() and hashlib.sha256(path.read_bytes()).hexdigest() == expected, 'evidence hash: ' + name)
    figures = set(re.findall(r'<span class="figslot" data-src="([0-9A-Z]+-[0-9]+)">', md))
    for fig in figures:
        stem = 'fig_' + fig.replace('-', '_')
        source, pdf = ROOT / 'figs' / (stem + '.tex'), ROOT / 'figs' / (stem + '.pdf')
        require(source.is_file() and pdf.is_file() and pdf.stat().st_mtime >= source.stat().st_mtime,
                'missing/stale figure: ' + fig)
    with zipfile.ZipFile(ROOT / 'latex_project.zip') as z:
        require(z.testzip() is None, 'broken Overleaf zip')
        require('main.tex' in z.namelist(), 'zip lacks main.tex')
        require('header_logo.png' in z.namelist() and z.read('header_logo.png') == (ROOT / 'figs/header_logo.png').read_bytes(),
                'zip header logo missing/stale')
        for n in z.namelist():
            if n.startswith('chapters/') and n.endswith('.tex'):
                require(z.read(n) == (ROOT / 'latex' / n).read_bytes(), 'zip chapter stale: ' + n)
        for fig in figures:
            name = 'figs/fig_' + fig.replace('-', '_') + '.pdf'
            require(name in z.namelist() and z.read(name) == (ROOT / 'figs' / Path(name).name).read_bytes(),
                    'zip figure missing/stale: ' + name)
    import pymupdf
    with pymupdf.open(ROOT / 'latex/main.pdf') as pdf:
        text = ''.join(p.get_text() for p in pdf)
        require(pdf.page_count > 10, 'PDF unexpectedly short')
        for token in ('23342', '1439', '3995', '128/128'):
            require(token in text, 'PDF missing current value: ' + token)
        require('DMA' not in text, 'PDF contains removed scope')
        print('PDF_PAGES', pdf.page_count)
    print(f'PASS: source/output consistency, benchmark, evidence hashes, {len(figures)} figures, PDF and Overleaf zip')


if __name__ == '__main__':
    main()

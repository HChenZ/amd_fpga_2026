#!/usr/bin/env python
"""一键按源重建报告；每步非零即停止，记录版本/日志/输入与产物哈希。"""
from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parent


def digest(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def input_snapshot():
    paths = list((ROOT / 'src').glob('*.md')) + list((ROOT / 'src_template/new').glob('*.md'))
    paths += list((ROOT / 'figs').glob('*.tex')) + [ROOT / 'figs/board_photo.jpg', ROOT / 'figs/header_logo.png']
    paths += [ROOT / n for n in ('build_report.py', 'build_site.py', 'build_latex.py',
              'build_template_src.py', 'make_overleaf_zip.py', 'prerender_figs.py', 'evidence/build_evidence.py')]
    return {p.relative_to(ROOT).as_posix(): digest(p) for p in sorted(paths)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tectonic', default=os.environ.get('TECTONIC'))
    parser.add_argument('--skip-figures', action='store_true', help='仅当已确认所有预渲染图与源一致时使用')
    args = parser.parse_args()
    candidates = [args.tectonic, shutil.which('tectonic'),
        'C:/Users/HXZ/AppData/Local/hermes/cache/scratch/tectonic.exe',
        'C:/wenjian/toolchain/tectonic/tectonic.exe']
    tectonic = next((str(Path(p)) for p in candidates if p and Path(p).is_file()), None)
    if not tectonic:
        raise SystemExit('Tectonic not found; supply --tectonic PATH')
    logdir = ROOT / 'validation' / datetime.datetime.now().strftime('build_%Y%m%d_%H%M%S')
    logdir.mkdir(parents=True)
    record = {'python': sys.version, 'inputs': input_snapshot(), 'steps': [], 'status': 'RUNNING'}
    env = dict(os.environ, PYTHONUTF8='1', TECTONIC=tectonic)

    def run(label, cmd, cwd=ROOT):
        p = subprocess.run(cmd, cwd=cwd, env=env, stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT, encoding='utf-8', errors='replace')
        (logdir / (label + '.log')).write_text(p.stdout, encoding='utf-8')
        record['steps'].append({'label': label, 'command': cmd, 'cwd': str(cwd), 'exit_code': p.returncode})
        print(label, 'exit', p.returncode)
        if p.returncode:
            print(p.stdout[-3000:])
            raise RuntimeError(label + ' failed')

    try:
        run('tool_version', [tectonic, '--version'])
        for name, script in [('evidence', 'evidence/build_evidence.py'),
                             ('template', 'build_template_src.py'), ('html', 'build_site.py')]:
            run(name, [sys.executable, '-X', 'utf8', str(ROOT / script)])
        if not args.skip_figures:
            run('figures', [sys.executable, '-X', 'utf8', str(ROOT / 'prerender_figs.py')])
        run('latex', [sys.executable, '-X', 'utf8', str(ROOT / 'build_latex.py')])
        run('pdf', [tectonic, '-X', 'compile', 'main.tex', '--keep-logs'], ROOT / 'latex')
        run('overleaf_zip', [sys.executable, '-X', 'utf8', str(ROOT / 'make_overleaf_zip.py')])
        run('audit', [sys.executable, '-X', 'utf8', str(ROOT / 'verify_report.py')])
        if record['inputs'] != input_snapshot():
            raise RuntimeError('Source changed during build; preserve changes and rebuild, do not release mixed outputs')
        record['outputs'] = {n: digest(ROOT / n) for n in ('report.md', 'index.html', 'latex/main.pdf', 'latex_project.zip')}
        record['status'] = 'PASS'
    except Exception as exc:
        record['status'] = 'FAIL'
        record['error'] = str(exc)
        raise
    finally:
        (logdir / 'summary.json').write_text(json.dumps(record, ensure_ascii=False, indent=2), encoding='utf-8')
        print('BUILD_RECORD', logdir)


if __name__ == '__main__':
    main()

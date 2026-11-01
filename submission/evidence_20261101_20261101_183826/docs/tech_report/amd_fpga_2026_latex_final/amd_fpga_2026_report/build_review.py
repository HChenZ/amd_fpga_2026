"""Build this editable LaTeX handoff with Tectonic, validating before publishing."""
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = next(p for p in HERE.parents if (p / 'AGENTS.md').is_file())


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--tectonic', default=os.environ.get('TECTONIC') or shutil.which('tectonic')
                        or 'C:/wenjian/toolchain/tectonic/tectonic.exe')
    args = parser.parse_args()
    stamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    logs = HERE / 'validation' / ('build_' + stamp)
    work = ROOT / 'build/local/report_puf3_review' / ('build_' + stamp)
    logs.mkdir(parents=True)
    work.mkdir(parents=True)
    records = []

    def run(name, command, cwd=HERE):
        p = subprocess.run([str(x) for x in command], cwd=cwd, stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT, env=dict(os.environ, PYTHONUTF8='1'))
        (logs / (name + '.log')).write_bytes(p.stdout)
        records.append({'name': name, 'command': [str(x) for x in command], 'exit_code': p.returncode})
        print(name, 'exit', p.returncode, flush=True)
        if p.returncode:
            raise RuntimeError(p.stdout.decode('utf-8', errors='replace')[-6000:])

    try:
        run('evidence', [sys.executable, '-X', 'utf8', HERE / 'review_evidence.py', '--generate'])
        files = [HERE / n for n in ['main.tex', 'preamble.tex', 'cover.tex', 'header_logo.png']]
        for directory in ['chapters', 'figs', 'evidence']:
            files.extend(p for p in (HERE / directory).rglob('*') if p.is_file())
        before = {p.relative_to(HERE).as_posix(): digest(p) for p in files}
        evidence_inputs = json.loads((HERE / 'validation/evidence_check.json').read_text(encoding='utf-8'))['inputs_sha256']
        for p in files:
            target = work / p.relative_to(HERE)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(p, target)
        run('tool_version', [args.tectonic, '--version'])
        run('compile', [args.tectonic, '-X', 'compile', 'main.tex', '--keep-logs'], work)
        shutil.copy2(work / 'main.log', logs / 'latex.log')
        log = (work / 'main.log').read_text(encoding='utf-8', errors='replace')
        bad = ['Missing character:', 'There were undefined references', 'multiply defined', 'Emergency stop', 'Fatal error']
        if any(x in log for x in bad):
            raise RuntimeError('Unresolved LaTeX diagnostics; inspect ' + str(logs / 'latex.log'))
        run('pdf_check', [sys.executable, '-X', 'utf8', HERE / 'review_evidence.py', '--pdf', work / 'main.pdf',
                          '--output', logs / 'pdf_check.json'])
        if any(digest(HERE / p) != h for p, h in before.items()):
            raise RuntimeError('Report sources changed during compilation')
        if any(digest(ROOT / p) != h for p, h in evidence_inputs.items()):
            raise RuntimeError('Evidence changed during compilation')
        final = HERE / 'output/pdf/final_report.pdf'
        final.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(work / 'main.pdf', final)
        summary = {'status': 'PASS', 'python': sys.version, 'steps': records, 'source_sha256': before,
                   'evidence_sha256': evidence_inputs, 'output': str(final), 'pdf_sha256': digest(final)}
        print('PDF ->', final, flush=True)
    except Exception as exc:
        summary = {'status': 'FAIL', 'steps': records, 'error': str(exc)}
        print(str(exc), flush=True)
    (logs / 'summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    return 0 if summary['status'] == 'PASS' else 1


if __name__ == '__main__':
    raise SystemExit(main())

#!/usr/bin/env python
"""装配当前报告与证据到新目录，不覆盖历史包；逐文件哈希与 ZIP 自检。"""
from __future__ import annotations

import argparse
import datetime
import hashlib
import json
from pathlib import Path
import shutil
import sys
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_evidence import EVIDENCE, ROOT, EV


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output', type=Path)
    args = p.parse_args()
    out = args.output or ROOT / 'submission' / ('evidence_20261101_' + datetime.datetime.now().strftime('%Y%m%d_%H%M%S'))
    if out.exists() or out.with_suffix('.zip').exists():
        raise SystemExit('Destination exists; choose a new path: ' + str(out))
    files = list(dict.fromkeys(f for _, _, paths in EVIDENCE for f in paths))
    files += [ROOT / 'docs/tech_report' / n for n in ('report.md', 'latex/main.pdf', 'latex_project.zip',
              'evidence/manifest.md', 'evidence/appendix_c_raw.md', 'evidence/sha256sums.txt')]
    files += [ROOT / n for n in ('docs/project_intro_20261101.md', 'docs/skill_test_guide_20261030.md',
              'tasks/release_plan_20261101.md', 'skill/rtl-design-discipline/SKILL.md', 'LICENSE')]
    for f in files:
        if not f.is_file():
            raise SystemExit('Missing: ' + str(f))
    expected = {}
    for line in (EV / 'sha256sums.txt').read_text(encoding='utf-8').splitlines():
        digest, name = line.split('  ', 1)
        if sha(ROOT / name) != digest:
            raise SystemExit('Stale evidence manifest: ' + name)
    out.mkdir(parents=True)
    for f in files:
        name = f.relative_to(ROOT).as_posix()
        dest = out / name
        dest.parent.mkdir(parents=True, exist_ok=True)
        before = sha(f)
        shutil.copy2(f, dest)
        if sha(dest) != before or sha(f) != before:
            raise SystemExit('File changed during assembly: ' + name)
        expected[name] = before
    readme = ('# 当前报告证据包\n\n11-01 提交候选；此包不是完整工程源码快照。\n'
              '报告：docs/tech_report/latex/main.pdf；Overleaf：docs/tech_report/latex_project.zip。\n'
              '主线为当前PYNQ三模式，历史PL-only与独立PUF原型分别标注。\n'
              '根目录sha256sums.txt覆盖所有随包文件；原始目录结构保持为仓库相对路径。\n'
              '硬件/长时/Skill结果未在装配时重测；团队信息、PPT、视频与上传动作由项目方完成。\n')
    (out / 'README.md').write_text(readme, encoding='utf-8')
    expected['README.md'] = sha(out / 'README.md')
    (out / 'sha256sums.txt').write_text(''.join(f'{h}  {n}\n' for n, h in sorted(expected.items())), encoding='utf-8')
    archive = out.with_suffix('.zip')
    with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as z:
        for f in sorted(out.rglob('*')):
            if f.is_file():
                z.write(f, f.relative_to(out).as_posix())
    with zipfile.ZipFile(archive) as z:
        if z.testzip() is not None:
            raise SystemExit('ZIP CRC failure')
        for name, digest in expected.items():
            if hashlib.sha256(z.read(name)).hexdigest() != digest:
                raise SystemExit('ZIP hash failure: ' + name)
    record = {'status': 'PASS', 'files': len(expected), 'directory': str(out.relative_to(ROOT)),
              'zip': str(archive.relative_to(ROOT)), 'zip_sha256': sha(archive)}
    (ROOT / 'submission/current_evidence.json').write_text(json.dumps(record, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(record, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()

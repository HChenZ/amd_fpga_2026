"""Assemble current PUF3 deliverables; create, extract and verify a genuine RAR.

Use --rar for native rar.exe or --wsl-rar for the official Linux binary in WSL.
Only delivery materials are written; no synthesis, firmware build or board run.
"""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
TITLE = 'RISC-V轻量密码加速SoC'
ARCHIVE = ROOT / 'delivery' / (TITLE + '_最终交付.rar')
CAND = 'board/vivado_zynq7000_xc7z020_pynq_puf3/candidate'
PDF = 'report/technical/amd_fpga_2026_latex_final/amd_fpga_2026_report/output/pdf/final_report.pdf'


def sha(body):
    return hashlib.sha256(body).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    tool = parser.add_mutually_exclusive_group(required=True)
    tool.add_argument('--rar')
    tool.add_argument('--wsl-rar')
    args = parser.parse_args()
    if ARCHIVE.exists():
        raise SystemExit('Archive already exists; preserve it and use a fresh checkout to rebuild')
    revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    tracked = subprocess.check_output(['git', 'ls-files', '-z'], cwd=ROOT).decode().split('\0')
    # Never package unfinished source changes from a shared checkout.
    dirty = subprocess.check_output(['git', 'diff', 'HEAD', '--name-only', '--',
                                    'src', 'sim', 'ascon', 'board', 'data', 'skill/pynq-overlay-workflow'], cwd=ROOT)
    if dirty:
        raise SystemExit('Production inputs have uncommitted changes')
    work = Path(tempfile.mkdtemp(prefix='final_rar_', dir=ROOT / 'build/local'))
    project = work / TITLE
    project.mkdir()
    sources = {}

    def put(name, body, source):
        path = project / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(body)
        sources[name] = {'source': source, 'sha256': sha(body), 'bytes': len(body)}

    def copy(name, target=None):
        put(target or 'code/' + name, (ROOT / name).read_bytes(), name)

    prefixes = ('src/', 'sim/', 'ascon/', 'board/vivado_zynq7000_xc7z020_pynq_puf3/',
                'board/atk_navigator_7020/', 'data/ascon/', 'data/pynq_puf3/', 'report/design/')
    for name in tracked:
        if name.startswith(prefixes):
            copy(name)
    for name in ['LICENSE', 'AGENTS.md', '.gitignore', '.gitattributes', 'board/readme.md',
                 'build/readme.md', 'build/keys_ro_allow_loops.tcl', 'build/keys_ro_pblock.xdc',
                 'tools/verify_puf3_sources.py']:
        copy(name)
    ipbase = 'board/vivado_zynq7000_xc7z020_ascon/riscv_vivado_project/riscv_vivado_project.srcs/sources_1'
    shared = [ipbase + '/ip/' + n + '/' + n + '.xci' for n in ['axi_bram_ctrl_0', 'blk_mem_gen_0']]
    shared += [ipbase + '/imports/bin_file/ascon_keys.coe']
    for name in shared:
        copy(name)
    # This is an actual host-test dependency, not a historical project attachment.
    with zipfile.ZipFile(ROOT / 'archive/evidence/raw_records_20261102.zip') as z:
        for stem in ['sw_timing_acb_sw', 'hw_timing_acb_hw', 'ise_timing_acb_ise']:
            for ext in ['.json', '.log']:
                name = 'data/ascon/results/key_lifecycle/' + stem + ext
                put('code/' + name, z.read(name), 'archive/evidence/raw_records_20261102.zip::' + name)
    # All official reference files referenced by the locked provenance are required.
    for manifest in ['provenance.json', 'derived_integrity.json']:
        for row in json.loads((ROOT / ('data/ascon/' + manifest)).read_text(encoding='utf-8'))['files']:
            p = project / 'code' / row['path']
            if not p.exists() or sha(p.read_bytes()) != row['sha256']:
                raise ValueError('Missing/corrupt official validation dependency: ' + row['path'])

    copy(PDF, 'technical_report/final_report.pdf')
    with zipfile.ZipFile(ROOT / 'delivery/technical_report.zip') as z:
        meta = json.loads(z.read('technical_report/source_manifest.json'))
        for name, digest in meta['files'].items():
            if sha(z.read('technical_report/' + name)) != digest:
                raise ValueError('Formal report member hash mismatch: ' + name)
        if z.read('technical_report/final_report.pdf') != (ROOT / PDF).read_bytes():
            raise ValueError('Formal PDF and report ZIP are different versions')
        for name in z.namelist():
            if name.startswith('technical_report/latex/'):
                put(name, z.read(name), 'delivery/technical_report.zip::' + name)
    put('technical_report/README.md', (
        '# 技术报告编译\n\n当前PDF为正式85页版本，长命令排版已修复。latex/从同一正式包原样提取，正文、图件、数据未改。\n'
        '进入latex/后执行 tectonic -X compile main.tex --keep-logs，或使用build.sh/build.ps1（latexmk + XeLaTeX）。\n'
        '需ctex/Fandol、TikZ、fvextra等TeX包及DejaVu Sans Mono字体；Tectonic首次编译需联网取包，已有缓存可离线。\n'
        '正式构建使用Tectonic0.15.0；原字号/字体保留，代码块仅调整字距、留白和自动换行标记。\n'
        '不要用pdfLaTeX编译。编译输出main.pdf不会自动替换上级final_report.pdf。\n'
        '原readme.md的历史说明保留；build_review.py/review_evidence.py需要完整原仓库及恢复的历史记录，\n'
        '不能在本精简包中声称194项证据重核已运行。独立LaTeX编译不依赖这些记录。\n'
    ).encode(), 'generated compilation instructions')

    skill_items = {}
    for name in tracked:
        if name.startswith('skill/pynq-overlay-workflow/'):
            copy(name, name)
            skill_items[name.removeprefix('skill/')] = (ROOT / name).read_bytes()
    license_bytes = (ROOT / 'LICENSE').read_bytes()
    put('skill/pynq-overlay-workflow/LICENSE', license_bytes, 'LICENSE')
    skill_items['pynq-overlay-workflow/LICENSE'] = license_bytes
    # Fresh standalone Skill ZIP from current tracked tree, never from an old ZIP.
    zip_path = project / 'skill/pynq_overlay_workflow_skill.zip'
    with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as z:
        for name, body in sorted(skill_items.items()):
            z.writestr(name, body)
        meta = {'source_revision': revision, 'files': {n.removeprefix('pynq-overlay-workflow/'): sha(b)
                                                     for n, b in skill_items.items()}}
        z.writestr('pynq-overlay-workflow/source_manifest.json', json.dumps(meta, ensure_ascii=False, indent=2))
    sources['skill/pynq_overlay_workflow_skill.zip'] = {'source': 'current tracked Skill + LICENSE',
                                                      'sha256': sha(zip_path.read_bytes()), 'bytes': zip_path.stat().st_size}
    for src, dest in [('delivery/final_readme.md', 'README.md'),
                      ('delivery/final_code_readme.md', 'code/README.md'),
                      ('delivery/verify_final_checksums.py', 'verify_checksums.py'), ('LICENSE', 'LICENSE')]:
        copy(src, dest)
    manifest = {'schema': 1, 'source_repository': 'https://github.com/HChenZ/amd_fpga_2026',
                'source_revision': revision, 'generated': datetime.datetime.now().astimezone().isoformat(timespec='seconds'),
                'scope': 'current PUF3 source/dependencies and unchanged candidate; latest report; current independent Skill',
                'shared_ip_files': shared,
                'excluded': ['.git', 'virtual environments', 'caches', 'independent historical projects',
                             'old delivery ZIPs and repository snapshot', 'LLM sessions and local agent settings'],
                'historical_support': 'six raw simulation fixture files for host unit tests, plus shared v1 API compatibility; not current board results',
                'original_report_zip_sha256': sha((ROOT / 'delivery/technical_report.zip').read_bytes()),
                'files': sources}
    (project / 'delivery_manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    sums = {p.relative_to(project).as_posix(): sha(p.read_bytes()) for p in project.rglob('*') if p.is_file()}
    (project / 'SHA256SUMS.txt').write_text(''.join(f'{h}  {n}\n' for n, h in sorted(sums.items())), encoding='utf-8')

    records = []

    def run(name, command, cwd, timeout=240):
        p = subprocess.run([str(x) for x in command], cwd=cwd, capture_output=True, timeout=timeout,
                           env=dict(os.environ, PYTHONUTF8='1', PYTHONDONTWRITEBYTECODE='1'))
        body = (p.stdout + p.stderr).decode('utf-8', errors='replace')
        (work / (name + '.log')).write_text(body, encoding='utf-8')
        records.append({'name': name, 'exit_code': p.returncode, 'tail': body[-1600:]})
        print(name, 'exit', p.returncode, flush=True)
        if p.returncode:
            raise RuntimeError(name + ' failed; see local build log')

    def linux(path):
        path = Path(path).resolve().as_posix()
        return '/mnt/' + path[0].lower() + path[2:]

    def rar(name, command, cwd):
        if args.wsl_rar:
            run(name, ['wsl', '-d', 'Ubuntu', '--cd', linux(cwd), '--', args.wsl_rar, *command], ROOT)
        else:
            run(name, [args.rar, *command], cwd)

    rar('create_rar', ['a', '-cfg-', '-m5', '-r', '-idq', linux(ARCHIVE) if args.wsl_rar else str(ARCHIVE), TITLE], work)
    if ARCHIVE.read_bytes()[:8] != b'Rar!\x1a\x07\x01\x00':
        raise ValueError('Not genuine RAR5 format')
    archive_arg = linux(ARCHIVE) if args.wsl_rar else str(ARCHIVE)
    rar('test_rar', ['t', '-cfg-', '-idq', archive_arg], work)
    extracted = work / 'extracted'
    extracted.mkdir()
    rar('extract_rar', ['x', '-cfg-', '-idq', '-o-', archive_arg,
                        (linux(extracted) if args.wsl_rar else str(extracted)) + '/'], work)
    if [p.name for p in extracted.iterdir()] != [TITLE]:
        raise ValueError('Expected one top-level project directory')
    final = extracted / TITLE
    for name, digest in {**sums, 'SHA256SUMS.txt': sha((project / 'SHA256SUMS.txt').read_bytes())}.items():
        if sha((final / name).read_bytes()) != digest:
            raise ValueError('Extracted bytes differ: ' + name)
    if len([p for p in final.rglob('*') if p.is_file()]) != len(sums) + 1:
        raise ValueError('Extra/missing extracted files')
    readme = (final / 'README.md').read_text(encoding='utf-8')
    links = re.findall(r'\]\(([^)#]+)(?:#[^)]*)?\)', readme)
    missing = [link for link in links if '://' not in link and not (final / link).exists()]
    if missing:
        raise ValueError('README links do not exist: ' + repr(missing))
    bad_paths = [p.relative_to(final).as_posix() for p in final.rglob('*')
                 if any(x in p.parts for x in ['.git', '.venv', '__pycache__', '.Xil', '.claude', '.codex'])
                 or p.name in ['.env', 'rarreg.key']]
    if bad_paths:
        raise ValueError('Forbidden local files bundled')
    # Only detect high-confidence credential formats; public KAT keys are intentional.
    secret_pattern = re.compile(rb'-----BEGIN (?:RSA |OPENSSH |EC )?PRIVATE KEY-----|gh[pousr]_[A-Za-z0-9]{30,}|AKIA[0-9A-Z]{16}')
    for p in final.rglob('*'):
        if p.is_file() and secret_pattern.search(p.read_bytes()):
            raise ValueError('Credential pattern found: ' + p.relative_to(final).as_posix())
    run('checksums', [sys.executable, '-B', 'verify_checksums.py'], final)
    run('source_identity_elaboration', [sys.executable, '-B', '-X', 'utf8', 'tools/verify_puf3_sources.py', '--compile'], final / 'code')
    run('host_unit_tests', [sys.executable, '-B', '-m', 'unittest', 'discover', '-s', 'src/pynq', '-p', 'test_*.py'], final / 'code')
    run('standalone_skill_tests', [sys.executable, '-B', '-m', 'pytest', 'tests', '-q', '-p', 'no:cacheprovider'], final / 'skill/pynq-overlay-workflow')
    run('skill_cli', [sys.executable, '-B', 'scripts/pynq_skill_cli.py', '--help'], final / 'skill/pynq-overlay-workflow')
    run('checksums_after_tests', [sys.executable, '-B', 'verify_checksums.py'], final)
    with zipfile.ZipFile(final / 'skill/pynq_overlay_workflow_skill.zip') as z:
        if z.testzip() is not None:
            raise ValueError('Skill ZIP CRC failure')
        for name, body in skill_items.items():
            if z.read(name) != body or (final / 'skill' / name).read_bytes() != body:
                raise ValueError('Standalone Skill differs from current source')
    import pymupdf
    with pymupdf.open(final / 'technical_report/final_report.pdf') as doc:
        pages = len(doc)
        if pages != 85:
            raise ValueError('Unexpected formal report page count')
    check = {'status': 'PASS', 'source_revision': revision, 'rar_format': 'RAR5',
             'archive': ARCHIVE.relative_to(ROOT).as_posix(), 'bytes': ARCHIVE.stat().st_size,
             'sha256': sha(ARCHIVE.read_bytes()), 'files': len(sums) + 1,
             'top_level_directory': TITLE, 'report_pages': pages,
             'report_sha256': sha((ROOT / PDF).read_bytes()),
             'skill_zip_sha256': sha(zip_path.read_bytes()),
             'readme_links_checked': len(links), 'missing_readme_links': missing,
             'all_packaged_files_match_after_extraction': True,
             'all_current_source_files_match_repository': True,
             'candidate_artifacts_and_reports_unchanged': True,
             'credential_pattern_scan': 'no high-confidence private-key/token matches',
             'commands': records,
             'limitations': ['no new firmware compilation, Vivado synthesis/implementation or board run',
                             'three optional Skill artifact tests may skip',
                             'original source/report may retain historical tool fallback paths; no local settings/configs bundled'],
             'local_validation_directory': work.relative_to(ROOT).as_posix()}
    (ROOT / 'delivery/final_rar_manifest.json').write_text(json.dumps(check, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    (ROOT / 'delivery/final_rar_sha256.txt').write_text(check['sha256'] + '  ' + ARCHIVE.name + '\n', encoding='utf-8')
    (ROOT / 'delivery/final_rar_files.json').write_text(json.dumps(sums, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({k: check[k] for k in ['status', 'archive', 'bytes', 'files', 'sha256']}, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()

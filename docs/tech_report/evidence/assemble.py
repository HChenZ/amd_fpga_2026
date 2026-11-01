#!/usr/bin/env python
"""装配最终报告与证据到新目录，不覆盖历史包；装配前校验报告-板测-工件一致，逐文件哈希与 ZIP 自检。

报告位置与板测来源在 build_evidence.py 顶部（REPORT_DIR/REPORT_PDF/BENCH/GATE/PUF3_RUN）统一维护。
--check-only 只跑全部门禁、不写包，供报告定稿前反复检查。
"""
from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import re
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_evidence import EV, EVIDENCE, PUF3_RUN, REPORT_DIR, REPORT_PDF, ROOT

PUF3 = ROOT / 'board/vivado_zynq7000_xc7z020_pynq_puf3'
DMA = ROOT / 'board/vivado_zynq7000_xc7z020_axi_dma_loopback'
L3 = ROOT / 'data/skill/l3_20261031_063709'
L2 = ROOT / 'skill/ab_eval_pynq/results/l2_20261030_deepseek-flash'
SKILL = ROOT / 'skill/pynq-overlay-workflow'
D02 = ROOT / 'docs/tech_report/validation/benchmark_tables_check.json'
# 报告源里出现的仓库相对路径；build/local 为本机缓存，不要求存在于仓库。
REF = re.compile(r'(?<![A-Za-z0-9_./-])(?:data|board|build/reports|src|sim|skill|docs|report|tasks|ascon)'
                 r'/[A-Za-z0-9_./-]+\.[A-Za-z0-9]+')
NOTES = []

EXTRA = [
    ('X-1', 'PUF3 overlay（最终报告主演示）：三模式+PUF v1 候选与实现报告',
     [PUF3 / 'readme.md'] +
     [PUF3 / 'candidate' / n for n in ('pynq_puf3.bit', 'pynq_puf3.hwh', 'pynq_svc_puf.bin', 'pynq_svc_puf.coe',
      'pynq_svc_puf.elf', 'manifest.json', 'sha256sums.txt')] +
     [PUF3 / 'candidate/reports' / n for n in ('context.txt', 'gate.txt', 'timing_summary.rpt', 'utilization.rpt',
      'drc.rpt', 'methodology.rpt', 'route_status.rpt', 'check_timing_counts.txt', 'clock_interaction.rpt',
      'ro_corner_sta.txt', 'pblock_utilization.rpt', 'explore_impl.txt', 'firmware_build.json',
      'cosim_summary.json', 'cosim_normal.log', 'cosim_mutant_autolock.log')]),
    ('X-2', 'PUF3 实板 Notebook 结果（最终报告唯一主采样，KAT/benchmark/PUF）',
     [ROOT / 'src/pynq_puf3/pynq_puf3_board_test.ipynb', PUF3_RUN / 'result.json', PUF3_RUN / 'mailbox_log.txt']),
    ('X-3', 'pynq-overlay-workflow Skill 本体与说明',
     [ROOT / 'skill/readme.md', SKILL / 'SKILL.md', ROOT / 'skill/ab_eval_pynq/README.md']),
    ('X-4', 'Skill L2 受控实验结果（simulated，仅方向性）',
     [L2 / n for n in ('README.md', 'results_final.csv', 'results_holdout_t5.csv', 'stats_final.txt',
      'stats_holdout_t5.txt')]),
    ('X-5', 'Skill L3 实板 session（10-31，preflight/Ascon/GPIO/DMA）',
     [L3 / n for n in ('00_preflight.json', '10_ascon_release.json', '20_non_ascon_gpio.json',
      '30_non_ascon_dma.json', '40_summary.json', '40_summary.md')]),
    ('X-6', '非 Ascon AXI DMA 回环 overlay 候选与 S04 报告示例',
     [DMA / 'readme.md'] +
     [DMA / 'candidate' / n for n in ('axi_dma_loopback.bit', 'axi_dma_loopback.hwh', 'manifest.json',
      'sha256sums.txt')] +
     [DMA / 'candidate/reports' / n for n in ('context.txt', 'gate.txt', 'timing_summary.rpt', 'utilization.rpt',
      'drc.rpt', 'route_status.rpt', 'check_timing_counts.txt')] +
     [ROOT / 'data/skill/s04_report_dma_loopback' / n for n in ('report.json', 'report.md')]),
    ('X-7', 'D02 最终报告数值与原始数据核对（独立于报告自带 review_evidence.py）',
     [EV / 'check_benchmark_tables.py', D02]),
    ('X-8', 'D04 演示视频脚本（实机视频未录）', [ROOT / 'report/demo_video_script.md']),
]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rel(path):
    try:
        return path.relative_to(ROOT).as_posix()
    except ValueError:
        return str(path)


def load(path):
    return json.loads(path.read_text(encoding='utf-8'))


def git_version_with_hash(name, digest):
    """在该文件的 Git 历史中查找内容哈希等于 digest 的提交；找不到返回 None。"""
    log = subprocess.run(['git', 'log', '--format=%h', '--', name], cwd=ROOT,
                         capture_output=True, check=True).stdout.decode().split()
    for commit in log:
        blob = subprocess.run(['git', 'show', f'{commit}:{name}'], cwd=ROOT, capture_output=True)
        if blob.returncode == 0 and hashlib.sha256(blob.stdout).hexdigest() == digest:
            return commit
    return None


def report_group(fail):
    """最终报告门禁：最近一次构建 PASS，PDF/报告源/证据输入与构建记录一致，板测结果为 PUF3_RUN。

    返回 (报告组文件, 报告核对过的证据输入文件, 报告源中引用的仓库文件, 构建记录目录)。
    """
    builds = sorted(p for p in (REPORT_DIR / 'validation').glob('build_*') if (p / 'summary.json').is_file())
    if not builds:
        fail.append('report: no validation/build_*/summary.json; run build_review.py')
        return [], [], [], None
    build = builds[-1]
    s = load(build / 'summary.json')
    board = rel(PUF3_RUN / 'result.json')
    if s.get('status') != 'PASS':
        fail.append(f'report: latest build {build.name} status {s.get("status")}')
        return [], [], [], build
    if s['pdf_sha256'] != sha(REPORT_PDF):
        fail.append(f'report: {rel(REPORT_PDF)} is not the PDF produced by {build.name}')
    sources = []
    for name, digest in s['source_sha256'].items():
        p = REPORT_DIR / name
        if not p.is_file() or sha(p) != digest:
            fail.append(f'report: source changed after {build.name} (rebuild report): {name}')
        sources.append(p)
    inputs = []
    for name, digest in s['evidence_sha256'].items():
        p = ROOT / name
        if not p.is_file() or sha(p) != digest:
            fail.append(f'report: evidence input changed after {build.name}: {name}')
        inputs.append(p)
    for path, label in ((build / 'pdf_check.json', 'pdf_check'), (REPORT_DIR / 'validation/evidence_check.json',
                                                                  'evidence_check')):
        c = load(path)
        if c.get('status') != 'PASS':
            fail.append(f'report: {label} not PASS')
        if c.get('board_result') != board:
            fail.append(f'report: {label} board_result {c.get("board_result")} != {board}')
        for name, digest in c['inputs_sha256'].items():
            if sha(ROOT / name) != digest:
                fail.append(f'report: {label} input stale: {name}')
    refs = set()
    for p in list(REPORT_DIR.rglob('*.tex')) + list(REPORT_DIR.glob('*.md')):
        refs |= {m.replace('\\_', '_') for m in REF.findall(p.read_text(encoding='utf-8', errors='replace'))}
    referenced = []
    for name in sorted(refs):
        p = ROOT / name
        if p.is_file():
            referenced.append(p)
        else:
            fail.append('report references missing repo file: ' + name)
    for name in sorted(set(re.findall(r'data/pynq_puf3/notebook_\d{8}_\d{6}', ' '.join(refs)))):
        if name != rel(PUF3_RUN):
            fail.append(f'report references PUF3 run {name}, packaging uses {rel(PUF3_RUN)}')
    extra = [REPORT_PDF] + [REPORT_DIR / n for n in ('readme.md', 'build_review.py', 'review_evidence.py',
                                                    'build.ps1', 'build.sh', 'latexmkrc')]
    extra += [REPORT_DIR / 'validation' / n for n in ('evidence_check.json', 'layout_check.json',
                                                      'mutation_check.json')]
    extra += sorted(p for p in build.iterdir() if p.is_file())
    return sources + extra, inputs, referenced, build


def check_extra(fail):
    """候选哈希、PUF3/L3 板测绑定与 PASS 状态、D02 结果新鲜度。"""
    for folder in (PUF3 / 'candidate', DMA / 'candidate'):
        for line in (folder / 'sha256sums.txt').read_text(encoding='utf-8').splitlines():
            digest, name = line.split('  ', 1)
            if sha(folder / name) != digest:
                fail.append('candidate hash mismatch: ' + rel(folder / name))
    r = load(PUF3_RUN / 'result.json')
    if r.get('status') != 'PASS' or r.get('exit_code') != 0 or r['service'].get('simulated') is not False:
        fail.append('PUF3 board result not PASS/real hardware')
    m = load(PUF3 / 'candidate/manifest.json')
    for key, name in (('bit_sha256', 'pynq_puf3.bit'), ('hwh_sha256', 'pynq_puf3.hwh'),
                      ('manifest_sha256', 'manifest.json')):
        if r.get(key) != sha(PUF3 / 'candidate' / name):
            fail.append('PUF3 board result not bound to candidate: ' + name)
    for name in ('pynq_puf3.bit', 'pynq_puf3.hwh'):
        if m['artifacts'][name]['sha256'] != sha(PUF3 / 'candidate' / name):
            fail.append('PUF3 manifest artifact mismatch: ' + name)
    for mode, d in r['sections']['kat'].items():
        if d['kat_pass'] != 289 or d['tag_reject'] != 289:
            fail.append('PUF3 KAT incomplete: ' + mode)
    s = load(L3 / '40_summary.json')
    if s.get('status') != 'PASS' or s.get('problems') or any(row['status'] != 'PASS' for row in s['rows']):
        fail.append('Skill L3 summary not PASS')
    for name, digest in s['l2_context']['files'].items():
        if sha(ROOT / name) == digest:
            continue
        commit = git_version_with_hash(name, digest)
        if commit:
            NOTES.append(f'`{name}`：L3 绑定的是提交 {commit} 中的版本（SHA-256 {digest[:12]}…），'
                         '其后文件有改动，随包为当前版本；原版本可用 `git show` 取回。')
        else:
            fail.append('Skill L3 not bound to L2 file: ' + name)
    dma = (L3 / '30_non_ascon_dma.json').read_text(encoding='utf-8')
    for name in ('axi_dma_loopback.bit', 'axi_dma_loopback.hwh', 'manifest.json'):
        if sha(DMA / 'candidate' / name) not in dma:
            fail.append('Skill L3 DMA not bound to candidate: ' + name)
    d02 = load(D02)
    if d02.get('status') != 'PASS' or d02.get('failures'):
        fail.append('D02 benchmark table check not PASS')
    if d02.get('board_result') != rel(PUF3_RUN / 'result.json'):
        fail.append('D02 checked a different board result: ' + str(d02.get('board_result')))
    for name, digest in d02['inputs'].items():
        if sha(ROOT / name) != digest:
            fail.append('D02 check stale (rerun check_benchmark_tables.py): ' + name)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output', type=Path)
    p.add_argument('--check-only', action='store_true')
    args = p.parse_args()
    fail = []
    report_files, report_inputs, referenced, build = report_group(fail)
    check_extra(fail)
    for line in (EV / 'sha256sums.txt').read_text(encoding='utf-8').splitlines():
        digest, name = line.split('  ', 1)
        if not (ROOT / name).is_file() or sha(ROOT / name) != digest:
            fail.append('Stale C-group manifest (rerun build_evidence.py): ' + name)
    groups = [('R', f'最终报告：PDF、LaTeX 源、报告核对脚本与最近一次构建记录 {build.name if build else "-"}',
               report_files),
              ('R-in', '报告构建时核对过的全部证据原件（build summary evidence_sha256）', report_inputs),
              ('R-ref', '报告正文引用的仓库文件', referenced)] + EXTRA
    files = list(dict.fromkeys(f for _, _, paths in EVIDENCE for f in paths))
    files += [EV / n for n in ('manifest.md', 'sha256sums.txt')]
    files += [ROOT / n for n in ('docs/skill_test_guide_20261030.md', 'tasks/release_plan_20261101.md',
              'tasks/task_board.md', 'skill/rtl-design-discipline/SKILL.md', 'LICENSE')]
    files += [f for _, _, paths in groups for f in paths]
    files = list(dict.fromkeys(files))
    fail += ['Missing: ' + rel(f) for f in files if not f.is_file()]
    if fail:
        raise SystemExit('FAIL\n' + '\n'.join(dict.fromkeys(fail)))
    summary = {'status': 'PASS', 'files': len(files) + 2,  # + README.md、extra_manifest.md（sha256sums 不计入自身）
               'report_build': build.name, 'report_pdf': rel(REPORT_PDF),
               'report_pdf_sha256': sha(REPORT_PDF), 'board_result': rel(PUF3_RUN / 'result.json')}
    if args.check_only:
        print(json.dumps({**summary, 'mode': 'check-only (no package written)'}, ensure_ascii=False, indent=2))
        return

    out = args.output or ROOT / 'submission' / ('evidence_20261101_' + datetime.datetime.now().strftime('%Y%m%d_%H%M%S'))
    if out.exists() or out.with_suffix('.zip').exists():
        raise SystemExit('Destination exists; choose a new path: ' + str(out))
    out.mkdir(parents=True)
    expected = {}
    for f in files:
        name = rel(f)
        dest = out / name
        dest.parent.mkdir(parents=True, exist_ok=True)
        before = sha(f)
        shutil.copy2(f, dest)
        if sha(dest) != before or sha(f) != before:
            raise SystemExit('File changed during assembly: ' + name)
        expected[name] = before
    readme = (
        '# 最终报告证据包\n\n'
        '11-01 提交候选；此包不是完整工程源码快照（源码包见仓库 submission/freeze_manifest.md）。\n'
        f'报告：{rel(REPORT_PDF)}（SHA-256 {summary["report_pdf_sha256"]}），LaTeX 源同目录；\n'
        f'该 PDF 由报告构建 {build.name} 产出，装配时核对：PDF 哈希、报告源与证据输入均与构建记录一致，\n'
        f'报告自带 evidence/pdf 核对 PASS，且板测结果均为 {summary["board_result"]}。\n'
        '主演示为 PUF3 overlay（X-1/X-2）；C-1～C-5 的 PYNQ v1 release（pynq-svc-v1）在报告中作历史对照，\n'
        '其错误门禁 9/9 不属于 PUF3；历史 PL-only 与独立 PUF 原型分别标注。\n'
        '根目录 sha256sums.txt 覆盖所有随包文件；原始目录结构保持为仓库相对路径；分组见 extra_manifest.md。\n'
        '限制：PUF3 跨上电/PVT/BER 未测，RO 计数器域未签核，PUF 原始数据可读，墙钟仅有 summary；\n'
        'Skill L2 为 simulated 且对安慰剂不显著，L3 验证版本早于最新离线修复；DMA 吞吐未测。\n'
        '硬件结果未在装配时重测；团队信息、PPT、视频与上传动作由项目方完成。\n')
    (out / 'README.md').write_text(readme, encoding='utf-8')
    expected['README.md'] = sha(out / 'README.md')
    rows = ['# 证据分组清单（装配时校验）\n', 'C-1～C-12 见 docs/tech_report/evidence/manifest.md。\n',
            '| 项目 | 内容 | 文件数 | 文件 |', '|---|---|---:|---|']
    for eid, desc, paths in groups:
        rows.append(f'| {eid} | {desc} | {len(paths)} | ' + '<br>'.join(f'`{rel(p)}`' for p in paths) + ' |')
    if NOTES:
        rows += ['', '## 绑定说明', ''] + [f'- {n}' for n in NOTES]
    (out / 'extra_manifest.md').write_text('\n'.join(rows) + '\n', encoding='utf-8')
    expected['extra_manifest.md'] = sha(out / 'extra_manifest.md')
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
              'zip': str(archive.relative_to(ROOT)), 'zip_sha256': sha(archive),
              'report_build': build.name, 'report_pdf_sha256': summary['report_pdf_sha256'],
              'board_result': summary['board_result']}
    (ROOT / 'submission/current_evidence.json').write_text(json.dumps(record, ensure_ascii=False, indent=2),
                                                         encoding='utf-8')
    print(json.dumps(record, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()

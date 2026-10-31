#!/usr/bin/env python
"""装配当前报告与证据到新目录，不覆盖历史包；逐文件哈希与 ZIP 自检。"""
from __future__ import annotations

import argparse
import datetime
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_evidence import EVIDENCE, ROOT, EV


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


# 10-30/10-31 新增实测，不进报告附录 C（报告源由队友维护），只随包并在装配时校验。
PUF3 = ROOT / 'board/vivado_zynq7000_xc7z020_pynq_puf3'
PUF3_RUN = ROOT / 'data/pynq_puf3/notebook_20261030_144328'
DMA = ROOT / 'board/vivado_zynq7000_xc7z020_axi_dma_loopback'
L3 = ROOT / 'data/skill/l3_20261031_063709'
L2 = ROOT / 'skill/ab_eval_pynq/results/l2_20261030_deepseek-flash'
SKILL = ROOT / 'skill/pynq-overlay-workflow'
EXTRA = [
    ('X-1', 'pynq_puf3 三模式+PUF v1 单 overlay 候选与实现报告（10-30）',
     [PUF3 / 'readme.md'] +
     [PUF3 / 'candidate' / n for n in ('pynq_puf3.bit', 'pynq_puf3.hwh', 'pynq_svc_puf.bin', 'pynq_svc_puf.coe',
      'pynq_svc_puf.elf', 'manifest.json', 'sha256sums.txt')] +
     [PUF3 / 'candidate/reports' / n for n in ('context.txt', 'gate.txt', 'timing_summary.rpt', 'utilization.rpt',
      'drc.rpt', 'route_status.rpt', 'check_timing_counts.txt', 'clock_interaction.rpt', 'ro_corner_sta.txt',
      'pblock_utilization.rpt', 'explore_impl.txt', 'firmware_build.json', 'cosim_summary.json',
      'cosim_normal.log', 'cosim_mutant_autolock.log')]),
    ('X-2', 'pynq_puf3 实板 Notebook 结果（10-30，KAT/benchmark/PUF 四段）',
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
    ('X-7', 'D02 报告性能/资源/时序数值与原始数据核对',
     [EV / 'check_benchmark_tables.py', ROOT / 'docs/tech_report/validation/benchmark_tables_check.json']),
    ('X-8', 'D04 演示视频脚本（实机视频未录）', [ROOT / 'report/demo_video_script.md']),
]
D02 = ROOT / 'docs/tech_report/validation/benchmark_tables_check.json'


def check_extra():
    """新增证据的一致性门禁：候选哈希、板测绑定与 PASS 状态。"""
    fail = []
    for folder in (PUF3 / 'candidate', DMA / 'candidate'):
        for line in (folder / 'sha256sums.txt').read_text(encoding='utf-8').splitlines():
            digest, name = line.split('  ', 1)
            if sha(folder / name) != digest:
                fail.append('candidate hash mismatch: ' + rel_posix(folder / name))
    r = json.loads((PUF3_RUN / 'result.json').read_text(encoding='utf-8'))
    if r.get('status') != 'PASS' or r.get('exit_code') != 0 or r['service'].get('simulated') is not False:
        fail.append('pynq_puf3 board result not PASS/real hardware')
    for key, name in (('bit_sha256', 'pynq_puf3.bit'), ('hwh_sha256', 'pynq_puf3.hwh'),
                      ('manifest_sha256', 'manifest.json')):
        if r.get(key) != sha(PUF3 / 'candidate' / name):
            fail.append('pynq_puf3 board result not bound to candidate: ' + name)
    for mode, d in r['sections']['kat'].items():
        if d['kat_pass'] != 289 or d['tag_reject'] != 289:
            fail.append('pynq_puf3 KAT incomplete: ' + mode)
    s = json.loads((L3 / '40_summary.json').read_text(encoding='utf-8'))
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
    d02 = json.loads(D02.read_text(encoding='utf-8'))
    if d02.get('status') != 'PASS' or d02.get('failures'):
        fail.append('D02 benchmark table check not PASS')
    for name, digest in d02['inputs'].items():
        if sha(ROOT / name) != digest:
            fail.append('D02 check stale (rerun check_benchmark_tables.py): ' + name)
    if fail:
        raise SystemExit('\n'.join(fail))


def rel_posix(path):
    return path.relative_to(ROOT).as_posix()


NOTES = []


def git_version_with_hash(name, digest):
    """在该文件的 Git 历史中查找内容哈希等于 digest 的提交；找不到返回 None。"""
    log = subprocess.run(['git', 'log', '--format=%h', '--', name], cwd=ROOT,
                         capture_output=True, check=True).stdout.decode().split()
    for commit in log:
        blob = subprocess.run(['git', 'show', f'{commit}:{name}'], cwd=ROOT, capture_output=True)
        if blob.returncode == 0 and hashlib.sha256(blob.stdout).hexdigest() == digest:
            return commit
    return None


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
              'tasks/release_plan_20261101.md', 'tasks/task_board.md',
              'skill/rtl-design-discipline/SKILL.md', 'LICENSE')]
    files += [f for _, _, paths in EXTRA for f in paths]
    files = list(dict.fromkeys(files))
    for f in files:
        if not f.is_file():
            raise SystemExit('Missing: ' + str(f))
    check_extra()
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
              '硬件/长时/Skill结果未在装配时重测；团队信息、PPT、视频与上传动作由项目方完成。\n'
              '报告附录 C 只覆盖 C-1～C-12；10-30/10-31 新增的 pynq_puf3、Skill 实测、D02 数值核对与视频脚本见 extra_manifest.md（X-1～X-8），\n'
              '冻结哈希与源码包见仓库 submission/freeze_manifest.md（装配后生成，不在本包内）。\n'
              '装配时已校验候选哈希、板测结果与候选/L2 文件绑定及 PASS 状态。\n'
              '限制：pynq_puf3 跨上电与 RO 时序未闭合，PUF 原始数据可读；Skill L2 为 simulated 且对安慰剂不显著，\n'
              'L3 验证的 Skill 版本为 7bc1abf，其后 S04 新增仅离线验证；DMA 吞吐与 short_output/missing_tlast 未测。\n')
    (out / 'README.md').write_text(readme, encoding='utf-8')
    expected['README.md'] = sha(out / 'README.md')
    rows = ['# 新增证据清单（X-1～X-8，装配时校验）\n', '| 项目 | 内容 | 文件 |', '|---|---|---|']
    for eid, desc, paths in EXTRA:
        rows.append(f'| {eid} | {desc} | ' + '<br>'.join(f'`{rel_posix(p)}`' for p in paths) + ' |')
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
              'zip': str(archive.relative_to(ROOT)), 'zip_sha256': sha(archive)}
    (ROOT / 'submission/current_evidence.json').write_text(json.dumps(record, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(record, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()

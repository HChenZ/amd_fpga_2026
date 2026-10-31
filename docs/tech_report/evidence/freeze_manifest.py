#!/usr/bin/env python
"""V04 冻结留档：在干净的已提交工作区上记录源码提交、交付工件哈希、板测绑定与证据包。

生成 git archive 源码包 submission/source_<commit>.zip（被 .gitignore 排除，只留本机），
写 submission/freeze_manifest.json 与 .md。任何校验失败 exit 1，不写清单。
"""
from __future__ import annotations

import datetime
import hashlib
import json
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SUB = ROOT / 'submission'
PYNQ = ROOT / 'board/vivado_zynq7000_xc7z020_pynq/release'
PUF3 = ROOT / 'board/vivado_zynq7000_xc7z020_pynq_puf3/candidate'
DMA = ROOT / 'board/vivado_zynq7000_xc7z020_axi_dma_loopback/candidate'
BENCH = ROOT / 'data/pynq/notebook_20261029_130920/pynq_warm_benchmark.json'
GATE = ROOT / 'data/pynq/error_gate_20261029_134023/pynq_board_error_gate.json'
PUF3_RUN = ROOT / 'data/pynq_puf3/notebook_20261030_144328/result.json'
L3 = ROOT / 'data/skill/l3_20261031_063709'
D02 = ROOT / 'docs/tech_report/validation/benchmark_tables_check.json'
OUTPUT_NAMES = ('freeze_manifest.json', 'freeze_manifest.md')

LIMITS = [
    'pynq_puf3：跨上电 not_measured；RO 振荡域时序未签核；REF/MASK/RAW/DNA 可读，未证明保密隔离；扩展展示，不替代主线 release。',
    'Skill：L2 为 simulated，with vs placebo 不显著，留出任务未复现；L3 验证版本 7bc1abf，其后 S04/gen 修复仅离线验证；DMA 吞吐、short_output/missing_tlast 未测。',
    '主线：消息/AD 各 ≤16 B；非 1089 全量板测；小时级/断电稳定性未测。',
    '未验收研发项（按 10-29 授权不阻塞提交）：B02 原 baseline 重建、B04 FreeRTOS 固件、I02/I04/I05 RV64 与完整异常矩阵、V01 完整门禁、D05 干净环境复现。',
    '报告 PDF 为 2026-10-31 14:30 构建版；实机演示视频与 PPT 不在本清单内。',
]


def sha(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def rel(path):
    return path.relative_to(ROOT).as_posix()


def git(*args):
    return subprocess.run(['git', *args], cwd=ROOT, capture_output=True, check=True,
                          text=True, encoding='utf-8').stdout.strip()


def load(path):
    return json.loads(path.read_text(encoding='utf-8'))


def sums(folder):
    """sha256sums 条目可能是目录内文件名或仓库相对路径；返回 {文件名: (路径, digest)}。"""
    out = {}
    for line in (folder / 'sha256sums.txt').read_text(encoding='utf-8').splitlines():
        digest, name = line.split('  ', 1)
        path = folder / name if (folder / name).is_file() else ROOT / name
        out[Path(name).name] = (path, digest)
    return out


def main():
    fail = []
    dirty = [l for l in git('status', '--porcelain').splitlines()
             if not any(l.endswith('submission/' + n) for n in OUTPUT_NAMES)]
    if dirty:
        raise SystemExit('Working tree not clean; commit first:\n' + '\n'.join(dirty))
    commit = git('rev-parse', 'HEAD')
    short = commit[:7]

    artefacts = []
    for name, folder, board in (('PYNQ 主线 release', PYNQ, [BENCH, GATE]),
                                ('pynq_puf3 扩展 candidate', PUF3, [PUF3_RUN]),
                                ('非 Ascon AXI DMA 回环 candidate（Skill L3）', DMA, [L3 / '30_non_ascon_dma.json'])):
        m = load(folder / 'manifest.json')
        files = {}
        for fname, (path, digest) in sums(folder).items():
            actual = sha(path) if path.is_file() else 'MISSING'
            if actual != digest:
                fail.append(f'{rel(path)} hash mismatch or missing')
            files[fname] = actual
        artefacts.append({'name': name, 'dir': rel(folder), 'part': m.get('part'), 'top': m.get('top'),
                          'vivado': m.get('vivado'), 'build_source_commit': m.get('source_commit'),
                          'build_source_dirty': m.get('source_dirty'), 'files': files,
                          'board_evidence': [rel(p) for p in board]})

    for p in (BENCH, GATE):
        r = load(p)
        for fname, digest in r['release']['artifact_sha256'].items():
            if sha(PYNQ / fname) != digest:
                fail.append(f'{rel(p)} not bound to release {fname}')
        if r.get('service', r.get('service_initial', {})).get('simulated') is not False:
            fail.append(f'{rel(p)} not real hardware')
    r = load(PUF3_RUN)
    if r['status'] != 'PASS' or r['bit_sha256'] != sha(PUF3 / 'pynq_puf3.bit') or r['hwh_sha256'] != sha(PUF3 / 'pynq_puf3.hwh'):
        fail.append('pynq_puf3 board result not PASS/bound')
    dma = (L3 / '30_non_ascon_dma.json').read_text(encoding='utf-8')
    if sha(DMA / 'axi_dma_loopback.bit') not in dma or load(L3 / '40_summary.json')['status'] != 'PASS':
        fail.append('Skill L3 not PASS/bound to DMA candidate')
    d02 = load(D02)
    if d02['status'] != 'PASS':
        fail.append('D02 check not PASS')

    ev = load(SUB / 'current_evidence.json')
    ev_zip = ROOT / ev['zip'].replace('\\', '/')
    if not ev_zip.is_file() or sha(ev_zip) != ev['zip_sha256']:
        fail.append('evidence ZIP missing or hash differs from current_evidence.json')
    ev_dir = ROOT / ev['directory'].replace('\\', '/')
    if git('ls-files', rel(ev_dir)) == '':
        fail.append('evidence directory not committed')
    if fail:
        raise SystemExit('\n'.join(fail))

    src_zip = SUB / f'source_{short}.zip'
    if not src_zip.exists():
        subprocess.run(['git', 'archive', '--format=zip', f'--prefix=amd_fpga_2026_{short}/',
                        '-o', str(src_zip), commit], cwd=ROOT, check=True)
    with zipfile.ZipFile(src_zip) as z:
        if z.testzip() is not None:
            raise SystemExit('source ZIP CRC failure')
        n_files = sum(1 for i in z.infolist() if not i.is_dir())
    n_tracked = len(git('ls-files').splitlines())
    if n_files != n_tracked:
        print(f'note: source zip {n_files} files vs ls-files {n_tracked} (symlinks/submodules differ)')

    upstream = git('rev-parse', '@{u}')
    record = {
        'task': 'V04 freeze record', 'status': 'PASS',
        'timestamp': datetime.datetime.now().astimezone().isoformat(timespec='seconds'),
        'source_commit': commit, 'branch': git('rev-parse', '--abbrev-ref', 'HEAD'),
        'upstream_commit_at_freeze': upstream, 'pushed': upstream == commit,
        'python': sys.version.split()[0],
        'source_zip': {'path': rel(src_zip), 'sha256': sha(src_zip), 'bytes': src_zip.stat().st_size,
                       'files': n_files, 'method': f'git archive --format=zip {short}（仅已跟踪文件，不入库）'},
        'evidence_package': {'directory': rel(ev_dir), 'zip': rel(ev_zip), 'zip_sha256': ev['zip_sha256'],
                             'files': ev['files']},
        'artefacts': artefacts,
        'checks': {'d02_benchmark_tables': f'{d02["status"]} {len(d02["checks"])}/{len(d02["checks"])}',
                   'pynq_puf3_board': 'PASS', 'skill_l3': 'PASS', 'release_board_binding': 'PASS'},
        'limits': LIMITS,
    }
    (SUB / 'freeze_manifest.json').write_text(json.dumps(record, ensure_ascii=False, indent=2) + '\n',
                                               encoding='utf-8')
    md = ['# 11-01 冻结清单（V04 留档，自动生成）\n',
          f'- 生成时间：{record["timestamp"]}；生成命令：`python -X utf8 docs/tech_report/evidence/freeze_manifest.py`',
          f'- 冻结源码提交：`{commit}`（{record["branch"]}；生成时 upstream `{upstream[:7]}`，'
          f'{"已" if record["pushed"] else "未"}推送）',
          f'- 源码包：`{rel(src_zip)}`，{n_files} 文件，{src_zip.stat().st_size / 1e6:.1f} MB，'
          f'SHA-256 `{record["source_zip"]["sha256"]}`（git archive，仅本机，不入库）',
          f'- 证据包：`{rel(ev_zip)}`（{ev["files"]} 文件），SHA-256 `{ev["zip_sha256"]}`；目录已入库',
          f'- 校验：D02 {record["checks"]["d02_benchmark_tables"]}；主线 release 与 benchmark/错误门禁绑定、'
          'pynq_puf3 板测、Skill L3 均 PASS\n',
          '## 交付工件\n']
    for a in artefacts:
        md.append(f'### {a["name"]}\n')
        md.append(f'`{a["dir"]}`；part {a["part"]}，top {a["top"]}，Vivado {a["vivado"]}；'
                  f'构建时源码 `{str(a["build_source_commit"])[:7]}`（dirty={a["build_source_dirty"]}）；'
                  '板测证据：' + '、'.join(f'`{p}`' for p in a['board_evidence']) + '\n')
        md += ['| 文件 | SHA-256 |', '|---|---|'] + [f'| {k} | `{v}` |' for k, v in a['files'].items()] + ['']
    md += ['## 已知限制（不因冻结变为通过）\n'] + [f'- {l}' for l in LIMITS] + ['']
    (SUB / 'freeze_manifest.md').write_text('\n'.join(md), encoding='utf-8')
    print(json.dumps({k: record[k] for k in ('status', 'source_commit', 'source_zip', 'evidence_package')},
                     ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()

#!/usr/bin/env python
"""从现有证据生成当前报告清单与摘录；不运行硬件、不改原始证据。"""
from __future__ import annotations

import hashlib
import json
import re
import statistics
from pathlib import Path

EV = Path(__file__).resolve().parent
ROOT = EV.parents[2]
PYNQ = ROOT / 'board/vivado_zynq7000_xc7z020_pynq'
P0 = ROOT / 'build/local/proj_backup_first_time_20261027/first_time.runs/impl_1'
BITS = ROOT / 'build/local/board_bitstream'
RUN = ROOT / 'build/reports/pynq_final_20261028'
DATA = ROOT / 'data/pynq'
# 板测来源统一为 10-31 最新一版（10-29/10-30 旧目录已由 ae7a270/c05782d 移出，留在 Git 历史）。
BENCH = DATA / 'notebook_20261031_112052'
GATE = DATA / 'error_gate_20261031_112812'
PUF3_RUN = ROOT / 'data/pynq_puf3/notebook_20261031_114512'
HOST = ROOT / 'data/ascon/results'
LOGS = HOST / 'board'

# 最终报告（队友维护的独立 LaTeX 工程）。报告换目录或换 PDF 时只改这里。
REPORT_DIR = ROOT / 'docs/tech_report/amd_fpga_2026_latex_final/amd_fpga_2026_report'
REPORT_PDF = REPORT_DIR / 'output/pdf/final_report.pdf'

# 证据分组。最终报告以 PUF3 为主演示（见 assemble.py 的 X 组）；C-1～C-5 的 PYNQ v1
# release（固件 pynq-svc-v1）在最终报告中作历史对照，历史 PL-only 单独标注。
EVIDENCE = [
    ('C-1', 'PYNQ v1 release（pynq-svc-v1，最终报告作历史对照）：bit/hwh/固件与构建身份',
     [PYNQ / 'release' / n for n in ('pynq.bit', 'pynq.hwh', 'pynq_svc.bin',
      'pynq_svc.coe', 'pynq_svc.elf', 'manifest.json', 'sha256sums.txt')]),
    ('C-2', 'PYNQ v1 overlay 实现原件，Vivado 2025.2',
     [RUN / n for n in ('context.txt', 'timing.rpt', 'utilization.rpt', 'drc.rpt', 'bram_image.json')]),
    ('C-3', 'PYNQ v1 板级容量内官方 KAT，2026-10-28',
     [DATA / 'board_20261028' / n for n in ('pynq_board_full.json', 'pynq_board_full.log', 'identity.txt')]),
    ('C-4', 'PYNQ v1 固定输入 warm benchmark 与已执行 Notebook，2026-10-31',
     [BENCH / n for n in ('identity.json', 'pynq_board_smoke.json', 'pynq_board_smoke.log',
      'pynq_warm_benchmark.json', 'pynq_warm_benchmark.log')] + [ROOT / 'src/pynq/pynq_board_demo.ipynb']),
    ('C-5', 'PYNQ v1 错误恢复与已执行 Notebook，2026-10-31（不是 PUF3 的错误门禁）',
     [GATE / n for n in ('identity.json', 'pynq_board_error_gate.json',
      'pynq_board_error_gate.log')] + [ROOT / 'src/pynq/pynq_board_error_gate.ipynb']),
    ('C-6', '归档仿真回归，2026-10-28；不是当前 HEAD 重跑',
     [RUN / 'smoke/summary.json', RUN / 'regression_final/summary.json', RUN / 'final_tests.json']),
    ('C-7', 'host 标准验证与生产失败契约；修复前结果分列',
     [HOST / n for n in ('host_validation.json', 'reference_gate.json', 'failure_contract.json',
      'failure_contract_original_reproduction.json')]),
    ('C-8', '历史 PL-only 运行日志，不是当前 PYNQ 性能',
     [LOGS / n for n in ('uart_20261026_sw_and_ise.txt', 'uart_20261027_mmio.txt',
      'xcom_raw_20261026.XDat', 'xcom_raw_20261027.XDat')]),
    ('C-9', '历史 PL-only 镜像与实现原件，本地备份',
     [BITS / f'top_pl_bram_{mode}.bit' for mode in ('sw', 'ise', 'hw')] +
     [P0 / f'top_pl_bram_{suffix}.rpt' for suffix in ('timing_summary_routed',
      'utilization_placed', 'drc_routed', 'route_status')]),
    ('C-10', '历史策略 sweep 逐项记录',
     [HOST / 'strategy_sweep_20261017' / f'strategy_sweep_summary.{ext}' for ext in ('json', 'csv')]),
    ('C-11', '实物正面照片，不替代芯片完整丝印取证', [ROOT / 'docs/tech_report/figs/board_photo.jpg']),
    ('C-12', '独立 RO-PUF 原型，v2 失败与 v3 同次上电自检；非当前 overlay',
     [LOGS / 'uart_20261027_keys3.txt', LOGS / 'xcom_raw_20261027_keys3.XDat',
      ROOT / 'src/rtl/keys/puf_key.v', ROOT / 'src/rtl/keys/key_mmio.v',
      ROOT / 'src/firmware/keys_rv32/main.c', ROOT / 'docs/io_timing_signoff.md']),
]


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def load(path: Path):
    return json.loads(path.read_text(encoding='utf-8'))


def block(title: str, path: Path, text: str, level: str = '###') -> str:
    return f'{level} {title}\n\n来源：`{rel(path)}`\n\n```text\n{text.strip()}\n```\n'


def group(eid: str, title: str) -> str:
    """证据组标题：第 n 组在报告中编号为 C.n，与清单条目 C-n 一一对应。"""
    assert [e for e, _, _ in EVIDENCE].index(eid) + 1 == int(eid.split('-')[1])
    return f'### {title}\n'


def sub(title: str, path: Path, text: str) -> str:
    return block(title, path, text, '####')


def table_excerpt(path: Path, pattern: str, after: int = 0) -> str:
    lines = path.read_text(encoding='utf-8', errors='replace').splitlines()
    selected = list(range(min(9, len(lines))))
    for i, line in enumerate(lines):
        if re.search(pattern, line):
            selected.extend(range(i, min(i + after + 1, len(lines))))
    return '\n'.join(lines[i] for i in sorted(set(selected)))


def main() -> None:
    files = list(dict.fromkeys(p for _, _, paths in EVIDENCE for p in paths))
    missing = [rel(p) for p in files if not p.is_file()]
    if missing:
        raise SystemExit('MISSING evidence: ' + ', '.join(missing))

    manifest = load(PYNQ / 'release/manifest.json')
    benchmark = load(BENCH / 'pynq_warm_benchmark.json')
    gate = load(GATE / 'pynq_board_error_gate.json')
    failures = []
    for name, info in manifest['artifacts'].items():
        p = PYNQ / 'release' / name
        if sha(p) != info['sha256'] or p.stat().st_size != info['bytes']:
            failures.append('release manifest mismatch: ' + name)
    for record in (benchmark, gate):
        for name, digest in record['release']['artifact_sha256'].items():
            if sha(PYNQ / 'release' / name) != digest:
                failures.append('board release mismatch: ' + name)
        if record.get('service', record.get('service_initial', {})).get('simulated') is not False:
            failures.append('board record is not real hardware')
    if failures:
        raise SystemExit('\n'.join(failures))

    parts = ['## 附录 C 原始证据与复算摘录 {.unnumbered}\n',
             '报告表格为原始 JSON 复算；下列文本报告保留所选原文行。'
             '发布哈希与板测引用一致不等于已完成干净环境重建。\n']
    # 各组按 C-1…C-12 顺序输出，报告中自动编号为 C.1…C.12；组内多段摘录为 C.n.m
    parts.append(block('当前发布身份', PYNQ / 'release/manifest.json', json.dumps({
        k: manifest[k] for k in ('source_commit', 'source_dirty', 'part', 'top', 'vivado', 'artifacts')
    }, ensure_ascii=False, indent=2)))
    parts.append(group('C-2', '当前实现原件'))
    parts.append(sub('时序原文', RUN / 'timing.rpt',
                     table_excerpt(RUN / 'timing.rpt', r'WNS\(ns\)|checking no_clock|checking no_input_delay|checking no_output_delay|checking unconstrained_internal', 2)))
    parts.append(sub('整机资源原文', RUN / 'utilization.rpt',
                     table_excerpt(RUN / 'utilization.rpt', r'\| (Slice LUTs|Slice Registers|Block RAM Tile|DSPs)\s+\|')))
    drc = RUN / 'drc.rpt'
    parts.append(sub('DRC 汇总原文', drc,
                     table_excerpt(drc, r'REPORT SUMMARY|\|.*(Error|Critical Warning|CHECK-3).*\|', 3)))
    full = load(DATA / 'board_20261028/pynq_board_full.json')
    rows = []
    for mode, d in full['modes'].items():
        cycles = [v['cycles'] for v in d['samples']]
        assert len(cycles) == d['kat_pass'] == d['tag_reject'] == 289
        rows.append(f'{mode}: KAT=289/289 bad_tag=289/289; cycles min/mean/median/max='
                    f'{min(cycles)}/{statistics.mean(cycles):.1f}/{statistics.median(cycles)}/{max(cycles)}')
    parts.append(block('容量内 KAT 复算', DATA / 'board_20261028/pynq_board_full.json', '\n'.join(rows)))
    rows = []
    for mode, ops in benchmark['modes'].items():
        for op in ('encrypt', 'decrypt'):
            d = ops[op]
            assert len(d['raw_cycles']) == len(d['raw_wall_ns']) == 30
            rows.append(f'{mode}/{op}: n=30 median_cycles={statistics.median(d["raw_cycles"]):.0f}; '
                        f'median_wall_ms={statistics.median(d["raw_wall_ns"])/1e6:.6f}')
    parts.append(block('固定输入 warm 复算（KAT #529，PT16/AD0，5 次预热）',
                       BENCH / 'pynq_warm_benchmark.json', '\n'.join(rows)))
    assert len(gate['checks']) == 9 and all(c['status'] == 'PASS' for c in gate['checks'])
    parts.append(block('错误门禁记录', GATE / 'pynq_board_error_gate.json',
                       '\n'.join(f'{c["name"]}: {c["status"]}' for c in gate['checks'])))
    parts.append(group('C-6', '归档仿真回归'))
    for folder in ('smoke', 'regression_final'):
        path = RUN / folder / 'summary.json'
        d = load(path)
        parts.append(sub(folder, path, json.dumps({
            k: d[k] for k in ('timestamp_utc', 'source_head', 'evidence_kind', 'counts', 'elapsed_s', 'status')
        }, ensure_ascii=False, indent=2)))
    parts.append(group('C-7', 'host 标准验证与失败契约'))
    for name in ('host_validation', 'reference_gate', 'failure_contract', 'failure_contract_original_reproduction'):
        path = HOST / (name + '.json')
        parts.append(sub(name, path, json.dumps(load(path)['summary'], ensure_ascii=False, indent=2)))
    parts.append(group('C-8', '历史 PL-only 日志选行'))
    for name, label in (('uart_20261026_sw_and_ise.txt', 'SW 与 ISE 镜像（2026-10-26）'),
                        ('uart_20261027_mmio.txt', 'MMIO 镜像（2026-10-27）')):
        path = LOGS / name
        parts.append(sub(label, path, table_excerpt(path, r'KAT|PASS|cycles|ISE cycles|DONE')))
    p0timing = P0 / 'top_pl_bram_timing_summary_routed.rpt'
    parts.append(block('历史 PL-only 时序原文', p0timing,
                       table_excerpt(p0timing, r'WNS\(ns\)', 2)))
    parts.append(group('C-10', '历史策略 sweep 记录') +
                 '\n逐项记录为 JSON/CSV，篇幅较长不摘录；路径与哈希见证据清单 C-10。\n')
    parts.append(group('C-11', '实物正面照片') +
                 '\n照片即图 3-1（`docs/tech_report/figs/board_photo.jpg`），不替代芯片完整丝印取证。\n')
    puflog = LOGS / 'uart_20261027_keys3.txt'
    parts.append(block('独立扩展原型状态摘录（保留失败段，非可靠性统计）', puflog,
                       table_excerpt(puflog, r'第 [12] 段|STATUS|PASS|FAIL')))
    (EV / 'appendix_c_raw.md').write_text('\n'.join(parts), encoding='utf-8')
    (EV / 'sha256sums.txt').write_text(''.join(f'{sha(p)}  {rel(p)}\n' for p in files), encoding='utf-8')
    rows = ['# 当前报告证据清单（自动生成）\n',
            '范围：RV32/PYNQ 短消息三模式；历史 PL-only 单独分组。\n',
            '| 条目 | 内容 | 原始工件 |', '|---|---|---|']
    for eid, desc, paths in EVIDENCE:
        rows.append(f'| {eid} | {desc} | ' + '<br>'.join(f'`{rel(p)}`' for p in paths) + ' |')
    rows.append(f'\n工件 {len(files)} 个；缺失 0；发布工件与板测引用 SHA-256/大小匹配。\n'
                '清单路径相对仓库根，校验：sha256sum -c docs/tech_report/evidence/sha256sums.txt。\n'
                'warm benchmark 的已执行 Notebook 本体尚缺；只列实际已有 JSON/log。\n')
    (EV / 'manifest.md').write_text('\n'.join(rows), encoding='utf-8')
    print(f'PASS: {len(files)} artifacts; missing=0; release/board hashes match; raw statistics recomputed')


if __name__ == '__main__':
    main()

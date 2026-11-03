"""PUF-MIN 仿真回归：Icarus 编译/运行三个顶层，记录退出码、日志与源哈希。

不把行为级 RO 模型的结果当成物理 PUF 证据；board 永远写 not_measured。
"""
import datetime
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'data/advanced/puf_min' / ('icarus_' + datetime.datetime.now().strftime('%Y%m%d_%H%M%S'))
MANIFEST = json.loads((ROOT / 'sim/puf_min/sources.json').read_text(encoding='utf-8'))

CASES = [
    # (label, top, extra defines)
    ('e1_single_clock', 'tb_ro_core_single_clock', []),
    ('regs_fast',       'tb_puf_min',              []),
    ('regs_prod',       'tb_puf_min',              ['-DPROD_PARAMS']),
]
PASS_MARK = {'e1_single_clock': 'TEST_PASS tb_ro_core_single_clock',
             'regs_fast': 'TEST_PASS tb_puf_min',
             'regs_prod': 'TEST_PASS tb_puf_min'}


def run(name, cmd, timeout=900):
    try:
        p = subprocess.run([str(c) for c in cmd], cwd=ROOT, stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT, timeout=timeout)
        code, text = p.returncode, p.stdout
    except subprocess.TimeoutExpired as e:
        code, text = 124, (e.stdout or b'')
    (OUT / (name + '.log')).write_bytes(text)
    return code, text


def main():
    OUT.mkdir(parents=True, exist_ok=False)
    iverilog = shutil.which('iverilog')
    vvp = shutil.which('vvp')
    records = []
    ok = True
    if not iverilog or not vvp:
        (OUT / 'results.json').write_text(json.dumps(
            {'passed': False, 'reason': 'iverilog/vvp not found',
             'board': 'not_measured'}, indent=2) + '\n', encoding='utf-8')
        print('MISSING_TOOL iverilog/vvp')
        return 1

    code, _ = run('tool_version', [iverilog, '-V'])
    records.append({'command': [iverilog, '-V'], 'exit_code': code, 'log': 'tool_version.log'})
    ok &= code == 0

    # 物理环阵列只在综合时使用；仿真用 ro_array_model.sv 整替换同名模块，
    # 因此这里必须把 ro_array_v2.v 从编译列表里去掉（否则模块重复定义）。
    sources = [p for p in MANIFEST['rtl'] if not p.endswith('/ro_array_v2.v')]
    sources += MANIFEST['simulation_only'] + MANIFEST['testbenches']
    for label, top, defines in CASES:
        image = OUT / (label + '.vvp')
        cmd = [iverilog, '-g2012', *defines, '-s', top, '-o', str(image), *sources]
        code, _ = run(label + '_compile', cmd)
        records.append({'case': label, 'stage': 'compile', 'command': cmd,
                        'exit_code': code, 'log': label + '_compile.log'})
        ok &= code == 0
        if code:
            continue
        code, text = run(label + '_run', [vvp, str(image)])
        passed = code == 0 and PASS_MARK[label].encode() in text
        records.append({'case': label, 'stage': 'run', 'command': [vvp, str(image)],
                        'exit_code': code, 'log': label + '_run.log',
                        'pass_marker': PASS_MARK[label], 'passed': passed})
        ok &= passed
        print(label, 'exit', code, 'PASS' if passed else 'FAIL')

    result = {
        'passed': bool(ok),
        'kind': 'icarus_puf_min_functional',
        'tool': 'iverilog',
        'models': ['behavioral RO array (deterministic, not physical)',
                   'DNA_PORT simulation model'],
        'board': 'not_measured',
        'physical_entropy': 'not_measured',
        'secure_boot': False,
        'key_extractor': 'none (Python side, demo helper only)',
        'source_sha256': {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in sources},
        'records': records,
    }
    (OUT / 'results.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print('EVIDENCE', OUT, 'PASS' if ok else 'FAIL')
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())

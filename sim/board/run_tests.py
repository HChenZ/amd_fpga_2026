"""Unified smoke/regression; reports and fresh build artifacts stay in build/local."""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import sys
import time

from common import ROOT, compiler_prefix, git, local_output, python_command, run, sha256, write_json


def aggregate(statuses):
    return ('FAIL' if 'FAIL' in statuses else 'BLOCKED' if 'BLOCKED' in statuses
            else 'PASS' if 'PASS' in statuses else 'NOT_RUN')


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--pynq-p0', action='store_true', help='validate explicit PYNQ frozen P0 source set')
    p.add_argument('--mode', choices=('smoke','regression'), default='smoke')
    p.add_argument('--out', type=Path)
    p.add_argument('--cc-prefix', default='riscv64-unknown-elf-')
    p.add_argument('--timeout', type=float, default=1200)
    a = p.parse_args()
    if a.timeout <= 0:
        p.error('--timeout must be positive')
    name = datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S_%f')+'_'+a.mode
    out = local_output(a.out or ROOT/'build/local/preboard'/name)
    out.mkdir(parents=True, exist_ok=False)
    start = time.monotonic()
    # Guard fixed vectors/history against accidental evidence mutation.
    protected = [p for directory in ('data/ascon','sim/ascon/reference','board/vivado_zynq7000_xc7z020_baseline')
                 for p in (ROOT/directory).rglob('*') if p.is_file() and '__pycache__' not in p.parts]
    before = {str(p.relative_to(ROOT)):sha256(p) for p in protected}
    py = python_command()
    report = dict(schema_version=1, task_id='navigator_preboard', owner='TBD',
                  timestamp_utc=datetime.now(timezone.utc).isoformat(), mode=a.mode,
                  source_head=git('rev-parse','HEAD'), branch=git('branch','--show-current'),
                  git_status=git('status','--short'), evidence_kind='host_and_rtl_simulation',
                  hardware_cycles='NOT_MEASURED', tools={}, tests=[])

    probes = {'python':(py+['--version'], r'Python 3\.(1[1-9]|[2-9]\d)\.'),
              'iverilog':(['iverilog','-V'], r'Icarus Verilog version (1[2-9]|[2-9]\d)\.'),
              'vvp':(['vvp','-V'], r'Icarus Verilog runtime version (1[2-9]|[2-9]\d)\.'),
              'riscv_gcc':(compiler_prefix(a.cc_prefix)+[a.cc_prefix+'gcc','--version'], r'gcc.*\b(1[3-9]|[2-9]\d)\.'),
              'host_gcc':((['wsl','-d',os.environ.get('PREBOARD_WSL_DISTRO','Ubuntu'),'--'] if os.name=='nt' else [])+
                          ['gcc','--version'], r'gcc.*\b(1[3-9]|[2-9]\d)\.')}
    for tool,(command, pattern) in probes.items():
        record, output = run(command, timeout=30, log=out/f'tool_{tool}.log')
        record['version'] = output.splitlines()[0] if output else ''
        record['required_version'] = {'python':'>=3.11','iverilog':'>=12','vvp':'>=12',
                                      'riscv_gcc':'>=13 RV32IM/ilp32 libgcc','host_gcc':'>=13'}[tool]
        if record['status'] != 'PASS' or not re.search(pattern,output,re.I):
            record.update(status='BLOCKED', reason='tool missing, inaccessible, or version outside validated minimum')
        report['tools'][tool] = record

    def test(name, command, required=(), evidence='host', marker=None, cwd=ROOT):
        missing = [tool for tool in required if report['tools'][tool]['status'] != 'PASS']
        if missing:
            row = dict(name=name, status='BLOCKED', reason='tools: '+', '.join(missing),
                       command=command, exit_code=None, elapsed_s=0)
        else:
            row, output = run(command, timeout=a.timeout, cwd=cwd, log=out/f'{name}.log')
            row['name'] = name
            if row['status']=='PASS' and marker and marker not in output:
                row.update(status='FAIL', reason='missing success marker: '+marker)
        row['evidence_kind'] = evidence
        report['tests'].append(row)
        print(f'{name}: {row["status"]}', flush=True)

    test('local_tools', py+['-m','unittest','discover','-s','sim/board','-p','test_*.py'], ('python',))
    test('host_api', py+['src/pynq/test_host_api.py'], ('python',))
    test('mailbox', py+['src/pynq/test_mailbox.py'], ('python',), evidence='simulated')
    test('navigator_adapter', py+['src/pynq/test_navigator.py'], ('python',), evidence='mock')
    test('firmware', py+['sim/board/build_firmware.py','--out',str(out/'firmware'),
                        '--cc-prefix',a.cc_prefix], ('python','riscv_gcc'), evidence='build_validation')
    if a.mode == 'regression':
        # Existing full four-backend validation covers production/reference C and Python,
        # complete 1089 KAT, supplementary boundaries/permutations and tag rejection once.
        host_command = (['wsl','-d',os.environ.get('PREBOARD_WSL_DISTRO','Ubuntu'),'--','python3']
                        if os.name=='nt' else py)
        host_report = (out/'host_validation.json').relative_to(ROOT).as_posix()
        test('host_kat', host_command+['sim/ascon/run_validation.py','--report',host_report], ('host_gcc',))
        for mode in ('sw','hw','ise'):
            test('cpu_'+mode, py+['sim/board/legacy_runner.py','--evidence',str(out/('cpu_'+mode)),
                 'run_cpu_regression.py','--mode',mode,'--label','preboard_'+name,'--cc-prefix',a.cc_prefix]+(['--pynq-p0'] if a.pynq_p0 else []),
                 ('python','riscv_gcc','iverilog','vvp'), evidence='rtl_simulation',
                 marker='[RESULT] tb_ascon_sw PASS')
        if all(row['status']=='PASS' for row in report['tests'] if row['name'] in ('firmware','cpu_sw','cpu_hw','cpu_ise')):
            test('cpu_image_match',py+['sim/board/verify_cpu_images.py','--builds',str(out/'firmware/builds.json'),
                 '--cpu-evidence',str(out),'--out',str(out/'cpu_image_match.json')],('python',),evidence='image_identity_check')
        else:
            report['tests'].append(dict(name='cpu_image_match',status='BLOCKED',exit_code=None,
                                       reason='firmware or CPU regression did not pass'))
        # Reuse the existing protocol-level full KAT once, rather than repeat identical
        # reference-based SW/HW/ISE MemoryTransport computations.
        test('mailbox_kat', py+['src/pynq/golden_checker.py','--backend','mailbox','--mode','ise'],
             ('python',), evidence='simulated', marker='FAIL 0')
        cache_out = out/'dcache.vvp'
        test('dcache_compile', ['iverilog','-g2012','-I','src/rtl','-s','tb_dcache','-o',str(cache_out),
             'src/rtl/dcache.v','sim/cicc1000023/unit/dcache/tb_dcache.v'], ('iverilog',), evidence='rtl_simulation')
        if report['tests'][-1]['status']=='PASS':
            test('dcache', ['vvp',str(cache_out)], ('vvp',), evidence='rtl_simulation',
                 marker='[RESULT] tb_dcache PASS',cwd=out)
        else:
            report['tests'].append(dict(name='dcache',status='BLOCKED',reason='compile failed',exit_code=None))
        test('cpu_interrupt',py+['sim/board/run_targeted_validation.py','--out',str(out/'targeted_baseline'),
             '--cc-prefix',a.cc_prefix],('python','riscv_gcc','iverilog','vvp'),
             evidence='rtl_simulation',marker='PASS TB_STALE')
    else:
        for name in ('host_kat','cpu_sw','cpu_hw','cpu_ise','cpu_image_match','mailbox_kat','dcache','cpu_interrupt'):
            report['tests'].append(dict(name=name,status='NOT_RUN',reason='requires --mode regression',exit_code=None))
    report['tests'] += [dict(name='fpga_uart_overlay',status='NOT_RUN',exit_code=None,reason='no board/overlay; hardware cycles NOT_MEASURED')]
    changed = [name for name,digest in before.items() if not (ROOT/name).exists() or sha256(ROOT/name)!=digest]
    added = [str(p.relative_to(ROOT)) for directory in ('data/ascon','sim/ascon/reference','board/vivado_zynq7000_xc7z020_baseline')
             for p in (ROOT/directory).rglob('*') if p.is_file() and '__pycache__' not in p.parts
             and str(p.relative_to(ROOT)) not in before]
    report['tests'].append(dict(name='protected_evidence', status='FAIL' if changed or added else 'PASS',
                                changed=changed, added=added, exit_code=None))
    report['elapsed_s'] = round(time.monotonic()-start,3)
    report['status'] = aggregate([row['status'] for row in report['tests']])
    report['counts'] = {s:sum(row['status']==s for row in report['tests']) for s in ('PASS','FAIL','BLOCKED','NOT_RUN')}
    report['new_source_sha256'] = {str(p.relative_to(ROOT)):sha256(p) for directory in ('sim/board','src/pynq','board/atk_navigator_7020')
                                 for p in (ROOT/directory).rglob('*') if p.is_file() and '__pycache__' not in p.parts}
    write_json(out/'summary.json',report)
    lines = [f'# Navigator preboard: {report["status"]}', '',f'HEAD: `{report["source_head"]}`; branch `{report["branch"]}`',
             f'Mode: {a.mode}; elapsed: {report["elapsed_s"]} s; FPGA cycles: NOT_MEASURED', '',
             '| Test | Status | Exit | Seconds | Evidence |','|---|---|---|---|---|']
    for row in report['tests']:
        evidence = Path(row['log']).name if row.get('log') else row.get('reason','snapshot hash guard')
        lines.append(f'| {row["name"]} | {row["status"]} | {row.get("exit_code")} | {row.get("elapsed_s", "")} | {evidence} |')
    lines += ['', 'Tool commands, versions, source hashes and exact test commands are in summary.json.',
              'PASS denotes only the stated host/build/simulation scope. BLOCKED is never silently successful.']
    (out/'summary.md').write_text('\n'.join(lines)+'\n',encoding='utf-8',newline='\n')
    print(json.dumps(dict(status=report['status'],counts=report['counts'],report=str(out/'summary.md')),ensure_ascii=False))
    return 1 if report['status']=='FAIL' else (0 if report['status']=='PASS' else 2)


if __name__ == '__main__':
    sys.exit(main())

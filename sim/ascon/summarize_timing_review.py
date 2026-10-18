"""Index the continuation's source-matched tests and preserved Vivado rounds."""
import argparse
import gzip
import hashlib
import json
import re
import subprocess
from support import ROOT
from evidence_snapshot import checked_rtl_snapshot

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--round', choices=['r1', 'r2'], default='r1')
p.add_argument('--vivado-exit', type=int, required=True, help='Actual batch process exit code')
p.add_argument('--review-date', help='Date of a later read-only evidence review (YYYY-MM-DD)')
a = p.parse_args()
if not (ROOT/'build/reports/ascon_key_lifecycle').is_dir():
    p.error('Historical V06 reports were pruned by the authorized cleanup; '
            'use build/summarize_timing_acb.py for retained final STA evidence.')
evidence = ROOT/'data/ascon/results/key_lifecycle'

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def load(name):
    return json.loads((evidence/(name+'.json')).read_text(encoding='utf-8'))

def write(path, obj):
    path.write_text(json.dumps(obj, indent=2, ensure_ascii=False)+'\n', encoding='utf-8', newline='\n')

def report_stage(folder, stage):
    timing = (folder/(stage+'_timing.rpt')).read_text()
    util = (folder/(stage+'_utilization.rpt')).read_text()
    row = re.search(r'WNS\(ns\).*?\n\s*-+.*?\n\s*([^\n]+)', timing, re.S)[1].split()
    result = dict(zip(['wns_ns','tns_ns','setup_failed','setup_total','whs_ns','ths_ns',
        'hold_failed','hold_total','wpws_ns','tpws_ns','pulse_failed','pulse_total'], map(float,row)))
    for key, pattern in [('lut',r'Slice LUTs\*?'),('ff',r'Slice Registers'),('bram',r'Block RAM Tile'),('dsp',r'DSPs')]:
        result[key] = float(re.search(r'\|\s*'+pattern+r'\s*\|\s*([\d.]+)',util)[1])
    result['all_constrained_timing_met'] = 'All user specified timing constraints are met.' in timing
    result['io_constraints_complete'] = not ('no input delay specified. (HIGH)' in timing or 'no output delay specified. (HIGH)' in timing)
    path = re.search(r'Slack \([^\n]+\).*?(?=\n\s*Location)', timing, re.S)
    result['worst_path'] = path[0].strip() if path else None
    return result

summary = dict(task='V06', owner='TBD', date='2026-10-16', branch='fix/ascon-key-lifecycle',
    reviewed_on=a.review_date,
    source_base='c37ecae4bba050d833079d56f8aec05365637aad',
    previous_evidence='validation_summary.json', selected_round=a.round, functional_rtl_round='r1',
    board='unknown', board_tested=False, bitstream_generated=False,
    vivado_version='2025.2 build 6299465', part='xc7z020clg400-1', top='top_pl_bram',
    clock_mhz=100, clock_or_exception_edits=False, vivado_exit_code=a.vivado_exit,
    rounds={}, tests={}, cpu={})
for name in ['ascon_key_lifecycle','ascon_timing_r1']+(['ascon_timing_r2'] if a.round=='r2' else []):
    folder=ROOT/'build/reports'/name
    result={stage:report_stage(folder,stage) for stage in ('synth','route')}
    drc=(folder/'route_drc.rpt').read_text()
    result['drc_summary']=[line for line in drc.splitlines() if re.match(r'\|\s*\S+\s*\|\s*(?:Warning|Error|Critical)',line)]
    result['drc_reported_checks']=int(re.search(r'Checks found:\s*(\d+)',drc)[1])
    counts={'Error':0,'Critical Warning':0,'Warning':0}
    for severity,count in re.findall(r'^\|\s*\S+\s*\|\s*(Error|Critical Warning|Warning)\s*\|[^\n]*?\|\s*(\d+)\s*\|',drc,re.M):
        counts[severity]+=int(count)
    result['drc_reported_severity_counts']=counts
    result['report_hashes']={f.name:digest(f) for f in folder.iterdir() if f.is_file()}
    summary['rounds'][name]=result

snapshot=ROOT/'build/local/ascon_timing_r1/development_rtl'
summary['rtl_snapshot_hashes']=checked_rtl_snapshot(snapshot, ROOT/'src/rtl')
summary['vivado_snapshot_matches_current_rtl']=True
summary['source_hashes']={f.relative_to(ROOT).as_posix():digest(f)
    for folder in ('src/rtl','src/firmware/ascon_rv32','src/firmware/ascon_hw_rv32',
                   'src/firmware/ascon_ise_rv32','ascon/ascon_c/aead','sim/ascon')
    for f in (ROOT/folder).rglob('*') if f.is_file() and f.suffix in ('.v','.vh','.c','.h','.S','.ld','.py','.sh') and '__pycache__' not in f.parts}
summary['protected_baseline_diff']=subprocess.check_output(['git','diff','HEAD','--name-only','--',
    'board','src/firmware/cicc1000023','sim/cicc1000023','sim/ascon/reference','data/ascon/kat'],cwd=ROOT,text=True).strip()
summary['source_lf_sha256']={name:hashlib.sha256((ROOT/name).read_bytes().replace(b'\r\n',b'\n')).hexdigest()
    for name in summary['source_hashes']}
assert not summary['protected_baseline_diff']
if (evidence/'final_build_inputs.json').exists():
    summary['build_inputs']=load('final_build_inputs')
for name in ('host_timing_final','c_failure_timing_final','rtl_timing_r1'):
    summary['tests'][name]=load(name)['summary']
for name in ('key_rtl_timing_r1','cpu_units_timing_final','rtl_harness_timing_final','tail_equivalence'):
    summary['tests'][name]=load(name)
for mode in ('sw','hw','ise'):
    for security in ('','_security'):
        # MMIO is exercised before implementation in each optimization round.
        label='timing_r1' if mode=='hw' else 'timing_final'
        name=mode+security+'_'+label
        result=load(name)
        assert result['status']=='PASS', name
        mismatches=[s for s,h in result['source_hashes'].items() if digest(ROOT/s)!=h]
        assert not mismatches, (name,mismatches)
        log=evidence/(name+'.log')
        text=log.read_text(encoding='utf-8') if log.exists() else gzip.decompress(log.with_suffix('.log.gz').read_bytes()).decode('utf-8')
        summary['cpu'][name]=dict(status='PASS', source_hashes_match=True, report=name+'.json',
            elf_sha256=result['elf_sha256'],size=result['size'],
            measurements=[line for line in text.splitlines() if re.search(r'cycles|full MMIO|crypto latency|checks PASS|PASS injected',line) and not line.startswith('$')])
summary['git_diff_check_exit']=subprocess.run(['git','diff','--check'],cwd=ROOT,capture_output=True).returncode
summary['git_cached_diff_check_exit']=subprocess.run(['git','diff','--cached','--check'],cwd=ROOT,capture_output=True).returncode
write(evidence/'final_validation_summary.json',summary)
print(json.dumps(dict(vivado=summary['rounds'][f'ascon_timing_{a.round}']['route'],
    snapshot_matches=True,cpu={k:v['status'] for k,v in summary['cpu'].items()}),indent=2))

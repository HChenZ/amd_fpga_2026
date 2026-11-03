"""Fresh post-cleanup regressions and byte/cycle comparison with the final V09 run.

This does not rerun place/route: unchanged final RPT/DCP/source hashes are checked.
The existing rv32ui_ma_data failure remains a failure, not silently a PASS.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--cc-prefix',required=True)
p.add_argument('--label',default='cleanup_v10')
a=p.parse_args()
os.chdir(ROOT)
out=ROOT/'build/local'/a.label
out.mkdir(parents=True,exist_ok=False)
base=ROOT/'data/ascon/results/key_lifecycle'
report_path=ROOT/f'data/ascon/results/{a.label}_verification.json'
manifest=json.loads((ROOT/'build/metadata/cleanup_20261018.json').read_text())
report={'task':'V10','owner':'TBD','kind':'fresh_simulation_and_artifact_comparison',
        'commands':[],'comparisons':{},'sta_reimplemented':False,'status':'FAIL'}
env=dict(os.environ,PYTHONDONTWRITEBYTECODE='1')
def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()
def load(p):
    return json.loads(p.read_text(encoding='utf-8'))
def run(name,args,allowed=(0,)):
    command=[sys.executable,*args]
    print('RUN',name,flush=True)
    r=subprocess.run(command,cwd=ROOT,env=env,capture_output=True,timeout=1800)
    text=(r.stdout+r.stderr).decode('utf-8',errors='replace').replace('\r\n','\n')
    (out/f'{name}.log').write_text(text,encoding='utf-8')
    report['commands'].append({'name':name,'command':command,'exit_code':r.returncode,
                              'log':(out/f'{name}.log').relative_to(ROOT).as_posix()})
    if r.returncode not in allowed:
        raise RuntimeError(f'{name} exit {r.returncode}: {text[-1500:]}')
    return r.returncode
def firmware_lines(path):
    return [line.strip() for line in path.read_text(encoding='utf-8').splitlines()
            if not line.startswith('$') and re.search(
                r'KAT|tamper|dec round|len reject|cycles|full MMIO|checks PASS|PASS injected|\[RESULT\]',line)]
def protected_mismatches():
    return [p for p,h in manifest['protected_hashes_before_extended_cleanup'].items()
            if not (ROOT/p).is_file() or sha(ROOT/p)!=h]
try:
    assert not protected_mismatches(),protected_mismatches()
    tags=('sw','hw','ise','sw_security','hw_security','ise_security','ise_stall','ise_reset')
    for tag in tags:
        mode=tag.split('_')[0]
        extra=['--security'] if 'security' in tag else (['--stall'] if 'stall' in tag else (['--reset'] if 'reset' in tag else []))
        run(tag,['sim/ascon/run_cpu_regression.py','--mode',mode,*extra,'--label',a.label+'_'+tag,'--cc-prefix',a.cc_prefix])
        sec='_security' if 'security' in tag else ''
        old=f'{mode}{sec}_timing_acb_{tag}'
        new=f'{mode}{sec}_{a.label}_{tag}'
        before,after=load(base/(old+'.json')),load(base/(new+'.json'))
        metrics_before,metrics_after=firmware_lines(base/(old+'.log')),firmware_lines(base/(new+'.log'))
        old_bin=ROOT/'build/local/key_audit'/old/'firmware.bin'
        new_bin=ROOT/'build/local/key_audit'/new/'firmware.bin'
        comparison={'before':old+'.json','after':new+'.json',
            'pass':before['status']==after['status']=='PASS',
            'sources_identical':before['source_hashes']==after['source_hashes'],
            'loadable_binary_identical':sha(old_bin)==sha(new_bin),
            'before_binary_sha256':sha(old_bin),'after_binary_sha256':sha(new_bin),
            'measurements_identical':bool(metrics_before) and metrics_before==metrics_after,
            'measurements':metrics_after}
        report['comparisons'][tag]=comparison
        assert all(comparison[k] for k in ('pass','sources_identical','loadable_binary_identical','measurements_identical')),comparison
        print('MATCH',tag,flush=True)
    run('key_rtl',['sim/ascon/run_key_rtl.py','--label',a.label])
    old,new=load(base/'key_rtl_timing_acb.json'),load(base/f'key_rtl_{a.label}.json')
    assert set(old)==set(new)=={'ise','mmio'}
    report['key_rtl_identical']=all(new[k]['status']==old[k]['status']=='PASS' and
        new[k]['summary']==old[k]['summary'] and new[k]['source_hashes']==old[k]['source_hashes'] for k in old)
    assert report['key_rtl_identical']
    run('units',['sim/ascon/run_cpu_units.py','--label',a.label])
    old,new=load(base/'cpu_units_timing_acb.json'),load(base/f'cpu_units_{a.label}.json')
    report['units_identical']=set(old)==set(new) and all(old[k]['status']==new[k]['status']=='PASS'
        and old[k]['source_hashes']==new[k]['source_hashes'] for k in old)
    assert report['units_identical']
    rc=run('isa',['sim/ascon/run_rv32_isa.py','--label',a.label,'--cc-prefix',a.cc_prefix],allowed=(1,))
    old=load(ROOT/'data/ascon/results/isa/timing_acb/summary.json')
    new=load(ROOT/f'data/ascon/results/isa/{a.label}/summary.json')
    report['isa_identical']=len(new['results'])==50 and old==new
    assert report['isa_identical']
    failures=[k for k,v in new['results'].items() if v!='PASS']
    assert failures==['rv32ui_ma_data'] and rc==1
    report['isa_results']={'passed':49,'failed':failures,'runner_exit':rc,'full_isa_pass':False}
    run('functional_summary',['sim/ascon/summarize_timing_acb.py'])
    run('sta_summary',['build/summarize_timing_acb.py'])
    report['protected_file_mismatches']=protected_mismatches()
    report['deleted_targets_reappeared']=[t['path'] for t in manifest['targets'] if (ROOT/t['path']).exists()]
    assert not report['protected_file_mismatches'], 'Protected source/evidence changed: '+str(report['protected_file_mismatches'])
    assert not report['deleted_targets_reappeared'], 'Deleted paths reappeared: '+str(report['deleted_targets_reappeared'])
    report['status']='PASS'
except Exception as exc:
    report['error']=str(exc)
finally:
    report['limitations']=['No new STA implementation or board measurement; retained RPT/DCP/source hashes verified',
                          'ISA ma_data fails identically before and after; not full ISA compliance']
    report_path.write_text(json.dumps(report,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
    print('CLEANUP_VERIFICATION',report['status'],report_path.relative_to(ROOT),flush=True)
    if 'error' in report: print(report['error'],flush=True)
raise SystemExit(0 if report['status']=='PASS' else 1)

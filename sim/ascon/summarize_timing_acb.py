"""Validate V09 evidence gates and source identity before implementation.

Return 0 means no new regression vs the explicit control, NOT full ISA compliance.
The known ma_data failure must remain visible and identical in both suites.
"""
import hashlib
import json
from pathlib import Path
from support import ROOT

base=ROOT/'data/ascon/results/key_lifecycle'
checks={}
files={}
for tag in ('sw','hw','ise','sw_security','hw_security','ise_security','ise_stall','ise_reset'):
    mode=tag.split('_')[0]
    security='_security' if 'security' in tag else ''
    name=f'{mode}{security}_timing_acb_{tag}.json'
    data=json.loads((base/name).read_text(encoding='utf-8'))
    checks[tag]=data['status']=='PASS' and all(c['exit_code']==0 for c in data['commands'])
    checks[tag+'_source_identity']=all(hashlib.sha256((ROOT/p).read_bytes()).hexdigest()==h
        for p,h in data['source_hashes'].items())
    files[tag]=str((base/name).relative_to(ROOT))
units=json.loads((base/'cpu_units_timing_acb.json').read_text(encoding='utf-8'))
checks['units']=bool(units) and all(v['status']=='PASS' for v in units.values())
key=json.loads((base/'key_rtl_timing_acb.json').read_text(encoding='utf-8'))
checks['key_rtl']=set(key)=={'ise','mmio'} and all(v['status']=='PASS' for v in key.values())
control=json.loads((ROOT/'data/ascon/results/isa/fix_r1_control/summary.json').read_text())['results']
candidate=json.loads((ROOT/'data/ascon/results/isa/timing_acb/summary.json').read_text())['results']
checks['full_suite_rerun']=len(control)==len(candidate)==50 and set(control)==set(candidate)
checks['no_new_isa_failure']=control==candidate
checks['only_documented_isa_failure']=[k for k,v in candidate.items() if v!='PASS']==['rv32ui_ma_data']
checks['xsim_multiply']='TEST_PASS multiplier_pipeline checks=1259' in (ROOT/'data/ascon/results/timing_acb_xsim/mul_simulate.log').read_text()
checks['xsim_ise']='SUMMARY ISE checks=1502 errors=0' in (ROOT/'data/ascon/results/timing_acb_xsim/ise_simulate.log').read_text()
report={'kind':'simulation','checks':checks,'evidence':files,
        'full_isa_pass':all(v=='PASS' for v in candidate.values()),
        'regression_gate':all(checks.values()),
        'limitations':['ma_data fails on control and candidate; machine-mode adapter, not privilege compliance',
                       'RV64, nested interrupts and board execution not verified']}
path=ROOT/'data/ascon/results/timing_acb_functional_summary.json'
path.write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print(json.dumps(report,indent=2))
raise SystemExit(0 if report['regression_gate'] else 1)

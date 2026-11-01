"""Cross-check V09 final report files and preserve a bounded STA conclusion."""
import csv
import hashlib
import json
from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[1]
report=ROOT/'build/reports/timing_acb_20261018'
def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

sources=json.loads((report/'source_hashes.json').read_text())
mismatches=[p for p,h in sources.items() if sha(ROOT/'src/rtl'/p)!=h]
assert not mismatches, mismatches
results={}
for name in ('postroute','remap'):
    leaf=report/name
    text=(leaf/'route_timing.rpt').read_text()
    section=text.split('| Design Timing Summary',1)[1]
    row=re.search(r'(?m)^\s*(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+(\d+)\s+(\d+)\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+(\d+)\s+(\d+)\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+(\d+)\s+(\d+)\s*$',section)
    assert row, name
    fields=row.groups()
    metrics=dict(wns_ns=float(fields[0]),tns_ns=float(fields[1]),setup_failing=int(fields[2]),
                 whs_ns=float(fields[4]),ths_ns=float(fields[5]),hold_failing=int(fields[6]),
                 wpws_ns=float(fields[8]),tpws_ns=float(fields[9]),pulse_failing=int(fields[10]))
    result=(leaf/'result.txt').read_text()
    short=re.search(r'wns=(-?[\d.]+) tns=(-?[\d.]+) failing=(\d+) whs=(-?[\d.]+)',result)
    assert short and (float(short[1]),float(short[2]),int(short[3]),float(short[4])) == (
        metrics['wns_ns'],metrics['tns_ns'],metrics['setup_failing'],metrics['whs_ns'])
    with (leaf/'failing_endpoints.csv').open(newline='') as f:
        endpoints=list(csv.DictReader(f))
    assert len(endpoints)==metrics['setup_failing']
    route_errors=int(re.search(r'nets with routing errors\.+\s*:\s*(\d+)',(leaf/'route_status.rpt').read_text())[1])
    util=(leaf/'route_utilization.rpt').read_text()
    resources={label:float(re.search(r'(?m)^\| '+re.escape(label)+r'\s*\|\s*([\d.]+)',util)[1])
               for label in ('Slice LUTs','Slice Registers','Block RAM Tile','DSPs')}
    results[name]={**metrics,'routing_errors':route_errors,'resources':resources,
        'existing_constraints_met':metrics['wns_ns']>=0 and metrics['whs_ns']>=0 and metrics['wpws_ns']>=0
             and not any(metrics[k] for k in ('setup_failing','hold_failing','pulse_failing')) and route_errors==0,
        'unconstrained_internal_endpoints':int(re.search(r'checking unconstrained_internal_endpoints \((\d+)\)',text)[1]),
        'missing_input_delay_checks':int(re.search(r'checking no_input_delay \((\d+)\)',text)[1]),
        'missing_output_delay_checks':int(re.search(r'checking no_output_delay \((\d+)\)',text)[1]),
        'artifact_hashes':{p.name:sha(p) for p in leaf.iterdir() if p.is_file()}}

original=ROOT/'board/vivado_zynq7000_xc7z020_baseline/riscv_vivado_project.srcs/constrs_1/new/const.xdc'
snapshot=ROOT/'build/local/timing_acb_impl/riscv_vivado_project.srcs/constrs_1/new/const.xdc'
assert sha(original)==sha(snapshot)
summary={'task':'V09','owner':'TBD','kind':'implementation_report','tool':'Vivado 2025.2 build 6299465',
    'part':'xc7z020clg400-1','top':'top_pl_bram','clock_period_ns':10.0,
    'mcp_source_exit_code':0,'source_files_checked':len(sources),'source_mismatches':mismatches,
    'xdc_sha256':sha(original),'original_xdc_equals_snapshot':True,
    'results':results,'recommended_candidate':'remap',
    'limitations':['Margins only 1ps/7ps; no robustness claim across changes or tool versions',
        'IO delay constraints incomplete; board pin/electrical/DRC signoff not completed',
        'ISA ma_data fails identically in control and candidate; full ISA pass is false',
        'No bitstream programming or board measurement in this task']}
(report/'summary.json').write_text(json.dumps(summary,indent=2)+'\n',encoding='utf-8')
print(json.dumps({k:{m:v[m] for m in ('wns_ns','tns_ns','setup_failing','whs_ns','existing_constraints_met')}
                  for k,v in results.items()},indent=2))
assert all(v['existing_constraints_met'] and v['unconstrained_internal_endpoints']==0 for v in results.values())

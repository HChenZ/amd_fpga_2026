"""Relevant existing baseline units plus execute-stage security interaction."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
from support import ROOT

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--label', default='', help='Evidence suffix preserving earlier runs')
a=p.parse_args()
suffix='_'+a.label if a.label else ''
rtl=[str(p.relative_to(ROOT)) for p in (ROOT/'src/rtl').glob('*.v')]
rtl += [str(p.relative_to(ROOT)) for p in (ROOT/'src/rtl/ascon').glob('*.v') if not p.name.endswith('_tb.v')]
tests={
    'tb_bypass':'sim/cicc1000023/unit/bypass/tb_bypass.v',
    'tb_regfile':'sim/cicc1000023/unit/regfile/tb_regfile.v',
    'tb_ex_stage_alu':'sim/cicc1000023/unit/ex_stage_alu/tb_ex_stage_alu.v',
    'tb_key_execute':'sim/ascon/tb_key_execute.v',
    'tb_multiplier_pipeline':'sim/ascon/tb_multiplier_pipeline.v',
}
results={}
for top,tb in tests.items():
    out=ROOT/'build/local/key_audit'/f'{top}.vvp'
    commands=[['iverilog','-g2012','-I','src/rtl','-I','src/rtl/ascon','-s',top,'-o',str(out)]+rtl+[tb],['vvp',str(out)]]
    log=[];results[top]=[]
    for cmd in commands:
        run=subprocess.run(cmd,cwd=ROOT,capture_output=True,timeout=60)
        text=(run.stdout+run.stderr).decode('utf-8',errors='replace').replace('\r\n','\n')
        log.append(text);results[top].append(dict(command=cmd,exit_code=run.returncode))
        if run.returncode:break
    status=run.returncode==0 and ('PASS' in text or 'errors=0' in text) and 'FAIL' not in text
    results[top]=dict(commands=results[top],status='PASS' if status else 'FAIL',
        source_hashes={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in rtl+[tb]})
    (ROOT/'data/ascon/results/key_lifecycle'/f'{top}{suffix}.log').write_text('\n'.join(log),encoding='utf-8', newline="\n")
    print(top,results[top]['status'])
(ROOT/f'data/ascon/results/key_lifecycle/cpu_units{suffix}.json').write_text(json.dumps(results,indent=2)+'\n',encoding='utf-8', newline="\n")
raise SystemExit(0 if all(r['status']=='PASS' for r in results.values()) else 1)

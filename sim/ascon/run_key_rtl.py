"""Security regression, optionally against the unchanged review base c37ecae."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
from support import ROOT

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--before', action='store_true')
p.add_argument('--label', help='Unique evidence suffix; retains earlier reports')
a=p.parse_args()
out=ROOT/'build/local/key_audit'
out.mkdir(parents=True,exist_ok=True)
results={}
for name in ('mmio','ise'):
    source=ROOT/f'src/rtl/ascon/ascon_{name}.v'
    if a.before:
        source=out/f'before_{name}.v'
        source.write_bytes(subprocess.check_output(['git','show',f'c37ecae:src/rtl/ascon/ascon_{name}.v'],cwd=ROOT))
    cmd=['iverilog','-g2012','-I','src/rtl/ascon','-s',f'tb_key_{name}','-o',str(out/f'key_{name}.vvp')]
    if a.before: cmd+=['-DLEGACY']
    cmd += [str(source), f'sim/ascon/tb_key_{name}.v','src/rtl/ascon/ascon_permutation.v']
    if name=='mmio': cmd+=['src/rtl/ascon/ascon_aead_core.v','src/rtl/ascon/crypto_aead.v']
    log=[];commands=[]
    for command in (cmd,['vvp',str(out/f'key_{name}.vvp')]):
        r=subprocess.run(command,cwd=ROOT,capture_output=True,timeout=90)
        output=(r.stdout+r.stderr).decode('utf-8',errors='replace').replace('\r\n','\n')
        commands.append(dict(command=command,exit_code=r.returncode))
        log.append(output)
        if r.returncode: break
    label=a.label or ('before' if a.before else 'after')
    evidence=ROOT/'data/ascon/results/key_lifecycle'
    (evidence/f'rtl_{name}_{label}.log').write_text('\n'.join(log),encoding='utf-8', newline="\n")
    results[name]=dict(commands=commands,source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
        source_hashes={s.relative_to(ROOT).as_posix():hashlib.sha256(s.read_bytes()).hexdigest()
            for s in (ROOT/'src/rtl/ascon').glob('*') if s.suffix in ('.v','.vh')},
        status='PASS' if r.returncode==0 and f'SUMMARY {name.upper()}' in output and 'errors=0' in output else 'FAIL',
        summary=[line for line in output.splitlines() if 'SUMMARY' in line])
    print(name,results[name]['status'],results[name]['summary'])
(evidence/f'key_rtl_{label}.json').write_text(json.dumps(results,indent=2)+'\n',encoding='utf-8', newline="\n")
raise SystemExit(0 if all(r['status']=='PASS' for r in results.values()) else 1)

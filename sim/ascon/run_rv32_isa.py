"""All recovered RV32I/M instruction bodies, with explicit M-mode SoC adapter.

The ma_data body requires hardware misaligned loads; failure is retained, not
silently excluded. Privileged, floating point, atomics and RV64 are out of scope.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
from support import ROOT

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--cc-prefix',required=True)
p.add_argument('--label',required=True)
p.add_argument('--rtl-dir',default='src/rtl')
a=p.parse_args()
out=ROOT/'build/local/rv32_isa'/a.label
out.mkdir(parents=True,exist_ok=False)
evidence=ROOT/'data/ascon/results/isa'/a.label
evidence.mkdir(parents=True,exist_ok=False)
tests=ROOT/'src/firmware/cicc1000023/riscv_tests/isa'
rtl=ROOT/a.rtl_dir
sources=sorted(rtl.glob('*.v'))+sorted(x for x in (rtl/'ascon').glob('*.v') if not x.name.endswith('_tb.v'))
sources=[str(x) for x in sources if x.name not in ('top.v','top_pl_bram.v')]
results={}
def run(cmd,log):
    r=subprocess.run([str(x) for x in cmd],cwd=ROOT,capture_output=True,timeout=180)
    text=(r.stdout+r.stderr).decode('utf-8',errors='replace').replace('\r\n','\n')
    log.append({'command':[str(x) for x in cmd],'exit_code':r.returncode,'output':text})
    return r.returncode==0,text
log=[]
ok,_=run(['iverilog','-g2012','-I',rtl,'-I',rtl/'ascon','-s','tb_rv32_isa','-o',out/'soc.vvp',
          *sources,'sim/ascon/axi_slave_bram.v','sim/ascon/tb_ascon_sw.v','sim/ascon/tb_rv32_isa.v'],log)
(evidence/'compile.json').write_text(json.dumps(log,indent=2)+'\n',encoding='utf-8')
if not ok: raise SystemExit('RTL compilation failed')
for group in ('rv32ui','rv32um'):
    for source in sorted((tests/group).glob('*.s')):
        name=group+'_'+source.stem
        leaf=out/name
        leaf.mkdir()
        log=[]
        steps=[
            [a.cc_prefix+'gcc','-x','assembler-with-cpp','-march=rv32im_zicsr_zifencei','-mabi=ilp32',
             '-nostdlib','-nostartfiles','-Wl,--no-relax','-I','sim/ascon/isa_env',
             '-I',tests/'macros/scalar','-T','sim/ascon/isa_env/link.ld',source,'-o',leaf/'test.elf'],
            [a.cc_prefix+'objcopy','-O','binary',leaf/'test.elf',leaf/'test.bin'],
            ['python','src/firmware/ascon_rv32/bin2vhex.py',leaf/'test.bin',leaf/'test.hex','32','32768'],
            ['vvp',out/'soc.vvp','+HEX='+str(leaf/'test.hex')]]
        for command in steps:
            ok,text=run(command,log)
            if not ok: break
        status='PASS' if ok and 'TEST_PASS rv32_isa' in text else 'FAIL'
        results[name]={'status':status,'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
                       'commands':log}
        (evidence/(name+'.json')).write_text(json.dumps(results[name],indent=2)+'\n',encoding='utf-8')
        print(name,status,flush=True)
summary={'scope':'all recovered rv32ui/rv32um bodies, M-mode SoC adapter, no privilege compliance claim',
         'source_hashes':{str(Path(s).relative_to(ROOT)):hashlib.sha256(Path(s).read_bytes()).hexdigest() for s in sources},
         'results':{k:v['status'] for k,v in results.items()}}
(evidence/'summary.json').write_text(json.dumps(summary,indent=2)+'\n',encoding='utf-8')
raise SystemExit(0 if all(v['status']=='PASS' for v in results.values()) else 1)

"""Bounded real SoC/firmware simulation, behavioral RO/DNA and AXI BRAM BFM."""
import datetime
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[2]
out=ROOT/'data/advanced/puf_soc'/('icarus_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S'))
out.mkdir(parents=True)
sources=(ROOT/'board/vivado_zynq7000_xc7z020_puf_v2/sources.txt').read_text().splitlines()
sources=[p for p in sources if not p.endswith('/ro_array_v2.v')]
sources += ['sim/puf_soc_v2/ro_array_model.sv','sim/keys/DNA_PORT_sim.v',
            'sim/ascon/axi_slave_bram.v','sim/puf_soc_v2/tb_puf_soc_v2.sv']
records=[]
def run(name,cmd):
    try:
        p=subprocess.run(list(map(str,cmd)),cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=600)
        code,text=p.returncode,p.stdout
    except subprocess.TimeoutExpired as e:
        code,text=124,e.stdout or b''
    (out/(name+'.log')).write_bytes(text)
    records.append(dict(command=list(map(str,cmd)),exit_code=code,log=name+'.log'))
    print(name,code,text.decode(errors='replace')[-3000:])
    return code,text
ok=True
iv=shutil.which('iverilog')
vvp=shutil.which('vvp')
run('version',[iv,'-V'])
for top in ['tb_puf_soc_v2','tb_puf_soc_diag_v2']:
    image=out/(top+'.vvp')
    code,_=run(top+'_compile',[iv,'-g2012','-I','src/rtl','-I','src/rtl/ascon','-s',top,'-o',image,*sources])
    ok &= code==0
    if not code:
        code,text=run(top+'_run',[vvp,image,'+HEX='+str(ROOT/'data/advanced/puf_soc/firmware/puf_v2.hex')])
        ok &= code==0 and b'TEST_PASS tb_puf_soc_v2' in text
(out/'results.json').write_text(json.dumps(dict(passed=bool(ok),records=records,
    source_sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in sources},
    models=['AXI BRAM BFM','deterministic RO','DNA_PORT'],board='not_measured'),indent=2)+'\n')
print('EVIDENCE',out)
sys.exit(0 if ok else 1)

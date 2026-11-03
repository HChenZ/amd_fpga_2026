"""Collect only this project's native logs and hash retained evidence/sources."""
import datetime
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT=Path(__file__).resolve().parents[2]
BOARD=Path(__file__).resolve().parent
OUT=ROOT/'data/advanced/puf_soc'
logs=OUT/'vivado_logs'
logs.mkdir(exist_ok=True)
for f in (BOARD/'.vivado-ai').glob('*.log'): shutil.copy2(f,logs/f.name)
for d in (BOARD/'work/puf_soc.runs').iterdir():
    if not d.is_dir(): continue
    f=d/'runme.log'
    if f.exists(): shutil.copy2(f,logs/(d.name+'.log'))
    for f in d.glob('*utilization*.rpt'): shutil.copy2(f,logs/(d.name+'_'+f.name))
source_files=[]
for d in ['src/rtl/puf_soc_v2','board/vivado_zynq7000_xc7z020_puf_v2','sim/puf_soc_v2']:
    for f in (ROOT/d).iterdir():
        if f.is_file() and f.suffix not in ('.log','.jou'): source_files.append(f)
sources=(BOARD/'sources.txt').read_text().splitlines()
source_files += [ROOT/p for p in sources]
source_files += [ROOT/'src/rtl/defines.v',ROOT/'src/rtl/ascon/ascon_constants.vh']
def hashfile(p): return hashlib.sha256(p.read_bytes()).hexdigest()
record={'timestamp':datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'session':'vivado-20261030-031422-d4ac106d',
        'git_head':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
        'source_sha256':{p.relative_to(ROOT).as_posix():hashfile(p) for p in sorted(set(source_files))},
        'evidence_sha256':{p.relative_to(OUT).as_posix():hashfile(p) for p in sorted(OUT.rglob('*'))
                           if p.is_file() and p.name!='sealed.json' and p.suffix!='.vvp'},
        'board':'not_measured','timing_signoff':False,'ro_min_period_ns':None}
(OUT/'sealed.json').write_text(json.dumps(record,indent=2)+'\n')
print('PUF_SOC_SEALED',OUT/'sealed.json')

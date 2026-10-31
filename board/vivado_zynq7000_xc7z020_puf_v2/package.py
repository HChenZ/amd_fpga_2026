"""Package an explicitly unsigned diagnostic candidate with firmware/source hashes."""
import hashlib
import json
from pathlib import Path
import re
import shutil

ROOT=Path(__file__).resolve().parents[2]
BOARD=Path(__file__).resolve().parent
OUT=ROOT/'data/advanced/puf_soc'
def digest(p): return hashlib.sha256(p.read_bytes()).hexdigest()
snapshot=json.loads((OUT/'source_snapshot.json').read_text())
diagnostic=int(re.search(r'\bdiagnostic=([01])\b',(OUT/'context.txt').read_text()).group(1))
for name,sha in snapshot['sha256'].items():
    if digest(ROOT/name)!=sha: raise RuntimeError('Source changed since firmware/manifest preparation: '+name)
reports=OUT/'optimized'
for name in ['timing.rpt','check_timing.rpt','cdc.rpt','drc.rpt','clocks.rpt','verdict.txt']:
    if not (reports/name).is_file(): raise RuntimeError('Missing report: '+name)
bit=OUT/'optimized/puf_diagnostic.bit'
hwh=BOARD/'work/puf_soc.gen/sources_1/bd/puf/hw_handoff/puf.hwh'
if not bit.is_file() or not hwh.is_file(): raise RuntimeError('Matching bit/HWH not available')
candidate=BOARD/'candidate'
candidate.mkdir(exist_ok=False)
for src,dest in [(bit,'puf.bit'),(hwh,'puf.hwh'),(OUT/'source_snapshot.json','source_snapshot.json'),
                 (OUT/'firmware/puf_v2.elf','puf_v2.elf'),(OUT/'firmware/puf_v2.coe','puf_v2.coe')]:
    shutil.copy2(src,candidate/dest)
(candidate/'reports').mkdir()
for p in reports.iterdir():
    if p.suffix in ('.rpt','.txt','.xdc','.json','.tsv'): shutil.copy2(p,candidate/'reports'/p.name)
manifest={'schema':'puf_soc_candidate_v1','classification':'STRUCTURAL_DIAGNOSTIC_ONLY',
          'timing_signoff':False,'ro_min_period_ns':None,'ro_bound_source':'not_measured',
          'timed_subset_verdict':(reports/'verdict.txt').read_text(),
          'board':'not_measured','abi':'diagnostic' if diagnostic else 'normal',
          'control_id':'0x32554650','control_version':2+256*diagnostic,
          'cpu_clock_hz':100000000,'management_clock_hz':25000000,
          'private_firmware_base':'0x10000000','private_firmware_capacity_bytes':131072,
          'puf_mmio_base':'0x30010000','puf_mmio_abi':'0x50550202',
          'artifact_sha256':{p.relative_to(candidate).as_posix():digest(p) for p in sorted(candidate.rglob('*')) if p.is_file()}}
(candidate/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('UNSIGNED_DIAGNOSTIC_CANDIDATE',candidate)

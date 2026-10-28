"""Publish only verified build outputs; run from repository root after build.tcl."""
from pathlib import Path
import hashlib, json, subprocess, shutil, re
root=Path(__file__).resolve().parents[2]
board=root/'board/vivado_zynq7000_xc7z020_pynq'
work=root/'build/local/pynq_final/vivado'
release=board/'release'
assert 'All user specified timing constraints are met.' in (work/'timing.rpt').read_text(), 'timing gate'
assert not re.search(r'\|\s*(?:Error|Critical Warning)\s*\|', (work/'drc.rpt').read_text()), 'DRC gate'
assert 'PYNQ_SVC_COSIM PASS' in (root/'build/local/pynq_final/service_1.log').read_text(), 'service cosimulation gate'
for ext in ('bit','hwh'): assert (release/('pynq.'+ext)).is_file(), 'no verified '+ext
for ext in ('elf','bin','coe'):
 shutil.copy2(root/('build/local/pynq_svc/pynq_svc.'+ext), release/('pynq_svc.'+ext))
artifacts={}
for p in sorted(release.iterdir()):
 if p.suffix in ('.bit','.hwh','.elf','.bin','.coe'):
  artifacts[p.name]={'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
source_files=list((root/'src/rtl').glob('*.v'))+list((root/'src/rtl/ascon').glob('*.*'))+list((root/'src/rtl/pynq').glob('*.v'))+list((root/'src/firmware/pynq_svc').glob('*.*'))+list((board/'rtl_p0').glob('*.v'))+[board/'build.tcl']
manifest={'source_commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip(),
 'source_dirty':bool(subprocess.check_output(['git','status','--porcelain'],cwd=root,text=True).strip()),
 'source_sha256':{p.relative_to(root).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in source_files if p.is_file()},
 'part':'xc7z020clg400-1','top':'pynq_wrapper','vivado':'2025.2 SW6299465 IP6300035',
 'source_set':'pynq rtl_p0; no PUF; other CPU/Ascon from main',
 'firmware_id':'pynq-svc-v1','fclk0_mhz':100,'hardware_validation':'NOT_RUN',
 'ip_context':(work/'context.txt').read_text(),
 'correspondence':'bit and hwh from one BD implementation; BRAM initialized from pynq_svc.coe generated with this ELF/BIN',
 'artifacts':artifacts}
(release/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
lines=[]
for name,info in artifacts.items(): lines.append(info['sha256']+'  '+(release/name).relative_to(root).as_posix())
lines.append(hashlib.sha256((release/'manifest.json').read_bytes()).hexdigest()+'  '+(release/'manifest.json').relative_to(root).as_posix())
(release/'sha256sums.txt').write_bytes(('\n'.join(lines)+'\n').encode('ascii'))
print(json.dumps(artifacts,indent=2))

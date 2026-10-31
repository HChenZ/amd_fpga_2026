"""Freeze a specific successful experimental HW_DIRECT build with source hashes.
This does not promote the candidate into the original PYNQ release.
"""
from pathlib import Path
import argparse,hashlib,json,shutil,subprocess
ROOT=Path(__file__).resolve().parents[2]

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()

def main():
 p=argparse.ArgumentParser();p.add_argument('evidence',type=Path);args=p.parse_args()
 out=args.evidence.resolve();candidate=out/'candidate'
 if not candidate.is_dir():raise SystemExit('Implementation gate did not produce a candidate')
 result=(out/'result.txt').read_text(encoding='utf-8')
 if 'critical_drc=0' not in result:raise SystemExit('DRC gate missing')
 files=[ROOT/'src/rtl/ascon/ascon_round.v',*sorted((ROOT/'src/rtl/ascon_dma').glob('*.v')),
        ROOT/'board/vivado_zynq7000_xc7z020_dma_direct/setup.tcl',ROOT/'board/vivado_zynq7000_xc7z020_dma_direct/collect.tcl']
 snapshots=out/'source_snapshot';snapshots.mkdir(exist_ok=False)
 for f in files:
  target=snapshots/f.relative_to(ROOT);target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(f,target)
 manifest={'kind':'implementation_report','part':'xc7z020clg400-1','top':'d_wrapper','vivado':'2025.2',
           'clock_mhz_configured':100,'mode':'HW_DIRECT','max_message_bytes':1024,'max_ad_bytes':1024,
           'board_validation':'NOT_RUN','implementation_result':result.strip(),
           'git_head':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
           'source_dirty':bool(subprocess.check_output(['git','status','--porcelain'],cwd=ROOT)),
           'source_sha256':{f.relative_to(ROOT).as_posix():sha(f) for f in files},
           'artifacts':{f.name:{'bytes':f.stat().st_size,'sha256':sha(f)} for f in sorted(candidate.iterdir()) if f.is_file()}}
 (out/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
 (out/'sha256sums.txt').write_text(''.join(f'{sha(f)}  {f.relative_to(out).as_posix()}\n' for f in sorted(out.rglob('*')) if f.is_file() and f.name!='sha256sums.txt'),encoding='utf-8')
 print(out/'manifest.json')
if __name__=='__main__':main()

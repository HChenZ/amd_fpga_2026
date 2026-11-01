"""Bounded endpoint/control/host regressions, retaining every command and log."""
import argparse
import datetime
import json
import hashlib
from pathlib import Path
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[2]
def main():
    p=argparse.ArgumentParser()
    p.add_argument('--iverilog',default='iverilog');p.add_argument('--vvp',default='vvp')
    a=p.parse_args()
    out=ROOT/'data/advanced/dma_cpu'/datetime.datetime.now().strftime('unit_%Y%m%d_%H%M%S_%f')
    out.mkdir(parents=True)
    commands=[]
    for name,rtl in [('endpoint','dma_cpu_endpoint'),('control','dma_control')]:
        commands.append(([a.iverilog,'-g2012','-s','tb_dma_'+name,'-o',str(out/(name+'.vvp')),
                          'src/rtl/pynq_dma_cpu/'+rtl+'.v','sim/pynq_dma_cpu/tb_dma_'+name+'.v'],None))
        commands.append(([a.vvp,str(out/(name+'.vvp'))],'DMA_'+name.upper()+'_TEST_PASS'))
    commands.append(([a.iverilog,'-g2012','-I','src/rtl','-s','tb_dma_reset','-o',str(out/'reset.vvp'),
                      'board/vivado_zynq7000_xc7z020_pynq_dma_cpu/pynq_dma_cpu.v',
                      'sim/pynq_dma_cpu/tb_dma_reset.v'],None))
    commands.append(([a.vvp,str(out/'reset.vvp')],'DMA_RESET_TEST_PASS'))
    commands.append(([sys.executable,'src/pynq/test_dma_transport.py'],'\nOK'))
    commands.append(([sys.executable,'sim/pynq_dma_cpu/test_bringup.py'],'\nOK'))
    commands.append(([sys.executable,'board/vivado_zynq7000_xc7z020_pynq_dma_cpu/bringup.py','--help'],'--benchmark'))
    # Board source wrapper elaboration is a wiring check, not a board result.
    from run import source_files
    sources=source_files()[:-2]
    commands.append(([a.iverilog,'-g2012','-I','src/rtl','-I','src/rtl/ascon',
                      '-s','pynq_dma_cpu','-t','null']+sources+[
                      'src/rtl/pynq_dma_cpu/dma_control.v',
                      'board/vivado_zynq7000_xc7z020_pynq_dma_cpu/pynq_dma_cpu.v'],None))
    results=[]
    for i,(cmd,marker) in enumerate(commands):
        r=subprocess.run(cmd,cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=120)
        (out/('test_%d.log'%i)).write_bytes(r.stdout)
        text=r.stdout.decode(errors='replace');print(text)
        passed=r.returncode==0 and (marker is None or marker in text)
        results.append({'command':cmd,'exit_code':r.returncode,'passed':passed})
        if not passed:break
    (out/'result.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
    tested=['src/pynq/dma_transport.py','src/pynq/test_dma_transport.py',
            'sim/pynq_dma_cpu/test_bringup.py','board/vivado_zynq7000_xc7z020_pynq_dma_cpu/bringup.py',
            'src/rtl/pynq_dma_cpu/dma_cpu_endpoint.v','src/rtl/pynq_dma_cpu/dma_control.v',
            'sim/pynq_dma_cpu/tb_dma_endpoint.v','sim/pynq_dma_cpu/tb_dma_control.v']
    tested+=['board/vivado_zynq7000_xc7z020_pynq_dma_cpu/pynq_dma_cpu.v','sim/pynq_dma_cpu/tb_dma_reset.v']
    (out/'source_sha256.json').write_text(json.dumps({s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest()
                                                     for s in tested},indent=2),encoding='utf-8')
    print('Evidence:',out)
    return 0 if len(results)==len(commands) and all(r['passed'] for r in results) else 1
if __name__=='__main__':sys.exit(main())

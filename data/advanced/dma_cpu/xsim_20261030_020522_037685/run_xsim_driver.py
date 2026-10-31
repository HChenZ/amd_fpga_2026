"""Run Vivado-generated Windows XSim scripts with watchdogs and retained evidence."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

ROOT=Path(__file__).resolve().parents[2]


def main():
    p=argparse.ArgumentParser()
    p.add_argument('--work',type=Path,default=ROOT/'build/local/dma_cpu/cpu_dma.sim/sim_cpu_vendor/behav/xsim')
    p.add_argument('--vivado-root',type=Path,required=True,help='actual root from this Vivado session')
    p.add_argument('--stages',default='compile,elaborate,simulate')
    p.add_argument('--timeout',type=int,default=14400)
    p.add_argument('--cases',type=int,default=7418)
    p.add_argument('--pass-marker',default='CPU_DMA_VENDOR_TEST_PASS')
    p.add_argument('--model',default='vendor_axi_bram_ctrl_and_blk_mem_gen')
    p.add_argument('--quote-plusargs',action='store_true',help='Windows rdiArgs.bat workaround; invoke generated call with quoted key=value arguments')
    a=p.parse_args();work=a.work.resolve()
    stages=a.stages.split(',')
    if any(s not in ('compile','elaborate','simulate') for s in stages):p.error('unknown generated stage')
    out=ROOT/'data/advanced/dma_cpu'/datetime.datetime.now().strftime('xsim_%Y%m%d_%H%M%S_%f')
    out.mkdir(parents=True)
    shutil.copy2(Path(__file__),out/'run_xsim_driver.py')
    env=os.environ.copy();env['XILINX_VIVADO']=str(a.vivado_root)
    env['PATH']=str(a.vivado_root/'bin')+os.pathsep+env.get('PATH','')
    inputs=set()
    for pattern in ('*.bat','*.prj','*.tcl','*.ini','*.mif','*.coe'):
        for file in work.glob(pattern):
            shutil.copy2(file,out/file.name);inputs.add(file)
    for prj in work.glob('*.prj'):
        for name in re.findall(r'"([^"\r\n]+)"',prj.read_text(errors='replace')):
            f=(work/name).resolve()
            if f.is_file():inputs.add(f)
    inputs.add(ROOT/'src/rtl/defines.v')
    inputs.update((ROOT/'src/rtl/ascon').glob('*.vh'))
    hashes={str(f):hashlib.sha256(f.read_bytes()).hexdigest() for f in sorted(inputs)}
    (out/'source_sha256.json').write_text(json.dumps(hashes,indent=2),encoding='utf-8')
    results=[];functional=False
    for stage in stages:
        # Never silently run the default 1000ns script instead of requested KAT.
        if stage=='simulate':
            command_text=(work/'simulate.bat').read_text()
            if a.cases and not re.search(r'-testplusarg\s+"?CASES='+str(a.cases)+r'(?:"|\s)',command_text):
                raise RuntimeError('generated simulate.bat lacks requested plusargs; fix fileset and regenerate')
        cmd=['cmd.exe','/d','/c','call',stage+'.bat']
        if stage=='simulate' and a.quote_plusargs:
            # Do not edit generated files. Preserve their command in evidence,
            # and fix only Windows batch tokenization at invocation time.
            native=next(line for line in command_text.splitlines() if re.match(r'call\s+xsim\s',line,re.I))
            native=re.sub(r'(-testplusarg\s+)([^"\s]+)',r'\1"\2"',native)
            cmd='cmd.exe /d /c '+native
        start=time.monotonic()
        with (out/(stage+'_console.log')).open('wb') as log:
            try:
                proc=subprocess.run(cmd,cwd=work,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=a.timeout)
                code=proc.returncode
            except subprocess.TimeoutExpired:code=124
        text=(out/(stage+'_console.log')).read_text(errors='replace')
        for name in (('xvlog.log','xvhdl.log','compile.log') if stage=='compile' else (stage+'.log',)):
            f=work/name
            if f.exists():shutil.copy2(f,out/name);text+='\n'+f.read_text(errors='replace')
        passed=code==0 and not re.search(r'^\s*(?:ERROR:|FATAL:|Fatal:)',text,re.M)
        if stage=='simulate':
            runtime=(work/'simulate.log').read_text(errors='replace')
            functional=(a.pass_marker in runtime and (not a.cases or 'cases='+str(a.cases) in runtime) and
                        runtime.count('CPU_DMA_KAT case=')==a.cases)
            passed=passed and functional
        results.append({'stage':stage,'command':cmd,'exit_code':code,'passed':passed,
                        'elapsed_s':time.monotonic()-start})
        print(text[-3500:],flush=True)
        if not passed:break
    unchanged=all(f.exists() and hashlib.sha256(f.read_bytes()).hexdigest()==h for f,h in
                  ((Path(name),value) for name,value in hashes.items()))
    passed=all(r['passed'] for r in results) and len(results)==len(stages) and unchanged
    (out/'result.json').write_text(json.dumps({'passed':passed,'functional_pass':functional,
        'stages':results,'sources_unchanged':unchanged,'cases':a.cases,'memory_model':a.model,
        'dma_model':'not_instantiated_stream_BFM','ps_ddr_model':'not_instantiated','board':'NOT_RUN',
        'windows_plusarg_quoting':a.quote_plusargs},indent=2))
    print('XSIM_STAGES_PASS' if passed else 'XSIM_STAGES_FAIL',out,flush=True)
    return 0 if passed else 1


if __name__=='__main__':sys.exit(main())

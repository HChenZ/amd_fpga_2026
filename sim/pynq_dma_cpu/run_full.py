"""All official CPU KATs in bounded parallel Icarus shards; same unsharded XSim vectors."""
import argparse
import concurrent.futures
import datetime
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time
from run import ROOT, source_files


def main():
    p=argparse.ArgumentParser()
    p.add_argument('--iverilog',default='iverilog')
    p.add_argument('--vvp',default='vvp')
    p.add_argument('--workers',type=int,default=8)
    p.add_argument('--shard-vectors',type=int,default=140)
    p.add_argument('--timeout',type=int,default=14400)
    p.add_argument('--out')
    a=p.parse_args()
    if a.workers<1 or a.shard_vectors<1:p.error('positive workers and shard-vectors required')
    out=ROOT/(a.out or 'data/advanced/dma_cpu/full_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
    out.mkdir(parents=True,exist_ok=False)
    snapshot=out/'cpu.vvp'
    compile_cmd=[a.iverilog,'-g2012','-I','src/rtl','-I','src/rtl/ascon','-s','tb_dma_cpu',
                 '-o',str(snapshot)]+source_files()
    with (out/'compile.log').open('wb') as log:
        code=subprocess.run(compile_cmd,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,timeout=120).returncode
    if code:return code
    base=[sys.executable,'sim/pynq_dma_cpu/run.py','--full-kat','--iverilog',a.iverilog,'--vvp',a.vvp,
          '--timeout',str(a.timeout)]
    prepare=base+['--prepare-only','--out',str(out/'xsim_all')]
    if subprocess.run(prepare,cwd=ROOT,timeout=120).returncode:return 1
    jobs=[]
    for mode,total in ((1,1089),(2,289),(3,1089)):
        for start in range(0,total,a.shard_vectors):
            jobs.append((mode,start,min(a.shard_vectors,total-start)))
    def run(job):
        mode,start,count=job
        dest=out/('mode%d_%04d_%04d'%(mode,start,start+count))
        cmd=base+['--modes',str(mode),'--kat-start',str(start),'--kat-count',str(count),
                  '--out',str(dest),'--compiled',str(snapshot)]
        begin=time.monotonic()
        with (out/(dest.name+'.log')).open('wb') as log:
            try:
                rc=subprocess.run(cmd,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,timeout=a.timeout+180).returncode
            except subprocess.TimeoutExpired:rc=124
        result={'mode':mode,'start':start,'count':count,'exit_code':rc,'elapsed_s':time.monotonic()-begin,
                'directory':str(dest.relative_to(ROOT)),'command':cmd}
        print(json.dumps(result),flush=True)
        return result
    begin=time.monotonic()
    with concurrent.futures.ThreadPoolExecutor(max_workers=a.workers) as pool:
        results=list(pool.map(run,jobs))
    passed=all(r['exit_code']==0 for r in results)
    summary={'passed':passed,'vectors':{'1':1089,'2':289,'3':1089},'crypto_transactions':7401,
             'elapsed_s':time.monotonic()-begin,'compile_command':compile_cmd,'compile_exit_code':code,
             'snapshot_sha256':hashlib.sha256(snapshot.read_bytes()).hexdigest(),'shards':results}
    (out/'result.json').write_text(json.dumps(summary,indent=2),encoding='utf-8')
    print('FULL_CPU_KAT_PASS' if passed else 'FULL_CPU_KAT_FAIL',out,flush=True)
    return 0 if passed else 1

if __name__=='__main__':sys.exit(main())

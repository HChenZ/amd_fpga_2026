"""Permanent PYNQ 2.7 DMA ABI v2 smoke/full-KAT/benchmark CLI.

No hardware is emulated by this CLI. Offline tests inject an explicitly simulated
transport into run_checks. Firmware hashes identify supplied build artifacts,
not firmware readback (the control ABI has no firmware-digest register).
"""
import argparse
import datetime
import hashlib
import json
import math
from pathlib import Path
import sys
import time

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from src.pynq.dma_transport import RemoteError, pynq_backend, dma_configuration
from src.pynq.golden_checker import parse_kat


def identity(path, expected=None):
    path=Path(path).resolve()
    value=hashlib.sha256(path.read_bytes()).hexdigest()
    if expected is not None and value != expected.lower():
        raise ValueError('artifact SHA-256 mismatch: '+path.name)
    return {'path':str(path),'bytes':path.stat().st_size,'sha256':value}


def save(path, report):
    temporary=path.with_suffix(path.suffix+'.tmp')
    temporary.write_text(json.dumps(report,indent=2),encoding='utf-8')
    temporary.replace(path)


def select_modes(text, capabilities):
    modes=sorted(capabilities) if text=='auto' else [int(x) for x in text.split(',')]
    if not modes or len(set(modes))!=len(modes) or any(m not in capabilities for m in modes):
        raise ValueError('requested modes must be advertised, distinct and nonempty')
    return modes


def run_checks(transport, *, modes, smoke=False, full=False, benchmark=0,
               message_bytes=16, ad_bytes=0, timeout=2.0, cases=None,
               checkpoint=lambda _:None, clock=time.monotonic):
    """Pure orchestration shared by board CLI and explicit offline tests."""
    if transport.needs_recovery:
        raise ValueError('recover transport before checks')
    if benchmark<0 or not math.isfinite(timeout) or timeout<=0:
        raise ValueError('invalid benchmark/deadline')
    if not (smoke or full or benchmark):raise ValueError('select at least one check')
    cases=list(parse_kat()) if cases is None else cases
    report={'evidence_kind':'simulated_adapter' if transport.simulated else 'board',
            'epoch':transport.epoch,'capabilities':transport.capacities,
            'tests':[],'benchmarks':[],'passed':False}
    checkpoint(report)
    for mode in modes:
        if mode not in transport.capacities:raise ValueError('mode not advertised')
        mm,ma=transport.capacities[mode]
        supported=[c for c in cases if len(c['PT'])<=mm and len(c['AD'])<=ma]
        selected=supported if full else []
        if smoke and not full:
            wanted={(0,0),(min(1,mm),0),(min(16,mm),min(16,ma)),(min(32,mm),min(32,ma))}
            selected=[c for c in supported if (len(c['PT']),len(c['AD'])) in wanted]
        if (smoke or full) and not selected:raise ValueError('no applicable KAT vectors')
        test={'mode':mode,'kind':'full_kat' if full else 'smoke','vectors_available':len(supported),
              'vectors_passed':0,'encrypt_passed':0,'decrypt_passed':0,'badtag_rejected':0,'passed':False}
        if smoke or full:report['tests'].append(test)
        for case in selected:
            key,nonce,ad,pt=(case[k] for k in ('Key','Nonce','AD','PT'))
            ct,tag=case['CT'][:-16],case['CT'][-16:]
            result=transport.transact(1,mode,key,nonce,ad,pt,timeout=timeout)
            if result.payload!=case['CT']:raise AssertionError('encrypt KAT mismatch, mode %d'%mode)
            test['encrypt_passed']+=1
            result=transport.transact(2,mode,key,nonce,ad,ct,tag,timeout=timeout)
            if result.payload!=pt:raise AssertionError('decrypt KAT mismatch, mode %d'%mode)
            test['decrypt_passed']+=1
            try:
                transport.transact(2,mode,key,nonce,ad,ct,bytes([tag[0]^1])+tag[1:],timeout=timeout)
            except RemoteError as error:
                if error.status!=1:raise
            else:raise AssertionError('tampered tag accepted, mode %d'%mode)
            test['badtag_rejected']+=1
            test['vectors_passed']+=1
            checkpoint(report)
        test['passed']=True
        if benchmark:
            if not 0<=message_bytes<=mm or not 0<=ad_bytes<=ma:
                raise ValueError('benchmark exceeds advertised mode capacity')
            key=bytes(range(16));nonce=bytes(range(16,32))
            pt=bytes(i%256 for i in range(message_bytes));ad=bytes((i+64)%256 for i in range(ad_bytes))
            # Reference computes only the oracle, outside all measured intervals.
            from src.pynq.ascon_host_api import load_python,REFERENCE_PATH,REFERENCE_SHA256
            reference=load_python(REFERENCE_PATH,REFERENCE_SHA256)
            expected=reference.ascon_encrypt(key,nonce,ad,pt,'Ascon-AEAD128')
            warm=transport.transact(1,mode,key,nonce,ad,pt,timeout=timeout)
            if warm.payload!=expected:raise AssertionError('benchmark warmup mismatch')
            measurement={'mode':mode,'message_bytes':message_bytes,'ad_bytes':ad_bytes,
                         'warmups':1,'samples':[],'cycle_scope':'PL computation' if mode==4 else 'RV32 AEAD mcycle',
                         'wall_scope':'host transact including cache maintenance, scrub wait and DMA quiesce'}
            report['benchmarks'].append(measurement)
            for repetition in range(benchmark):
                start=clock()
                result=transport.transact(1,mode,key,nonce,ad,pt,timeout=timeout)
                wall=clock()-start
                if result.payload!=expected:raise AssertionError('benchmark output mismatch')
                measurement['samples'].append({'repetition':repetition,'wall_seconds':wall,
                    'cycles':result.cycles,'simulated':result.simulated})
                checkpoint(report)
        checkpoint(report)
    report['passed']=True
    checkpoint(report)
    return report


def parser():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--bit',required=True,type=Path)
    p.add_argument('--hwh',required=True,type=Path)
    p.add_argument('--firmware',type=Path,help='CPU build artifact; required for modes 1/2/3')
    for artifact in ('bit','hwh','firmware'):p.add_argument('--'+artifact+'-sha256')
    deployment=p.add_mutually_exclusive_group(required=True)
    deployment.add_argument('--download',action='store_true')
    deployment.add_argument('--use-loaded',action='store_true')
    p.add_argument('--control-ip',default='pynq_dma_cpu_0')
    p.add_argument('--dma-ip',default='axi_dma_0')
    p.add_argument('--lock-path',default='/tmp/ascon_dma_v2.lock')
    p.add_argument('--modes',default='auto',help='auto or comma-separated 1,2,3,4')
    p.add_argument('--smoke',action='store_true')
    p.add_argument('--full',action='store_true')
    p.add_argument('--benchmark',type=int,default=0,metavar='REPETITIONS')
    p.add_argument('--message-bytes',type=int,default=16)
    p.add_argument('--ad-bytes',type=int,default=0)
    p.add_argument('--timeout',type=float,default=2.0)
    p.add_argument('--output',type=Path,required=True)
    return p


def open_board(args, report):
    """Lock before download and create raw MMIO, not PYNQ's spinning DMA driver."""
    import fcntl
    import os
    import pynq
    from pynq import MMIO,Overlay,PL,Clocks
    if not str(pynq.__version__).startswith('2.7'):
        raise RuntimeError('this CLI is audited for PYNQ 2.7')
    report['pynq_version']=pynq.__version__
    fd=os.open(args.lock_path,os.O_CREAT|os.O_RDWR,0o600)
    try:
        fcntl.flock(fd,fcntl.LOCK_EX|fcntl.LOCK_NB)
        overlay=Overlay(str(args.bit.resolve()),download=False)
        dma_info=overlay.ip_dict[args.dma_ip]
        control_info=overlay.ip_dict[args.control_ip]
        parameters=dma_info['parameters']
        dma_configuration(parameters)
        if 'axi_dma' not in dma_info.get('type',''):raise ValueError('selected IP is not AXI DMA')
        if int(control_info['addr_range'])<0x50 or int(dma_info['addr_range'])<0x5c:
            raise ValueError('HWH register windows too small')
        if args.download:overlay.download()
        elif not PL.bitfile_name or Path(PL.bitfile_name).resolve()!=args.bit.resolve():
            raise ValueError('loaded overlay filename does not match supplied bitstream')
        report['deployment']='downloaded_this_run' if args.download else 'OS_loaded_filename_matched_not_readback_verified'
        report['fclk0_mhz_register_readback']=float(Clocks.fclk0_mhz)
        report['pynq_reference_clock_mhz_assumed']=getattr(getattr(Clocks,'_instance',None),'_ref_clk_mhz',None)
        report['clock_readback_scope']='PYNQ PS clock-register-derived value, not an oscillator measurement'
        report['register_windows']={
            'control':{'name':args.control_ip,'base':control_info['phys_addr'],'range':control_info['addr_range']},
            'dma':{'name':args.dma_ip,'base':dma_info['phys_addr'],'range':dma_info['addr_range']}}
        report['dma_parameters']=parameters
        control=MMIO(control_info['phys_addr'],control_info['addr_range'])
        dma=MMIO(dma_info['phys_addr'],dma_info['addr_range'])
    except BaseException:
        os.close(fd)
        raise
    # Factory assumes ownership of the already locked descriptor, including on failure.
    return pynq_backend(control,dma,parameters=parameters,lock_fd=fd,timeout=args.timeout)


# A failed quiesce cannot be followed by process exit: XRT could reclaim buffers
# still targeted by DMA. This deliberately keeps the owning process alive while
# every individual hardware retry remains deadline-bounded.
def quarantine(transport, report, output, sleep=time.sleep):
    report['quarantined']=True
    report['exit_code_when_safe']=1
    save(output,report)
    print('DMA NOT QUIESCENT: buffers retained. Keep this process alive; reset hardware externally.',file=sys.stderr,flush=True)
    while transport.retained:
        try:
            sleep(1)
            transport.close()
        except (Exception,KeyboardInterrupt):
            continue
    report['quarantined']=False
    report['quarantine_released_after_verified_quiescence']=True
    save(output,report)


def main(argv=None, factory=open_board):
    args=parser().parse_args(argv)
    if args.output.exists():raise SystemExit('output already exists; choose a new evidence file')
    args.output.parent.mkdir(parents=True,exist_ok=True)
    report={'schema':'dma_bringup_v2','started_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
            'passed':False,'artifacts':{},'measurements':None,'errors':[]}
    transport=None
    try:
        if not math.isfinite(args.timeout) or args.timeout<=0 or args.benchmark<0:
            raise ValueError('finite positive timeout and nonnegative repetitions required')
        if args.bit.with_suffix('.hwh').resolve()!=args.hwh.resolve():
            raise ValueError('HWH must be the matching same-stem file used by Overlay')
        for kind in ('bit','hwh','firmware'):
            path=getattr(args,kind)
            if path is None and getattr(args,kind+'_sha256'):
                raise ValueError('digest supplied without artifact')
            if path is not None:report['artifacts'][kind]=identity(path,getattr(args,kind+'_sha256'))
        report['firmware_binding']='supplied_build_artifact_not_readback_verified' if args.firmware else 'not_supplied'
        report['host_source_sha256']=hashlib.sha256((ROOT/'src/pynq/dma_transport.py').read_bytes()).hexdigest()
        report['cli_source_sha256']=hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
        save(args.output,report)
        transport=factory(args,report)
        caps=transport.recover(timeout=args.timeout)
        modes=select_modes(args.modes,caps)
        if any(m in (1,2,3) for m in modes) and args.firmware is None:
            raise ValueError('CPU modes require the deployed firmware build artifact identity')
        if all(m==4 for m in modes):report['firmware_binding']='not_applicable_direct_hardware'
        def checkpoint(value):
            report['measurements']=value
            save(args.output,report)
        run_checks(transport,modes=modes,smoke=args.smoke or not(args.full or args.benchmark),
                   full=args.full,benchmark=args.benchmark,message_bytes=args.message_bytes,
                   ad_bytes=args.ad_bytes,timeout=args.timeout,checkpoint=checkpoint)
        for artifact in report['artifacts'].values():
            identity(artifact['path'],artifact['sha256'])
        report['passed']=True
    except (Exception,KeyboardInterrupt) as error:
        # No exception message containing device data or request material is logged.
        report['errors'].append(type(error).__name__)
        report['passed']=False
    finally:
        if transport is not None:
            try:transport.close(timeout=args.timeout)
            except (Exception,KeyboardInterrupt) as error:
                report['passed']=False
                report['errors'].append('close:'+type(error).__name__)
                if transport.retained:quarantine(transport,report,args.output)
        report['finished_utc']=datetime.datetime.now(datetime.timezone.utc).isoformat()
        report['exit_code']=0 if report['passed'] else 1
        save(args.output,report)
    print(json.dumps({'passed':report['passed'],'evidence':str(args.output),'exit_code':report['exit_code']}))
    return report['exit_code']


if __name__=='__main__':sys.exit(main())

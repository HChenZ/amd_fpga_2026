"""Icarus real-CPU DMA regression. KAT oracle is parsed, never crypto-stubbed."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import struct
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from src.pynq.dma_transport import encode_request, RESPONSE
from src.pynq.golden_checker import parse_kat


def source_files():
    rtl = [str(p.relative_to(ROOT)).replace('\\', '/') for p in (ROOT / 'src/rtl').glob('*.v')
           if p.name not in ('top.v', 'top_pl_bram.v', 'soc_top.v', 'bus_interconnect.v')]
    rtl += [str(p.relative_to(ROOT)).replace('\\', '/') for p in (ROOT / 'src/rtl/ascon').glob('*.v')
            if p.name not in ('ascon_mmio.v', 'ascon_aead_2_tb.v')]
    rtl += ['board/vivado_zynq7000_xc7z020_pynq/rtl_p0/ascon_mmio.v']
    rtl += ['src/rtl/pynq_dma_cpu/' + x for x in
            ('bus_interconnect_dma.v', 'soc_top_dma.v', 'dma_cpu_endpoint.v')]
    return rtl + ['sim/ascon/axi_slave_bram.v', 'sim/pynq_dma_cpu/tb_dma_cpu.v']


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--iverilog', default='iverilog')
    p.add_argument('--vvp', default='vvp')
    p.add_argument('--firmware', default='build/local/pynq_dma_svc/dma_svc.hex')
    p.add_argument('--out')
    p.add_argument('--full-kat', action='store_true')
    p.add_argument('--modes', default='1,2,3')
    p.add_argument('--kat-start', type=int, default=0)
    p.add_argument('--kat-count', type=int)
    p.add_argument('--prepare-only', action='store_true', help='write vectors/manifests for XSim without running')
    p.add_argument('--timeout', type=int, default=14400)
    p.add_argument('--compiled', help='reuse an explicitly supplied Icarus snapshot')
    a = p.parse_args()
    out = ROOT / (a.out or 'data/advanced/dma_cpu/' + datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
    out.mkdir(parents=True, exist_ok=False)
    req, rsp, sizes, counts = [], [], [], []
    cases = list(parse_kat())
    rid = 0

    def append(q, op, mode, payload, status=0, response_id=None, response_epoch=1):
        req.extend(q); sizes.append(len(q))
        r = RESPONSE.pack(b'D01R', 2, 1 if status == 0 else 0, response_epoch,
                          rid if response_id is None else response_id,
                          status, op, mode, len(payload), 0) + payload
        rsp.extend(r); counts.append(len(r))

    vector_counts = {}
    modes = [int(m) for m in a.modes.split(',')]
    if not modes or any(m not in (1,2,3) for m in modes):
        p.error('CPU modes are 1,2,3')
    for mode in modes:
        lengths = [(0, 0), (1, 0), (7, 8), (8, 7), (15, 15), (16, 16)]
        if mode != 2:
            lengths += [(17, 17), (31, 32), (32, 31), (32, 32)]
        selected = ([c for c in cases if len(c['PT']) <= (16 if mode == 2 else 32)
                     and len(c['AD']) <= (16 if mode == 2 else 32)] if a.full_kat else
                    [next(c for c in cases if len(c['PT']) == size and len(c['AD']) == alen)
                     for size, alen in lengths])
        selected = selected[a.kat_start:None if a.kat_count is None else a.kat_start+a.kat_count]
        if not selected:
            p.error('empty KAT selection')
        vector_counts[str(mode)] = len(selected)
        for case in selected:
            key, nonce, ad, pt = (case[k] for k in ('Key', 'Nonce', 'AD', 'PT'))
            ct, tag = case['CT'][:-16], case['CT'][-16:]
            for op, data, t, status, payload in [
                (1, pt, b'', 0, ct + tag), (2, ct, tag, 0, pt),
                (2, ct, bytes([tag[0] ^ 1]) + tag[1:], 1, b'')]:
                rid += 1
                append(encode_request(1, rid, op, mode, key, nonce, ad, data, t), op, mode, payload, status)
    # Negative semantic and framing cases after known-good transactions.
    key=bytes(range(16));nonce=bytes(range(16,32))
    for mode, ad, data, status in [(2,b'',bytes(17),2),(2,bytes(17),b'',2),(4,b'',b'',3)]:
        rid += 1
        append(encode_request(1,rid,1,mode,key,nonce,ad,data),1,mode,b'',status)
    rid += 1
    q=encode_request(1,rid,1,1,key,nonce,b'',b'')
    append(q[:-1],1,1,b'',5)
    append(q,1,1,b'',6)  # framing failure consumed the valid session id
    rid += 1
    append(encode_request(2,rid,1,1,key,nonce,b'',b''),1,1,b'',6,response_epoch=2)
    for offset,value,status in [(4,1,5),(4,0x10002,5),(32,0xffffffff,2),
                                 (44,16,2),(40,15,2),(24,0,3),(28,0,3)]:
        rid+=1
        q=bytearray(encode_request(1,rid,1,1,key,nonce,b'',b''))
        struct.pack_into('<I',q,offset,value)
        append(q,0 if offset==24 else 1,0 if offset==28 else 1,b'',status)
    rid+=1
    append(encode_request(1,rid,1,1,key,nonce,b'',b'')+b'\x00',1,1,b'',5)
    rid+=1
    q=bytearray(encode_request(1,rid,1,1,key,nonce,b'',b''));q[8:16]=bytes(8)
    append(q,1,1,b'',6,response_epoch=0)
    rid+=1
    q=bytearray(encode_request(1,rid,1,1,key,nonce,b'',b''));q[16:24]=bytes(8)
    append(q,1,1,b'',6,response_id=0)
    rid+=1
    append(encode_request(1,rid,1,1,key,nonce,b'',bytes(33)),1,1,b'',2)
    for name, values, width in [('requests',req,2),('expected',rsp,2),('sizes',sizes,8),('counts',counts,8)]:
        (out/(name+'.hex')).write_text(''.join(format(v,'0%dx'%width)+'\n' for v in values),encoding='ascii')
    sources = source_files()
    (out/'sources.json').write_text(json.dumps({'top':'tb_dma_cpu','sources':sources,
         'includes':['src/rtl','src/rtl/ascon'],'language':'SystemVerilog'},indent=2))
    plusargs = ['+HEX='+a.firmware,'+DATA='+out.as_posix(),'+CASES='+str(len(sizes)),
                '+REQUEST_BYTES='+str(len(req)), '+RESPONSE_BYTES='+str(len(rsp))]
    hashes={s:hashlib.sha256((ROOT/s).read_bytes()).hexdigest() for s in sources+[a.firmware,
            'data/ascon/kat/asconaead128.txt', 'sim/pynq_dma_cpu/run.py']}
    manifest={'top':'tb_dma_cpu','full_kat':a.full_kat,'vectors_by_mode':vector_counts,
              'kat_start':a.kat_start,'kat_count':a.kat_count,'cases':len(sizes),
              'plusargs':plusargs,'source_sha256':hashes,
              'vector_sha256':{name:hashlib.sha256((out/(name+'.hex')).read_bytes()).hexdigest()
                               for name in ('requests','expected','sizes','counts')}}
    (out/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
    if a.prepare_only:
        print('Prepared XSim vectors:',out)
        return 0
    cmds = ([] if a.compiled else [[a.iverilog,'-g2012','-I','src/rtl','-I','src/rtl/ascon',
                                  '-s','tb_dma_cpu','-o',str(out/'cpu.vvp')]+sources])
    cmds += [[a.vvp,a.compiled or str(out/'cpu.vvp')]+plusargs]
    records=[]
    for tool in (a.iverilog,a.vvp):
        v=subprocess.run([tool,'-V'],cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=30)
        (out/(Path(tool).stem+'_version.log')).write_bytes(v.stdout)
    for i, cmd in enumerate(cmds):
        start=time.monotonic()
        with (out/('run_%d.log'%i)).open('wb') as f:
            try:
                r=subprocess.run(cmd,cwd=ROOT,stdout=f,stderr=subprocess.STDOUT,timeout=a.timeout)
                code=r.returncode
            except subprocess.TimeoutExpired:
                code=124
        text=(out/('run_%d.log'%i)).read_text(errors='replace')
        print(text[-4000:],flush=True)
        records.append({'command':cmd,'exit_code':code,'elapsed_s':time.monotonic()-start})
        if code:
            break
    passed = (len(records)==len(cmds) and records[-1]['exit_code']==0 and 'CPU_DMA_TEST_PASS' in text
              and text.count('CPU_DMA_KAT case=') == len(sizes))
    passed = passed and all(hashlib.sha256((ROOT/s).read_bytes()).hexdigest()==h for s,h in hashes.items())
    (out/'result.json').write_text(json.dumps({'passed':passed,'cases':len(sizes),'commands':records,
                                            'source_sha256':hashes,'vectors_by_mode':vector_counts},indent=2),encoding='utf-8')
    print('Evidence:',out)
    return 0 if passed else 1


if __name__ == '__main__':
    sys.exit(main())

"""Independent official KAT + locked-Python random oracle against real DMA RTL.
Icarus is the explicit fast backend; XSim reruns use the same TB and vector file.
"""
from pathlib import Path
import argparse,datetime,hashlib,json,random,struct,subprocess,sys
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'sim/ascon'))
from support import parse_kat,verify_sources,backend

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--prepare-only',action='store_true');ap.add_argument('--smoke',action='store_true');args=ap.parse_args()
    verify_sources();ref=backend('upstream-python');rng=random.Random(0x25c0ffee)
    work=ROOT/'build/local/advanced_dma';work.mkdir(parents=True,exist_ok=True)
    out=ROOT/'data/advanced/dma_direct'/datetime.datetime.now().strftime('%Y%m%d_%H%M%S');out.mkdir(parents=True)
    cases=parse_kat();cases=cases[:4]+cases[528:530]+cases[-2:] if args.smoke else cases
    rows=[];rid=0
    def add(k,no,ad,pt,ct,tag,op,bad=False):
        nonlocal rid
        rid+=1;data=pt if op==1 else ct; t=b'' if op==1 else tag
        if bad:t=bytes([t[0]^1])+t[1:]
        req=struct.pack('<4sHHQQIIIIII',b'D01Q',2,0,1,rid,op,4,len(ad),len(data),len(data)+16, len(t))+k+no+ad+data+t
        payload=ct+tag if op==1 else (b'' if bad else pt)
        status=1 if bad else 0
        resp=struct.pack('<4sHHQQIIIIQ',b'D01R',2,int(not bad),1,rid,status,op,4,len(payload),0)+payload
        rows.append((req,resp,0))
    for c in cases:
        k,no,ad,pt,ct,tag=(bytes.fromhex(c[n]) for n in ('key','nonce','ad','plaintext','ciphertext','tag'))
        for op,bad in [(1,False),(2,False),(2,True)]:add(k,no,ad,pt,ct,tag,op,bad)
    for length in ([63] if args.smoke else [0,1,7,8,15,16,17,31,32,33,63,64,65,127,255,256,257,511,1023,1024]):
        k=rng.randbytes(16);no=rng.randbytes(16);pt=rng.randbytes(length);ad=rng.randbytes(length)
        combined=ref.encrypt(k,no,ad,pt);ct,tag=combined[:-16],combined[-16:]
        for op,bad in [(1,False),(2,False),(2,True)]:add(k,no,ad,pt,ct,tag,op,bad)
    if not args.smoke:
        c=parse_kat()[-1]
        k,no,ad,pt,ct,tag=(bytes.fromhex(c[n]) for n in ('key','nonce','ad','plaintext','ciphertext','tag'))
        for bit in range(128):
            corrupt=bytearray(tag);corrupt[bit//8]^=1<<(bit%8)
            add(k,no,ad,pt,ct,bytes(corrupt),2)
            req,_,kind=rows[-1]
            rows[-1]=(req,struct.pack('<4sHHQQIIIIQ',b'D01R',2,0,1,rid,1,2,4,0,0),kind)
        for field in ('key','nonce','ad','ct'):
            material={'key':k,'nonce':no,'ad':ad,'ct':ct};v=bytearray(material[field]);v[0]^=1;material[field]=bytes(v)
            add(material['key'],material['nonce'],material['ad'],pt,material['ct'],tag,2)
            req,_,kind=rows[-1]
            rows[-1]=(req,struct.pack('<4sHHQQIIIIQ',b'D01R',2,0,1,rid,1,2,4,0,0),kind)
    # Protocol failures, same packet body; increasing IDs avoid accidental session errors.
    good_req=rows[0][0]
    for mutation,status,kind in [('version',5,0),('mode',3,0),('length',2,0),('short',5,0),('keep',5,1),('epoch',6,0),('duplicate',6,0)]:
        rid+=1;r=bytearray(good_req);struct.pack_into('<Q',r,16,rid)
        if mutation=='version':r[4]=3
        if mutation=='mode':struct.pack_into('<I',r,28,1)
        if mutation=='length':struct.pack_into('<I',r,32,1025)
        if mutation=='short':r=r[:-1]
        if mutation=='epoch':struct.pack_into('<Q',r,8,99)
        if mutation=='duplicate':struct.pack_into('<Q',r,16,1)
        e=struct.pack('<4sHHQQIIIIQ',b'D01R',2,0,struct.unpack_from('<Q',r,8)[0],struct.unpack_from('<Q',r,16)[0],status,1,struct.unpack_from('<I',r,28)[0],0,0)
        if mutation=='keep':e=struct.pack('<4sHHQQIIIIQ',b'D01R',2,0,0,0,5,0,0,0,0)
        rows.append((bytes(r),e,kind))
    # Missing TLAST: timeout returns a header with zero metadata (no validated frame).
    rows.append((good_req,struct.pack('<4sHHQQIIIIQ',b'D01R',2,0,0,0,5,0,0,0,0),2))
    vector=work/('smoke_vectors.txt' if args.smoke else 'vectors.txt')
    vector.write_text(''.join(f'{len(r)} {len(e)} {kind}\n'+r.hex(' ')+'\n'+e.hex(' ')+'\n' for r,e,kind in rows),encoding='ascii')
    sources=[ROOT/'src/rtl/ascon/ascon_round.v',ROOT/'src/rtl/ascon_dma/ascon_aead_multiblock.v',ROOT/'src/rtl/ascon_dma/ascon_axis_direct.v',ROOT/'sim/ascon_dma/tb_axis_direct.sv']
    result={'kind':'rtl_simulation','backend':'iverilog/vvp','cases':len(rows),'kat_cases':len(cases),'seed':0x25c0ffee,
            'vector':str(vector),'vector_sha256':hashlib.sha256(vector.read_bytes()).hexdigest(),
            'source_sha256':{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources},'commands':[]}
    (work/'sources.json').write_text(json.dumps([str(p) for p in sources],indent=2),encoding='utf-8')
    if args.prepare_only:print(vector);return
    try:
        for label,cmd in [('tool',['iverilog','-V']),('compile',['iverilog','-g2012','-s','tb_axis_direct','-o',str(work/'direct.vvp')]+list(map(str,sources))),('run',['vvp',str(work/'direct.vvp'),'+VECTORS='+str(vector).replace('\\','/')])]:
            p=subprocess.run(cmd,cwd=ROOT,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=300)
            text=p.stdout+p.stderr;(out/(label+'.log')).write_text(text,encoding='utf-8')
            result['commands'].append({'command':cmd,'exit_code':p.returncode});print(label,p.returncode,text[-500:])
            if p.returncode or (label=='run' and 'TEST_PASS' not in text):raise RuntimeError(label+' failed')
        result['status']='PASS'
    except Exception as e:result['status']='FAIL';result['error']=str(e);raise
    finally:(out/'summary.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print(out)

if __name__=='__main__':main()

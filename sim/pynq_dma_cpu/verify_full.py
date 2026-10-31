"""Independent audit of prepared packets and final full-regression coverage."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import sys

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from src.pynq.golden_checker import parse_kat
Q=struct.Struct('<4sHHQQIIIIII')
R=struct.Struct('<4sHHQQIIIIQ')


def packets(directory,name,length_name):
    data=bytes(int(v,16) for v in (directory/(name+'.hex')).read_text().split())
    sizes=[int(v,16) for v in (directory/(length_name+'.hex')).read_text().split()]
    offset=0;result=[]
    for size in sizes:
        result.append(data[offset:offset+size]);offset+=size
    assert offset==len(data),'unexpected vector bytes'
    return result


def audit(directory,oracle):
    manifest=json.loads((directory/'manifest.json').read_text())
    for name,expected in manifest['vector_sha256'].items():
        assert hashlib.sha256((directory/(name+'.hex')).read_bytes()).hexdigest()==expected
    for name,expected in manifest['source_sha256'].items():
        assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==expected,'source changed: '+name
    queries=packets(directory,'requests','sizes');responses=packets(directory,'expected','counts')
    assert len(queries)==len(responses)==manifest['cases']
    found={1:set(),2:set(),3:set()}
    index=0
    for mode,count in manifest['vectors_by_mode'].items():
        mode=int(mode)
        for _ in range(count):
            q=Q.unpack(queries[index][:48]);body=queries[index][48:]
            assert q[0:3]==(b'D01Q',2,0) and q[3]==1 and q[5:7]==(1,mode)
            alen,n=q[7:9]
            assert q[9:]==(n+16,0) and len(body)==32+alen+n
            identity=(body[:16],body[16:32],body[32:32+alen],body[32+alen:])
            kat_id,case=oracle[identity]
            assert kat_id not in found[mode],'duplicate KAT'
            assert alen<=(16 if mode==2 else 32) and n<=(16 if mode==2 else 32)
            found[mode].add(kat_id)
            for step in range(3):
                request=queries[index+step];response=responses[index+step]
                h=Q.unpack(request[:48]);r=R.unpack(response[:48])
                assert h[:4]==(b'D01Q',2,0,1) and h[4]==q[4]+step
                assert h[5:9]==(1 if step==0 else 2,mode,alen,n)
                assert h[9:]==((n+16,0) if step==0 else (n,16))
                ct,tag=case['CT'][:-16],case['CT'][-16:]
                expected_body=case['Key']+case['Nonce']+case['AD']
                expected_body+=case['PT'] if step==0 else ct+(tag if step==1 else bytes([tag[0]^1])+tag[1:])
                assert request[48:]==expected_body,'request does not match independent official KAT'
                expected_payload=case['CT'] if step==0 else case['PT'] if step==1 else b''
                assert r==(b'D01R',2,1 if step<2 else 0,1,h[4],0 if step<2 else 1,
                            h[5],mode,len(expected_payload),0)
                assert response[48:]==expected_payload,'response oracle mismatch'
            index+=3
    return found


def main():
    p=argparse.ArgumentParser()
    p.add_argument('directory',type=Path)
    p.add_argument('--vectors-only',action='store_true')
    a=p.parse_args();root=a.directory.resolve()
    cases=list(parse_kat())
    oracle={(c['Key'],c['Nonce'],c['AD'],c['PT']):(i,c) for i,c in enumerate(cases)}
    assert len(oracle)==1089
    expected={m:{i for i,c in enumerate(cases) if len(c['PT'])<=(16 if m==2 else 32)
                 and len(c['AD'])<=(16 if m==2 else 32)} for m in (1,2,3)}
    unsharded=audit(root/'xsim_all',oracle)
    assert unsharded==expected
    if not a.vectors_only:
        summary=json.loads((root/'result.json').read_text())
        assert summary['passed'] and summary['compile_exit_code']==0
        assert hashlib.sha256((root/'cpu.vvp').read_bytes()).hexdigest()==summary['snapshot_sha256']
        found={1:set(),2:set(),3:set()}
        for shard in summary['shards']:
            directory=ROOT/shard['directory']
            result=json.loads((directory/'result.json').read_text())
            assert result['passed'] and all(c['exit_code']==0 for c in result['commands'])
            coverage=audit(directory,oracle)
            log=(directory/'run_0.log').read_text()
            assert log.count('CPU_DMA_KAT case=')==result['cases']
            assert all(marker in log for marker in ('CPU_DMA_TEST_PASS','reset_active_ise=PASS',
                       'reset_partial=PASS','reset_pending=PASS','recovery_kat=PASS'))
            for mode in found:
                assert not (found[mode]&coverage[mode]),'duplicate across shards'
                found[mode]|=coverage[mode]
        assert found==expected,'missing official vectors'
    record={'passed':True,'scope':'vectors_only' if a.vectors_only else 'real_cpu_full_results_and_vectors',
            'official_vectors_by_mode':{m:len(v) for m,v in expected.items()},'crypto_transactions':7401}
    (root/('vector_audit.json' if a.vectors_only else 'verified_full.json')).write_text(json.dumps(record,indent=2))
    print(json.dumps(record))


if __name__=='__main__':main()

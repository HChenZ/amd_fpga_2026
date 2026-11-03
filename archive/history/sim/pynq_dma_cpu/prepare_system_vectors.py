"""Convert preserved official directed packets to the vendor-DMA BFM file format."""
import hashlib
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
source=ROOT/'data/advanced/dma_cpu/20261030_002124_404425'
out=ROOT/'build/local/dma_cpu_system_vectors.txt'
def packets(name,sizes):
    raw=bytes(int(x,16) for x in (source/(name+'.hex')).read_text().split())
    offset=0;result=[]
    for size in sizes:result.append(raw[offset:offset+size]);offset+=size
    assert offset==len(raw)
    return result
sizes=[int(x,16) for x in (source/'sizes.hex').read_text().split()]
counts=[int(x,16) for x in (source/'counts.hex').read_text().split()]
requests=packets('requests',sizes);expected=packets('expected',counts)
assert len(requests)==len(expected)==95
with out.open('w',encoding='ascii') as f:
    for q,r in zip(requests,expected):
        f.write('%d %d 0\n'%(len(q),len(r)))
        f.write(' '.join('%02x'%v for v in q)+'\n')
        f.write(' '.join('%02x'%v for v in r)+'\n')
print(json.dumps({'cases':95,'path':str(out),'sha256':hashlib.sha256(out.read_bytes()).hexdigest()}))

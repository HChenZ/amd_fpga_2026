"""Independent final XSim verdict check; does not rerun or alter simulation."""
import argparse
import hashlib
import json
from pathlib import Path
import re

p=argparse.ArgumentParser()
p.add_argument('directory',type=Path)
p.add_argument('--marker',required=True)
p.add_argument('--cases',type=int,required=True)
a=p.parse_args()
result=json.loads((a.directory/'result.json').read_text())
assert result['passed'] and result['functional_pass'],'runner did not pass functional gate'
assert all(stage['exit_code']==0 and stage['passed'] for stage in result['stages'])
text=(a.directory/'simulate.log').read_text(errors='replace')
assert a.marker in text
assert text.count('CPU_DMA_KAT case=')==a.cases
if a.cases:assert 'cases='+str(a.cases) in text
for file in a.directory.glob('*.log'):
    assert not re.search(r'^\s*(?:error|fatal):',file.read_text(errors='replace'),re.M|re.I),str(file)
hashes=json.loads((a.directory/'source_sha256.json').read_text())
changed=[name for name,value in hashes.items() if not Path(name).is_file() or hashlib.sha256(Path(name).read_bytes()).hexdigest()!=value]
assert not changed,'compiled inputs changed: '+str(changed)
record={'passed':True,'cases':a.cases,'marker':a.marker,'unexpected_errors':0,
        'source_hashes_match':True,'board':'NOT_RUN'}
(a.directory/'verified.json').write_text(json.dumps(record,indent=2),encoding='utf-8')
print(json.dumps(record))

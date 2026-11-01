"""Verify candidate pairing, unchanged synthesis inputs, and retained evidence."""
import hashlib
import json
from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[2]
BOARD=Path(__file__).resolve().parent
OUT=ROOT/'data/advanced/puf_soc'
candidate=BOARD/'candidate'
manifest=json.loads((candidate/'manifest.json').read_text())
snapshot=json.loads((candidate/'source_snapshot.json').read_text())
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
checks={}
checks['candidate_hashes']=all(sha(candidate/p)==h for p,h in manifest['artifact_sha256'].items())
checks['synthesis_sources_unchanged']=all(sha(ROOT/p)==h for p,h in snapshot['sha256'].items())
checks['no_simulation_source_in_synthesis_manifest']=all(not p.startswith('sim/') for p in snapshot['sources'])
words=[int(x,16) for x in (OUT/'firmware/puf_v2.hex').read_text().split()]
binary=(OUT/'firmware/puf_v2.bin').read_bytes()
image=b''.join(w.to_bytes(4,'little') for w in words)
checks['real_firmware_mapping']=len(image)==131072 and image[:len(binary)]==binary
coe=(candidate/'puf_v2.coe').read_text().split('memory_initialization_vector=')[1]
checks['coe_hex_identity']=[int(x.strip(),16) for x in coe.rstrip().rstrip(';').split(',')]==words
xsim=OUT/'xsim_20261030_040155'
logs=list(xsim.glob('*/simulate.log'))
checks['four_xsim_runs']=len(logs)==4 and all('TEST_PASS tb_puf_soc_v2' in p.read_text() and not re.search(r'(?im)^\s*(fatal:|error:)',p.read_text()) for p in logs)
checks['icarus_normal_and_diagnostic']=json.loads((OUT/'icarus_20261030_034234/results.json').read_text())['passed']
checks['host_cli_tests']=json.loads((OUT/'capture_cli_tests.json').read_text())['exit_code']==0
checks['explicit_no_signoff']=manifest['timing_signoff'] is False and manifest['ro_min_period_ns'] is None
checks['actual_normal_abi']=manifest['abi']=='normal' and manifest['control_version']==2
result={'checks':checks,'passed':all(checks.values()),'board':'NOT_RUN','timing_signoff':False}
(OUT/'delivery_checks.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result,indent=2))
raise SystemExit(0 if result['passed'] else 1)

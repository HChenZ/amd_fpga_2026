"""Compare outputs AND handshake every cycle with the original main core."""
import hashlib
import json
import subprocess
from support import ROOT

out = ROOT / 'build/local/key_audit/tail_equivalence'
out.mkdir(parents=True, exist_ok=True)
reference = subprocess.check_output(['git', 'show', 'c37ecae:src/rtl/ascon/crypto_aead.v'], cwd=ROOT)
old = reference.replace(b'CRYPTO_AEAD_V', b'CRYPTO_AEAD_BEFORE_V').replace(b'module crypto_aead(', b'module crypto_aead_before(')
(out / 'before.v').write_bytes(old)
commands = [
    ['iverilog', '-g2012', '-I', 'src/rtl/ascon', '-s', 'tb_tail_equivalence', '-o', str(out/'miter.vvp'),
     'src/rtl/ascon/crypto_aead.v', str(out/'before.v'), 'sim/ascon/tb_tail_equivalence.v'],
    ['vvp', str(out/'miter.vvp')],
]
report = dict(reference_commit='c37ecae', reference_sha256=hashlib.sha256(reference).hexdigest(),
    source_sha256=hashlib.sha256((ROOT/'src/rtl/ascon/crypto_aead.v').read_bytes()).hexdigest(), commands=[])
logs = []
for cmd in commands:
    result = subprocess.run(cmd, cwd=ROOT, capture_output=True, timeout=120)
    text = (result.stdout+result.stderr).decode('utf-8', errors='replace').replace('\r\n', '\n')
    logs.append(text)
    report['commands'].append(dict(command=cmd, exit_code=result.returncode))
    if result.returncode: break
report['status'] = 'PASS' if result.returncode == 0 and 'PASS tail equivalence' in text else 'FAIL'
report['summary'] = text.strip()
evidence = ROOT/'data/ascon/results/key_lifecycle'
(evidence/'tail_equivalence.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8',newline='\n')
(evidence/'tail_equivalence.log').write_text(''.join(logs),encoding='utf-8',newline='\n')
print(report['status'], text.strip())
raise SystemExit(0 if report['status']=='PASS' else 1)

"""Public runtime-key test inputs, checked against BOTH locked Final references."""
import json
from support import ROOT, backend, verify_sources, parse_kat

manifest = verify_sources()
c, py = backend('upstream-c'), backend('upstream-python')
# Gate references against the unchanged official corpus before deriving cases.
for row in parse_kat():
    args = [bytes.fromhex(row[x]) for x in ('key','nonce','ad','plaintext')]
    expected = bytes.fromhex(row['ciphertext']+row['tag'])
    assert c.encrypt(*args) == py.encrypt(*args) == expected
rows = []
for group in range(3):
    for n, an in ((0,0),(1,1),(7,9),(8,8),(9,7),(15,15),(16,16),(17,17),(32,32)):
        k = bytes((0x83 + group*47 + i*13) & 255 for i in range(16))
        nonce = bytes((0x24 + group*29 + i*7 + n) & 255 for i in range(16))
        ad = bytes((0x52 + i*11) & 255 for i in range(an))
        m = bytes((0xa1 + i*19) & 255 for i in range(n))
        expected = c.encrypt(k,nonce,ad,m)
        assert expected == py.encrypt(k,nonce,ad,m)
        rows.append(dict(key=k.hex(), nonce=nonce.hex(), ad=ad.hex(), plaintext=m.hex(), expected=expected.hex()))
out = ROOT/'build/local/key_audit'
out.mkdir(parents=True,exist_ok=True)
def arr(s):
    return '{'+','.join('0x'+s[i:i+2] for i in range(0,len(s),2))+'}' if s else '{0}'
header = '/* PUBLIC TEST DATA, never deployment secrets. Derived from locked C/Python. */\n'
header += 'static const struct { unsigned n, an; unsigned char k[16], nonce[16], ad[32], m[32], expected[48]; } key_cases[] = {\n'
for r in rows:
    header += '{'+str(len(r['plaintext'])//2)+','+str(len(r['ad'])//2)+','+','.join(arr(r[x]) for x in ('key','nonce','ad','plaintext','expected'))+'},\n'
header += '};\n'
(out/'key_cases.h').write_text(header,encoding='ascii', newline="\n")
mem = []
for r in rows:
    if len(r['plaintext'])//2>16: continue
    n, an = len(r['plaintext'])//2,len(r['ad'])//2
    fields=[r['key'],r['nonce'],r['ad'],r['plaintext'],r['expected'][:2*n],r['expected'][2*n:]]
    mem.append(f'{n:02x}{an:02x}'+''.join(f'{int.from_bytes(bytes.fromhex(s),"little"):032x}' for s in fields))
(out/'key_cases.mem').write_text('\n'.join(mem)+'\n',encoding='ascii', newline="\n")
evidence = ROOT/'data/ascon/results/key_lifecycle'
evidence.mkdir(parents=True,exist_ok=True)
(evidence/'public_vectors.json').write_text(json.dumps(dict(public_test_only=True,
    reference_commits={k:manifest[k] for k in ('ascon_c_commit','pyascon_commit')},
    official_reference_gate=1089, cases=rows),indent=2)+'\n',encoding='utf-8', newline="\n")
print(f'PASS {len(rows)} public runtime cases; {len(mem)} within MMIO capacity')

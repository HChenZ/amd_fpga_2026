"""Core lifecycle gate: explicit native Icarus quick backend or prepare-only.

Frozen sources, manifests and bounded TB also support the parent's XSim flow.
Tag-acceptance mutation must compile and fail the bad-tag assertion at runtime.
"""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import random
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'sim/ascon'))
from support import parse_kat, verify_sources, backend


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--backend', choices=['iverilog'], default='iverilog')
    parser.add_argument('--prepare-only', action='store_true')
    args = parser.parse_args()
    verify_sources()
    out = ROOT / 'data/advanced/dma_direct' / datetime.datetime.now().strftime('lifecycle_%Y%m%d_%H%M%S_%f')
    out.mkdir(parents=True)
    paths = ['src/rtl/ascon/ascon_round.v', 'src/rtl/ascon_dma/ascon_aead_multiblock.v',
             'sim/ascon_dma/tb_core_lifecycle.sv']
    copies = []
    for name in paths:
        p = out / Path(name).name
        p.write_bytes((ROOT / name).read_bytes())
        copies.append(p)
    selected = [next(c for c in parse_kat() if c['plaintext_bytes'] == n and c['ad_bytes'] == n)
                for n in (0, 16, 17, 32)]
    rows = []
    for c in selected:
        rows.append(tuple(bytes.fromhex(c[n]) for n in ('key', 'nonce', 'ad', 'plaintext', 'ciphertext', 'tag')))
    rng = random.Random(0x1c1e2026)
    k, no, ad, pt = (rng.randbytes(n) for n in (16, 16, 1024, 1024))
    ref = backend('upstream-python')
    combined = ref.encrypt(k, no, ad, pt)
    rows.append((k, no, ad, pt, combined[:-16], combined[-16:]))
    vector = out / 'vectors.txt'
    def little(value):
        return value[::-1].hex()
    vector.write_text(''.join(f'{len(a)} {len(p)} {little(k)} {little(n)} {little(t)}\n'
                             + a.hex(' ')+'\n'+p.hex(' ')+'\n'+c.hex(' ')+'\n'
                             for k,n,a,p,c,t in rows), encoding='ascii')
    manifest = dict(kind='rtl_simulation', board='not_measured', backend=args.backend,
                    top='tb_core_lifecycle', watchdog_ns=200000000,
                    source_sha256={n: sha(p) for n,p in zip(paths,copies)},
                    reviewed_source_sha256={n: sha(ROOT/n) for n in (
                        'src/rtl/ascon_dma/ascon_axis_direct.v',
                        'src/rtl/ascon_dma/dma_direct_top.v',
                        'docs/advanced_dma_contract.md', 'src/pynq/dma_transport.py')},
                    runner_sha256=sha(Path(__file__)), sources=[str(p) for p in copies],
                    vector=str(vector), vector_sha256=sha(vector),
                    kat_sha256=sha(ROOT/'data/ascon/kat/asconaead128.txt'),
                    official_kat_ids=[c['id'] for c in selected],
                    maximum_length_oracle=ref.metadata, seed=0x1c1e2026,
                    plusargs=['+VECTORS='+vector.as_posix()], commands=[])
    (out/'sources.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    if args.prepare_only:
        print(out)
        return

    def run(label, command):
        p = subprocess.run(command, cwd=ROOT, capture_output=True, text=True,
                           encoding='utf-8', errors='replace', timeout=180)
        text = p.stdout+p.stderr
        (out/(label+'.log')).write_text(text, encoding='utf-8')
        manifest['commands'].append(dict(label=label, command=command, exit_code=p.returncode))
        print(label, p.returncode, text[-350:])
        return p.returncode, text

    try:
        run('tool', ['iverilog', '-V'])
        binary = out/'normal.vvp'
        code, _ = run('compile', ['iverilog', '-g2012', '-s', 'tb_core_lifecycle', '-o', str(binary)]+list(map(str,copies)))
        if code:
            raise RuntimeError('baseline compile failed')
        code, text = run('run', ['vvp', str(binary)]+manifest['plusargs'])
        if code or 'TEST_PASS lifecycle' not in text:
            raise RuntimeError('baseline functional failure')
        manifest['baseline_status'] = 'PASS'
        # These are mandatory in the normal TB as well as focused replays.
        manifest['contract_probes'] = {}
        for name in ('LOAD_REVOKE', 'SYNC_GATE'):
            code, text = run('probe_'+name.lower(), ['vvp', str(binary)]+manifest['plusargs']+['+PROBE_'+name])
            manifest['contract_probes'][name] = dict(exit_code=code,
                status='PASS' if code == 0 and 'TEST_PASS lifecycle probe='+name in text else 'FAIL')
            if manifest['contract_probes'][name]['status'] != 'PASS':
                raise RuntimeError('required contract probe failed: '+name)
        mutant = out/'mutant_tag_compare.v'
        source = copies[1].read_text(encoding='utf-8')
        old = 'enc || computed_tag == expected_tag'
        if source.count(old) != 1:
            raise RuntimeError('tag comparison mutation anchor changed')
        mutant.write_text(source.replace(old, "enc || 1'b1"), encoding='utf-8')
        manifest['mutation'] = dict(change='accept any tag', source_sha256=sha(mutant))
        binary = out/'mutant.vvp'
        code, _ = run('mutation_compile', ['iverilog', '-g2012', '-s', 'tb_core_lifecycle', '-o', str(binary), str(copies[0]), str(mutant), str(copies[2])])
        if code:
            raise RuntimeError('mutation compile failure is not detection')
        code, text = run('mutation_run', ['vvp', str(binary)]+manifest['plusargs'])
        if not code or 'BAD_TAG_ACCEPTED' not in text:
            raise RuntimeError('mutation did not trip the intended assertion')
        manifest['status'] = 'PASS'
        manifest['mutation']['status'] = 'DETECTED_FUNCTIONAL_FAILURE'
    except Exception as error:
        manifest['status'] = 'FAIL'
        manifest['error'] = str(error)
        raise
    finally:
        manifest['live_sources_unchanged'] = all(sha(ROOT/n)==h for n,h in manifest['source_sha256'].items())
        (out/'summary.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
        print(out)


if __name__ == '__main__':
    main()

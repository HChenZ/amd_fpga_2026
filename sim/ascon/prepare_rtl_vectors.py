"""Prepare RTL inputs from immutable KATs and KAT-checked locked references."""
import argparse
import hashlib
import json
from pathlib import Path
import re
from support import DATA, ROOT, Report, backend, check_aead, first_difference, parse_kat, sha256, verify_sources


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "build/local/ascon_rtl")
    parser.add_argument("--cc", default="gcc")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    manifest = verify_sources()
    oracle, second = backend("upstream-c", args.cc), backend("upstream-python", args.cc)
    gate = Report()
    gate.metadata["upstream-c"] = oracle.metadata
    gate.metadata["upstream-python"] = second.metadata
    official = parse_kat()
    for impl in (oracle, second):
        check_aead(gate, impl, official)
    if gate.save(args.output / "reference_gate.json"):
        return 1
    peer_path = ROOT / "src/rtl/ascon/ascon_aead_2_tb.v"
    text = peer_path.read_text(encoding="utf-8")
    key_hex, nonce_hex = re.search(r"k\s*=\s*128'h([0-9a-f]+);\s*npub\s*=\s*128'h([0-9a-f]+)", text, re.I).groups()
    key = int(key_hex, 16).to_bytes(16, "little")
    nonce = int(nonce_hex, 16).to_bytes(16, "little")
    pattern = re.compile(r"run_vector\(\s*128'h([0-9a-f]+),\s*128'h([0-9a-f]+),\s*5'd(\d+),\s*5'd(\d+),\s*128'h([0-9a-f]+),\s*128'h([0-9a-f]+)\s*\)", re.I)
    peer = []
    for i, match in enumerate(pattern.finditer(text)):
        ad_hex, m_hex, adlen, mlen, ct_hex, tag_hex = match.groups()
        adlen, mlen = int(adlen), int(mlen)
        if max(adlen, mlen) > 16:
            raise ValueError("Peer test exceeds physical interface capacity")
        ad = int(ad_hex, 16).to_bytes(16, "little")[:adlen]
        pt = int(m_hex, 16).to_bytes(16, "little")[:mlen]
        expected = oracle.encrypt(key, nonce, ad, pt)
        if second.encrypt(key, nonce, ad, pt) != expected:
            raise ValueError("Locked references disagree")
        asserted_ct = int(ct_hex, 16).to_bytes(16, "little")[:mlen]
        asserted_tag = int(tag_hex, 16).to_bytes(16, "little")
        ct_error = first_difference(expected[:-16], asserted_ct)
        tag_error = first_difference(expected[-16:], asserted_tag)
        peer.append(dict(id=f"peer_v{i}", origin="peer inputs; expected recomputed by locked C after complete KAT gate",
            source_line=text[:match.start()].count("\n") + 1,
            key=key.hex(), nonce=nonce.hex(), ad=ad.hex(), plaintext=pt.hex(),
            ad_bytes=adlen, plaintext_bytes=mlen, ciphertext=expected[:-16].hex(), tag=expected[-16:].hex(),
            peer_asserted_ciphertext=asserted_ct.hex(), peer_asserted_tag=asserted_tag.hex(),
            expected_audit="FAIL" if ct_error or tag_error else "PASS",
            ciphertext_difference=ct_error, tag_difference=tag_error))
    if len(peer) != 5:
        raise ValueError(f"Expected 5 literal peer calls, found {len(peer)}; audit parser needs review")
    lengths = (0, 1, 7, 8, 9, 15, 16)
    matrix = [dict(row, id="matrix_" + row["id"]) for row in official
              if row["ad_bytes"] in lengths and row["plaintext_bytes"] in lengths]
    tails = [dict(row, id="tail_" + row["id"]) for row in json.loads((DATA / "aead_cases.json").read_text())["cases"]
             if row["origin"] == "locked_ascon_c_ref" and max(row["ad_bytes"], row["plaintext_bytes"]) <= 16]
    cases = peer + matrix + tails
    # Retain poison in unused input bytes: explicit lengths must govern masking.
    rows = []
    for case in cases:
        def pack(name):
            value = bytes.fromhex(case[name])
            pad = b"\xa5" if name in ("ad", "plaintext") else b"\x00"
            return f"{int.from_bytes(value + pad * (16-len(value)), 'little'):032x}"
        rows.append(f"{case['plaintext_bytes']:02x}{case['ad_bytes']:02x}" +
                    "".join(pack(n) for n in ("key", "nonce", "ad", "plaintext", "ciphertext", "tag")))
    memory = args.output / "aead.mem"
    memory.write_text("\n".join(rows) + "\n", encoding="ascii")
    result = dict(schema_version=1, standard=manifest["standard"],
        reference_commits={k: manifest[k] for k in ("ascon_c_commit", "pyascon_commit")},
        official_kat_sha256=sha256(DATA / "kat/asconaead128.txt"),
        peer_source_sha256=sha256(peer_path), generator_sha256=sha256(__file__),
        original_peer_vector_provenance="not_documented in RTL/testbench/commit; mathematical values independently confirmed here",
        permutation_sha256=sha256(DATA / "permutation.mem"), memory_sha256=sha256(memory),
        supported_lengths=[0, 16], matrix_cases=len(matrix), tail_cases=len(tails),
        peer_expected_pass=sum(c["expected_audit"] == "PASS" for c in peer), cases=cases)
    (args.output / "vectors.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    for c in peer:
        print(f"{c['expected_audit']} independent_reference/{c['id']} ciphertext={c['ciphertext']} tag={c['tag']}")
    print(f"PASS prepared peer={len(peer)} matrix={len(matrix)} tail={len(tails)}; no >16-byte RTL cases")
    return 1 if result["peer_expected_pass"] != 5 else 0


if __name__ == "__main__":
    raise SystemExit(main())

"""Explicit maintainer operation: derive additions ONLY from locked upstreams.

Ordinary validation never regenerates expected outputs. The official KAT file
is downloaded verbatim and is never rewritten by this program.
"""
import argparse
import json
import random
from support import (DATA, ROOT, RC12, Report, backend, check_aead,
                     negative_cases, parse_kat, sha256, verify_sources)


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cc", default="gcc")
    parser.add_argument("--output", required=True, help="New, empty output directory")
    args = parser.parse_args()
    destination = __import__("pathlib").Path(args.output).resolve()
    if destination.exists() and any(destination.iterdir()):
        parser.error("Output directory must be empty; existing vectors are never overwritten")
    source = verify_sources(derived=False)
    report = Report()
    oracle = backend("upstream-c", args.cc)
    secondary = backend("upstream-python", args.cc)
    report.metadata[oracle.name] = oracle.metadata
    report.metadata[secondary.name] = secondary.metadata
    official = parse_kat()
    for impl in (oracle, secondary):
        check_aead(report, impl, official)
    if report.save(DATA / "results/reference_gate.json"):
        return 1
    destination.mkdir(parents=True, exist_ok=True)
    selected = []
    for row in official:
        if row["plaintext_bytes"] in (0, 1, 7, 8, 9, 15, 16, 17, 32) and row["ad_bytes"] in (0, 1, 15, 16, 17, 32):
            selected.append(dict(row))
    # Pairs that differ only by trailing zero bytes, plus long blocks and AD.
    inputs = [(b"\x00", b""), (b"\xa5", b""), (b"\xa5\x00", b""),
              (b"\xa5" * 7 + b"\x00", b"\x00"),
              (b"\xa5" * 14 + b"\x00", b"\x30" * 15),
              (b"\xa5" * 14 + b"\x00\x00", b"\x30" * 15 + b"\x00"),
              (b"\xa5" * 14 + b"\x00\x00\x00", b"\x30" * 15 + b"\x00\x00"),
              (bytes(range(32)) + b"\x00", bytes(range(32)) + b"\x00"),
              (bytes(range(63)) + b"\x00", bytes(range(47)) + b"\x00"),
              (bytes(range(128)) + b"\x00", bytes(range(80)) + b"\x00")]
    k, n = bytes.fromhex(official[0]["key"]), bytes.fromhex(official[0]["nonce"])
    for i, (pt, ad) in enumerate(inputs):
        combined = oracle.encrypt(k, n, ad, pt)
        if combined != secondary.encrypt(k, n, ad, pt):
            raise ValueError("Locked references disagree on supplemental encryption")
        if any(impl.decrypt(k, n, ad, combined) != pt for impl in (oracle, secondary)):
            raise ValueError("Supplemental decrypt rejected by reference")
        selected.append(dict(id=f"extended_{i:02d}", origin="locked_ascon_c_ref",
                             key=k.hex(), nonce=n.hex(), ad=ad.hex(), plaintext=pt.hex(),
                             ad_bytes=len(ad), plaintext_bytes=len(pt),
                             ciphertext=combined[:-16].hex(), tag=combined[-16:].hex()))
    for row in selected:
        row["negative"] = negative_cases(row)
    reference = dict(ascon_c_commit=source["ascon_c_commit"],
                     pyascon_commit=source["pyascon_commit"],
                     official_kat_sha256=sha256(DATA / "kat/asconaead128.txt"),
                     generator_sha256=sha256(__file__),
                     prerequisite="both locked upstreams passed complete official KAT",
                     expected_origin="ascon-c ref; pyascon cross-check after independent KAT gate")
    write_json(destination / "aead_cases.json", dict(schema_version=1, reference=reference, cases=selected))
    mask = (1 << 64) - 1
    states = [[0]*5, [mask]*5,
              [int.from_bytes(bytes(range(8*i, 8*i+8)), "little") for i in range(5)],
              [1, 0, 0, 0, 0], [0, 0, 0, 0, 1 << 63],
              [0xAAAAAAAAAAAAAAAA, 0x5555555555555555, 0, mask, 1]]
    rng = random.Random(0x800232)
    states += [[rng.getrandbits(64) for _ in range(5)] for _ in range(16)]
    permutations = []
    for i, state in enumerate(states):
        operations = [(1, c) for c in RC12] + [(8, 0), (12, 0)]
        for rounds, constant in operations:
            out = oracle.permute(state, rounds, constant)
            if out != secondary.permute(state, rounds, constant):
                raise ValueError("Locked references disagree on permutation")
            row = dict(id=f"state_{i:02d}_p{rounds}_{constant:02x}", rounds=rounds,
                       constant=f"{constant:02x}", input_words=[f"{w:016x}" for w in state],
                       expected_words=[f"{w:016x}" for w in out],
                       input_bus="".join(f"{w:016x}" for w in reversed(state)),
                       expected_bus="".join(f"{w:016x}" for w in reversed(out)),
                       expected_bytes=b"".join(w.to_bytes(8, "little") for w in out).hex())
            permutations.append(row)
    write_json(destination / "permutation_cases.json", dict(schema_version=1,
                    reference=reference, seed="0x800232", cases=permutations))
    # One 656-bit row: op[655:648], rc[647:640], input[639:320], expected[319:0].
    (destination / "permutation.mem").write_text("".join(
        f"{r['rounds']:02x}{r['constant']}{r['input_bus']}{r['expected_bus']}\n"
        for r in permutations), encoding="ascii")
    write_json(destination / "derived_integrity.json", dict(schema_version=1, files=[
        dict(path=f"data/ascon/{name}", sha256=sha256(destination / name))
        for name in ("aead_cases.json", "permutation_cases.json", "permutation.mem")]))
    print(f"PASS frozen aead={len(selected)} permutation={len(permutations)} output={destination}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

"""Run the complete immutable upstream KAT and fixed supplemental corpus."""
import argparse
import json
from pathlib import Path
from support import (BACKENDS, DATA, ROOT, Report, backend, check_aead,
                     first_difference, parse_kat, verify_sources)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--backends", nargs="+", choices=BACKENDS, default=list(BACKENDS))
    parser.add_argument("--cc", default="gcc")
    parser.add_argument("--report", type=Path, default=DATA / "results/host_validation.json")
    args = parser.parse_args(argv)
    report = Report()
    report.metadata["backends_requested"] = args.backends
    try:
        sources = verify_sources()
        report.metadata["reference_commits"] = {k: sources[k] for k in ("ascon_c_commit", "pyascon_commit")}
        report.record("locked_source_and_data_sha256")
        cases = parse_kat()
        supplements = json.loads((DATA / "aead_cases.json").read_text())["cases"]
        permutations = json.loads((DATA / "permutation_cases.json").read_text())["cases"]
        report.metadata["corpus"] = dict(official_kat=len(cases), supplemental=len(supplements),
                                          permutation=len(permutations))
        for name in args.backends:
            try:
                impl = backend(name, args.cc)
                report.metadata[name] = impl.metadata
                report.record(f"{name}/load_or_compile")
                check_aead(report, impl, cases + supplements)
                # Short ciphertext/tag inputs must also be rejected.
                first = cases[0]
                k, n = bytes.fromhex(first["key"]), bytes.fromhex(first["nonce"])
                for length in range(16):
                    value = impl.decrypt(k, n, b"", bytes(length))
                    report.record(f"{name}/short_tag_{length}",
                                  None if value is None else "expected=fail actual=accepted")
                for row in permutations:
                    inp = [int(w, 16) for w in row["input_words"]]
                    result = impl.permute(inp, row["rounds"], int(row["constant"], 16))
                    expected = bytes.fromhex(row["expected_bytes"])
                    actual = b"".join(w.to_bytes(8, "little") for w in result)
                    report.record(f"{name}/{row['id']}", first_difference(expected, actual))
            except Exception as exc:
                report.record(f"{name}/setup_or_corpus", f"{type(exc).__name__}: {exc}")
    except Exception as exc:
        report.record("setup_or_integrity", f"{type(exc).__name__}: {exc}")
    return report.save(args.report)


if __name__ == "__main__":
    raise SystemExit(main())

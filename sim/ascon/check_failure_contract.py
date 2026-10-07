"""Audit the raw repository C output on authentication failure.

This is a separate project API gate, not a ciphertext/tag KAT mismatch.
The test adapter discards failed plaintext; the raw C API does not do so.
"""
import argparse
from pathlib import Path
from support import DATA, Report, backend, verify_sources
from golden import aead_case


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cc", default="gcc")
    parser.add_argument("--report", type=Path, default=DATA / "results/failure_contract.json")
    args = parser.parse_args()
    report = Report()
    try:
        verify_sources()
        impl = backend("repository-c", args.cc)
        report.metadata[impl.name] = impl.metadata
        row = aead_case("extended_06")
        k, n, ad, pt = (bytes.fromhex(row[f]) for f in ("key", "nonce", "ad", "plaintext"))
        combined = bytearray.fromhex(row["ciphertext"] + row["tag"])
        combined[-1] ^= 1
        status, length, candidate = impl.decrypt_raw(k, n, ad, bytes(combined))
        report.record("repository-c/raw_tag_rejection", None if status != 0 else "accepted invalid tag")
        report.record("repository-c/no_usable_plaintext_on_failure", None if (
            status != 0 and length == 0 and not candidate) else
            f"expected=fail with length=0 actual=rc={status} length={length} "
            f"candidate_equals_plaintext={candidate == pt}; caller must discard/wipe output")
    except Exception as exc:
        report.record("setup", f"{type(exc).__name__}: {exc}")
    return report.save(args.report)


if __name__ == "__main__":
    raise SystemExit(main())

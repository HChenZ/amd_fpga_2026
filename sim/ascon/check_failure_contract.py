"""Check the production C API's raw buffer, length and authentication status.

Read immutable answers, never generate them. Inspect the entire plaintext
region even when mlen is zero; the normal KAT adapter hides rejected output.
"""
import argparse
import ctypes
import hashlib
import json
from pathlib import Path
from support import (DATA, Report, backend, first_difference, negative_cases,
                     parse_kat, verify_sources)


GUARD = 16
SENTINEL = 0xA5


def decrypt_buffer(impl, key, nonce, ad, combined):
    """Call raw C with exactly clen-tag writable bytes between two canaries."""
    capacity = max(0, len(combined) - 16)
    storage = (ctypes.c_ubyte * (capacity + 2 * GUARD))(
        *([SENTINEL] * (capacity + 2 * GUARD)))
    output = ctypes.cast(ctypes.byref(storage, GUARD),
                         ctypes.POINTER(ctypes.c_ubyte))
    # A stale nonzero caller length must also be reset on truncated input.
    length = ctypes.c_ulonglong(0xFFFFFFFFFFFFFFFF)
    status = impl.lib.crypto_aead_decrypt(
        output, ctypes.byref(length), None, impl.buffer(combined), len(combined),
        impl.buffer(ad), len(ad), impl.buffer(nonce), impl.buffer(key))
    raw = bytes(storage)
    return dict(return_value=status, mlen=length.value,
                output=raw[GUARD:GUARD + capacity],
                guards=raw[:GUARD] + raw[GUARD + capacity:])


def check_call(report, impl, name, key, nonce, ad, combined, expected,
               accepted, observations=None):
    raw = decrypt_buffer(impl, key, nonce, ad, combined)
    report.record(name + "/status", None if raw["return_value"] == (
        0 if accepted else -1) else
        f"expected={'0' if accepted else '-1'} actual={raw['return_value']}")
    report.record(name + "/length", None if raw["mlen"] == (
        len(expected) if accepted else 0) else
        f"expected={len(expected) if accepted else 0} actual={raw['mlen']}")
    report.record(name + ("/plaintext" if accepted else "/cleared_plaintext"),
                  first_difference(expected, raw["output"]))
    report.record(name + "/bounds", first_difference(
        bytes([SENTINEL]) * (2 * GUARD), raw["guards"]))
    if observations is not None:
        observations.append(dict(name=name, expected_output=expected.hex(),
            return_value=raw["return_value"], mlen=raw["mlen"],
            raw_output=raw["output"].hex(), guards=raw["guards"].hex()))


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
        rows = parse_kat() + json.loads((DATA / "aead_cases.json").read_text())["cases"]
        report.metadata["corpus"] = dict(official_kat=1089, supplemental=64,
            plaintext_lengths=sorted({r["plaintext_bytes"] for r in rows}),
            truncated_ciphertext_lengths=list(range(16)))
        observations = report.metadata["raw_observations"] = []
        digest = hashlib.sha256()
        for row in rows:
            k, n, ad, pt = (bytes.fromhex(row[f]) for f in
                            ("key", "nonce", "ad", "plaintext"))
            name = f"repository-c/{row['id']}"
            combined = bytes.fromhex(row["ciphertext"] + row["tag"])
            actual = impl.encrypt(k, n, ad, pt)
            report.record(name + "/encryption_unchanged", first_difference(combined, actual))
            digest.update(actual)
            sample = observations if (row["origin"] == "upstream_kat" and
                not ad and len(pt) in (0, 1, 8, 16, 17)) else None
            check_call(report, impl, name + "/valid", k, n, ad, combined,
                       pt, True, sample)
            for bad in row.get("negative", negative_cases(row)):
                check_call(report, impl, name + "/" + bad["kind"], k, n, ad,
                           bytes.fromhex(bad["ciphertext_and_tag"]),
                           bytes(len(pt)), False, sample)
        report.metadata["encryption_output_sha256"] = digest.hexdigest()
        first = rows[0]
        for length in range(16):
            check_call(report, impl, f"repository-c/truncated_{length}",
                bytes.fromhex(first["key"]), bytes.fromhex(first["nonce"]),
                b"", bytes(length), b"", False)
    except Exception as exc:
        report.record("setup", f"{type(exc).__name__}: {exc}")
    return report.save(args.report)


if __name__ == "__main__":
    raise SystemExit(main())

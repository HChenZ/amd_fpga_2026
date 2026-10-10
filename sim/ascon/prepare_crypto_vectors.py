"""Prepare unified crypto_aead vectors straight from the locked official KAT.

Unlike prepare_rtl_vectors.py this needs no C compiler: the NIST SP 800-232
Final KAT file already carries the expected ciphertext/tag for every case, so
the frozen official answers are the oracle. Only the 289 cases whose plaintext
and AD lengths are both <= 16 (the standalone core's packed-bus capacity) are
selected. Each output row is the same 784-bit layout as the existing AEAD RTL
vectors, so the same $readmemh consumers work.

Row layout (little-endian buses):
  plaintext_bytes(2) ad_bytes(2) key(32) nonce(32) ad(32)
  plaintext(32) ciphertext(32) tag(32)
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from support import parse_kat


def pack(value_bytes, pad_byte):
    assert len(value_bytes) <= 16
    padded = value_bytes + bytes([pad_byte]) * (16 - len(value_bytes))
    return f"{int.from_bytes(padded, 'little'):032x}"


def main():
    cases = parse_kat()
    selected = [c for c in cases if max(c["ad_bytes"], c["plaintext_bytes"]) <= 16]
    if len(selected) != 289:
        raise ValueError(f"Expected 289 in-capacity KAT cases, got {len(selected)}")
    rows = []
    for c in selected:
        fields = {n: bytes.fromhex(c[n]) for n in
                  ("key", "nonce", "ad", "plaintext", "ciphertext", "tag")}
        row = f"{c['plaintext_bytes']:02x}{c['ad_bytes']:02x}"
        row += pack(fields["key"], 0x00) + pack(fields["nonce"], 0x00)
        row += pack(fields["ad"], 0xA5) + pack(fields["plaintext"], 0xA5)
        row += pack(fields["ciphertext"], 0xA5) + pack(fields["tag"], 0x00)
        rows.append(row)
    out = Path("build/local/ascon_crypto/aead.mem")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(rows) + "\n", encoding="ascii", newline="\n")
    print(f"PASS prepared {len(rows)} crypto vectors -> {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

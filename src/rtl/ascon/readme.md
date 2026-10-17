# Ascon-AEAD128 RTL

2026-10-09; V05/C03; owner TBD. Integration baseline: `0a425f9`.
The standalone core supports NIST SP 800-232 Final with at most 16-byte data
and 16-byte AD. It is not yet a CPU ISE or AXI peripheral.

## Common contract

Packed bytes are little-endian, first byte at `[7:0]`. `rst_n` is synchronous
and active low. Pulse start for one clock while idle; AEAD ignores start while
busy. A held start can accept another request after completion. Data, AD and
their explicit byte lengths are captured at acceptance. Never infer lengths
from content or discard trailing zeros. Keep key, nonce and decrypt tag_in
stable until done. Read new results only at the one-cycle done pulse.

## Encrypt

Existing named ports `clk,rst_n,start,m,ad,npub,k,adlen,mlen,c,tag,done,busy`
are preserved. Appended `output reg error` reports unsupported lengths.
All existing repository callers use named connections and continue to compile.
Read exactly the accepted request's mlen ciphertext bytes at `done && !error`.
Unused ciphertext bits and reset-time c are unspecified. Length 17..31 on
either data or AD gives immediate `done=1,busy=0,error=1,c=0,tag=0` without a
permutation. Normal requests clear error at acceptance.

## Decrypt: unchanged remote interface

The exact remote 15-port order, names, directions and widths are retained:
`clk,rst_n,start,c,ad,npub,k,adlen,clen,tag_in,m,tag,correct,done,busy`.
clen excludes the separate full 128-bit input tag. Output tag remains the
calculated tag, including on authentication failure; it is not plaintext-valid.
There are no added decrypt mlen/error/result ports or compatibility wrappers.

- Accepted start revokes the previous result: m=0 and correct=0 throughout busy.
- Only a full 128-bit tag match publishes m with done=1, correct=1, busy=0.
  Read exactly the accepted request's clen bytes, including zero for empty
  plaintext. Unused successful plaintext bits are unspecified.
- Authentication failure gives done=1, correct=0, busy=0, m=0. Effective valid
  plaintext length is zero. Never consume m based only on done.
- Unsupported clen/adlen 17..31 gives immediate done=1, correct=0, busy=0,
  m=0, tag=0. Callers distinguish unsupported parameters from auth failure
  using their own accepted input lengths.
- Reset aborts with no completion and clears m/correct/candidate plaintext.
  Candidates are also cleared on new acceptance and after completion.
- Result/output hold until new acceptance/reset or the next completion. Input
  lengths >=32 must be rejected before narrowing into the 5-bit ports.

The teammate's initialization, AD absorption, full ciphertext replacement,
partial ciphertext masking/padding, finalization and full tag XOR are retained.
Repairs initialize/revoke candidates and authentication, reject unsupported
lengths and fail closed when a tag comparison is unknown.

P8/P12 capture `{s4,s3,s2,s1,s0}` at start, have synchronous active-low reset,
one-cycle done and busy low at completion. Their existing busy-start policy is
restart. AEAD requests a permutation only after the previous one completes.
The entire AEAD file, including get_bytes, has an include guard: the teammate
TB's include and explicit complete production source lists both work.

See [entry](../../../sim/ascon/readme.md) and
[integration report](../../../docs/ascon_rtl_decrypt_validation.md).
All 289 supported official KATs, 11 supplemental inputs, 2,579 tamper rejects,
735 unsupported length pairs per direction, reset/restart, named/positional
decrypt callers and full production compile/simulation pass. Vivado, target
CPU/board KAT, hardware cycles/PPA and longer RTL messages remain unverified.

## 2026-10-16 key lifecycle review

Current software/MMIO/ISE runtime APIs, ZEROIZE, CPU handshake, test commands and build evidence: [review](../../../docs/ascon_key_management.md). Earlier dated status above is historical. Board model remains unknown; no programming performed.

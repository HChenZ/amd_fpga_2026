# Ascon-AEAD128 production C API and authentication-failure repair

2026-10-07, C02 / C03 software, owner TBD. Direct branch baseline:
`c34728558469f0d4e4068730801dea59e0ca2100`; working branch
`fix/ascon-c-auth-failure`. Host evidence only; target build/run/cycles/PPA are
not_measured. No production RTL, CPU, Vivado or task-board change.

## Production versus reference

This existing directory is the project's production software port. Its historical
origin is not proved solely by similarity to upstream. `CRYPTO_VERSION=1.3.0`
is retained; this is a local failure-output patch, not an upstream version update.
The independently locked, unmodified C/Python references live under
`sim/ascon/reference/`. Sources, original CC0 licenses, Final specification and
KAT hashes are in [provenance](../../../data/ascon/provenance.json) and the
[standard baseline](../../../report/design/ascon_standard_baseline.md).

The repair branch directly descends from the pushed C01/C03 and RTL-validation
branch `origin/feat/ascon-kat-validation` at `c347285`. Its software validation
scripts, reference sources, provenance, frozen AEAD/permutation data, historical
baseline and RTL regression remain parent history rather than duplicated changes
in this commit. Byte-preservation rules in .gitattributes retain immutable source
bytes. All 18 imported source hashes and three derived-vector hashes pass
verification unchanged.

## Contract and its authority

Key/nonce/tag are each 16 bytes. AD and plaintext lengths are explicit byte
counts. Encryption returns ciphertext followed by the full 16-byte tag.
Encryption and all successful-decryption calculations are unchanged.

[NIST SP 800-232 Final](https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-232.pdf),
section 4.1.2 / Algorithm 4 (printed page 16), returns plaintext when tags agree
and fail otherwise. It specifies the algorithm, not C mlen/buffer-wipe semantics.
[SUPERCOP's AEAD API](https://bench.cr.yp.to/call-aead.html), page version
2020.08.01, requires -1 for invalid ciphertext, 0 on success, and permits other
negative error codes for other failures. Its interface description does not
require clearing mlen or the destination buffer on authentication failure;
absence of that requirement is not permission to use unauthenticated plaintext.
Both primary sources were read on 2026-10-07.

This project's [technical_rules](../../../report/design/technical_rules.md), custom
instruction completion definition item 5, adds “失败不得返回可使用明文”. This repair
implements that acceptance rule directly in the production C function:

| Input/result | Return | mlen after return | Output buffer after return |
|---|---|---|---|
| Valid ciphertext/tag | 0 | clen - 16 | Correct plaintext, no extra bytes written |
| Invalid tag/ciphertext, clen >= 16 | -1 | 0 | Exactly the known clen - 16 candidate bytes zeroed |
| Short ciphertext/tag, clen < 16 | -1 | 0 | Buffer untouched; no candidate exists |

The caller must provide valid pointers, an independent mlen object, sufficient
output capacity max(0, clen-16), 16-byte key/nonce and readable explicit inputs.
`CRYPTO_NOOVERLAP=1` remains the supported contract: input/output must not overlap.
This patch does not add a capacity argument or support invalid pointers/huge
unbacked lengths. Use output only after return==0; do not concurrently consume
the output while decryption is in progress. It does not erase all stack/state
copies or claim whole-implementation constant time. ASCON_PRINT_STATE is a
diagnostic mode that logs secrets/state and must not be enabled in production.

## Root cause and minimal change

Before the patch, decrypt sets mlen before authentication, writes candidate
plaintext block by block, compares all 16 tag bytes and returns result without
clearing the output. It also returns early on clen<16 without resetting mlen.
The normal KAT adapter discards a failed return; that masks buffer exposure and
is insufficient evidence of a safe production API.

Decrypt now saves the original output pointer, initializes mlen to zero and
retains the original known plaintext length after checking clen>=16. After the
unchanged XOR/OR comparison over all 16 tag bytes, failure clears precisely that
many bytes with volatile byte stores and returns -1 with mlen zero. Volatile
stores retain the wipe under optimization; no malloc, libc wipe dependency or
early-exit tag comparison is introduced. Success follows the original path.
The only production edit is in aead.c's decrypt function.

GCC 13.3.0 x86-64 -O2 disassembly was read: the comparison loads the complete
16-byte tag, performs XOR and OR reduction (2bd5..2c38) before the outcome branch
at 2c42. The failure path retains byte-zero stores at 3524, loops only to the
known output end, then writes zero to mlen at 3531. These addresses are specific
to the inspected object; this is compiler inspection, not a timing proof or
RISC-V verification. Temporary object is ignored under build/local/ascon_kat.

## Real verification and evidence

Run from the repository root. Environment: Ubuntu WSL Python 3.12.3;
GCC (Ubuntu 13.3.0-6ubuntu2~24.04.1) 13.3.0. Normal C test flags:
`-std=c99 -O2 -Wall -Wextra -Werror -shared -fPIC`.

```powershell
# Before the production edit; retained reproduction, not expected to pass.
wsl -d Ubuntu -- python3 sim/ascon/check_failure_contract.py --report data/ascon/results/failure_contract_original_reproduction.json
wsl -d Ubuntu -- python3 sim/ascon/run_validation.py --report data/ascon/results/host_validation_before.json
# Expanded test before the production edit, then the same test after it.
wsl -d Ubuntu -- python3 sim/ascon/check_failure_contract.py --report data/ascon/results/failure_contract_before.json
wsl -d Ubuntu -- python3 sim/ascon/check_failure_contract.py
wsl -d Ubuntu -- python3 sim/ascon/run_validation.py
wsl -d Ubuntu -- python3 sim/ascon/test_harness.py
# Compiler review, separate from algorithm tests.
wsl -d Ubuntu -- gcc -std=c99 -O2 -Wall -Wextra -Werror -c ascon/ascon_c/aead/aead.c -o build/local/ascon_kat/auth_failure_review.o
wsl -d Ubuntu -- objdump -d --disassemble=crypto_aead_decrypt build/local/ascon_kat/auth_failure_review.o
```

The original two-check test reports 1 PASS / 1 FAIL, exit 1, confirming an invalid
tag returns -1, mlen=17 and output equal to the original plaintext. The expanded
raw test before repair reports 15,039 PASS / 8,926 FAIL, exit 1. It also records
first/last ciphertext flips and stale mlen for truncated lengths. Failed tests
were not hidden or discarded.

After repair the expanded raw test reports **23,965 PASS / 0 FAIL / exit 0**.
It covers all 1,089 official KAT and 64 frozen extensions, PT lengths 0..32 plus
33/64/129, empty/boundary/multi-block AD and trailing-zero inputs. For each input
it checks unchanged encryption, valid plaintext/length/status, tag first/last
and (for nonempty PT) ciphertext first/last tampering, returned failure, zero
mlen and the complete zeroed plaintext region. A5 canaries on both sides must
remain unchanged, including zero-length and truncated inputs. Its raw inspection
does not slice the buffer using the returned mlen. Required PT=0/1/8/16/17
samples retain output bytes and return values in the report metadata.

For 17-byte official case kat_0562 with empty AD: valid output stays
`202122232425262728292a2b2c2d2e2f30`, return 0, mlen 17. Bad first/last tag
previously returned -1, mlen 17 with those same plaintext bytes; after repair it
returns -1, mlen 0 and 17 zero bytes. Bad first ciphertext previously leaves
`212122232425262728292a2b2c2d2e2f7a`; after repair it leaves 17 zero bytes.
Guard bytes remain A5 in all these cases.

Full four-backend host validation is **28,661 PASS / 0 FAIL / exit 0** both before
and after. Both locked references and project C/Python pass encryption,
decryption, tamper rejection, short-tag and permutation checks. Harness/golden
tests: 5 PASS, exit 0. The SHA256 of concatenated production C encryption outputs
over all 1,153 fixed AEAD rows is byte-identical before/after:
`9914aa88a6a93bcf3d09a4fee00144f44b3b06cb57abd36047f8f2c6883cb4b5`.

Evidence in [results](../../../data/ascon/results/):
`failure_contract_original_reproduction.json/.log`,
`failure_contract_before.json.gz/.log.gz`, `failure_contract.json/.log.gz`,
`host_validation_before.json`, `host_validation.json/.log`.
Large historical failure details and repetitive full logs are losslessly
gzip-compressed, preserving every PASS/FAIL. The before/after host PASS logs are
byte-identical, so the parent branch's single `host_validation.log` is retained
instead of storing a duplicate. Before reports identify the original
production source SHA; after reports identify the changed source SHA. Reports
include compiler command/version, binary/source/test hashes and raw observations.
Recorded absolute build paths are run evidence; no script hardcodes them.

The first attempted dynamic wslpath conversion lost backslashes through Windows
argument handling (exit 2); no test ran in that attempt. Running WSL at the repo
root with relative script paths succeeded. No frozen vector was regenerated.

## Task recommendations and remaining blockers

C01: evidence supports review-to-done; its validation branch still needs project
integration review. C02's authentication-failure host subtask is closed, but
**C02 cannot yet be marked done**: its acceptance also requires target compilation
and port/build entry, dependent on B04, which were not run here. C03 software
checks including the extra failure-output contract now pass; do not automatically
mark the overall task done or edit the task board.

RTL owner remains TBD. Prior branch evidence reported duplicate encrypt/decrypt/
get_bytes modules, legacy reset versus rst_n mismatch, absent RTL decrypt and
new AEAD's 16-byte PT/AD interface limit. These remain owner follow-ups, not
retested findings in this software-only task. No RTL regression or full-source
integration test was run here. Next recipient: C02 target/B04 build owner, then
C03 target KAT and C04 real mcycle; RTL owner handles integration/decrypt.

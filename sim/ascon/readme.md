# Ascon Final host validation and RTL golden interface

Task C01/C02/C03, owner TBD, audited 2026-10-07 (Asia/Shanghai).
The standard and observed issues are in [ascon_standard_baseline](../../docs/ascon_standard_baseline.md).
The production C API is documented in
[aead/readme.md](../../ascon/ascon_c/aead/readme.md).

## Run

Python 3.10+ and GCC (or a compatible compiler via `--cc`) are required for the
full host suite. There are no pip dependencies. Tested: WSL Ubuntu, Python
3.12.3, GCC 13.3.0. Run from the repository root:

```sh
python3 sim/ascon/run_validation.py
python3 sim/ascon/test_harness.py
python3 sim/ascon/check_failure_contract.py
```

Windows/PowerShell with the available Ubuntu WSL environment:

```powershell
wsl -d Ubuntu -- python3 sim/ascon/run_validation.py
wsl -d Ubuntu -- python3 sim/ascon/test_harness.py
wsl -d Ubuntu -- python3 sim/ascon/check_failure_contract.py
```

The first command checks all 1,089 official upstream KATs, 64 fixed supplemental
cases, 16 short-tag lengths, and 308 permutation expectations against all four
backends. C builds use `-std=c99 -O2 -Wall -Wextra -Werror -shared -fPIC` and an
isolated temporary directory under ignored `build/local/ascon_kat/`.
Source/data SHA-256 is checked before testing. Missing compilers, corrupt data,
exceptions, or mismatches produce FAIL and a nonzero exit status. Outputs go to
`data/ascon/results/host_validation.json` and `.log`; `--report PATH` overrides
that location. JSON stores tool/source hashes, aggregate counts and failures;
the log stores every PASS/FAIL. Byte offsets in mismatch messages start at zero.
An optional `--backends repository-python upstream-python` run is **partial**,
does not establish C correctness, and is labelled in the report metadata.

The second command checks rejection of deliberately injected wrong output,
invalid-tag acceptance, and a hash mismatch; it also calls all four golden CLI
operations and checks the `$readmemh` layout. Faults are injected only in child
Python processes; no repository/reference source or fixed expected data changes.

The third command is a separate production C API acceptance gate. It now calls
raw C with A5 canaries before and after exactly `max(0, clen-16)` output bytes,
starts with a stale nonzero mlen, and inspects the whole output independently of
returned mlen. For all 1,089 official and 64 supplemental cases it checks valid
decrypt, unchanged encrypt, first/last tag and ciphertext tampering, failure
mlen=0, zeroed plaintext and unchanged canaries. Empty ciphertext has only tag
tampering. All 16 truncated lengths must fail, reset mlen and leave canaries
untouched. Public-vector raw samples at PT=0/1/8/16/17 are saved in the JSON.
Before repair it reports 15,039 PASS / 8,926 FAIL, exit 1; after repair it reports
23,965 PASS / 0 FAIL, exit 0. The original two-check reproducer also failed;
all before-fix evidence is retained. Merely hiding the buffer by returning
mlen=0 cannot pass the new test. The unchanged upstream reference is subject to
algorithm KAT, not the project's extra output-erasure contract.
Stored full logs and the large before-fix JSON are losslessly gzip-compressed
in data/ascon/results; rerunning the scripts writes normal JSON and log files.
Python rejects a short tag via assertion (converted to rejection in the test
adapter); it is not a production input-validation wrapper. Timing resistance,
buffer aliasing/huge lengths and target firmware are outside this host suite.
WSL inherits the repository working directory; run these commands at its root.

## RTL consumers

The host software suite does not instantiate RTL. The separate RTL regression
instantiates production RTL; the 2026-10-09 integration retains the remote
tag_in/tag/correct decrypt API and adds authentication protection and explicit
length rejection. The frozen files
`data/ascon/permutation_cases.json`, `data/ascon/permutation.mem`, and
`data/ascon/aead_cases.json` are available offline to future TestBenches.

Words are numeric 64-bit hex values in **s0,s1,s2,s3,s4** order. A 320-bit
RTL bus is `{s4,s3,s2,s1,s0}`, with s0 in `[63:0]`. `expected_bytes` is
`LE64(s0)||LE64(s1)||...||LE64(s4)`. It is different from the printed bus hex.
Each `.mem` line has 164 hex digits encoding one 656-bit row:

| Bits | Field |
|---|---|
| `[655:648]` | operation: `01` round, `08` P8, `0c` P12 |
| `[647:640]` | round constant, ignored for P8/P12 |
| `[639:320]` | input bus `{s4,s3,s2,s1,s0}` |
| `[319:0]` | expected output bus |

```verilog
reg [655:0] golden_rows [0:307];
initial $readmemh("data/ascon/permutation.mem", golden_rows);
// Input s0 = golden_rows[index][383:320].
// Expected s0 = golden_rows[index][63:0].
```

For arbitrary states, a Python consumer can import `GoldenModel` from
`sim/ascon/golden.py`, then call
`GoldenModel().permutation(state_bus_hex, rounds=8)` or `rounds=1, constant=0xf0`.
It executes the locked upstream C helpers via `c_bridge.c`; the bridge contains
no custom cryptographic implementation. The CLI has the same mapping:

```sh
python3 sim/ascon/golden.py round --state-bus <80_hex_digits> --constant f0
python3 sim/ascon/golden.py p8 --state-bus <80_hex_digits> --format hex
python3 sim/ascon/golden.py p12 --state-bus <80_hex_digits> --format hex
python3 sim/ascon/golden.py aead --case kat_0001 --format hex
```

AEAD `--format hex` prints ciphertext followed by the full 16-byte tag in byte
sequence order. Default JSON includes explicit plaintext/AD byte lengths and
separate ciphertext/tag. `aead --case` only reads trusted frozen expectations;
it does not generate arbitrary new expected AEAD outputs during validation.

## Updating the lock

Imported reference files retain their upstream bytes and CC0 license texts.
The provenance manifest records exact raw URLs, commits, local mappings and
hashes. `.gitattributes` prevents checkout newline conversion of locked data
and reference code, and keeps the new Python/C test scripts in LF.

Normal validation never regenerates expected answers. A maintainer can run:

```sh
python3 sim/ascon/freeze_vectors.py --output build/local/new_ascon_vectors
```

The output must be a new/empty directory; existing vectors are not overwritten.
Both locked references must first pass the **entire independently downloaded
official KAT**, including decrypt and negative tests. Only then are extensions
generated by the locked ascon-c ref and cross-checked with the locked pyascon.
The official text KAT is never rewritten. Review generated differences and
hashes before explicitly replacing frozen data; source/standard lock changes
require a new C01 review. Extension/permutation vectors are reference-derived,
not NIST-published vectors or a NIST certification.

## RTL regression after latest main

Read [current RTL validation](../../docs/ascon_rtl_decrypt_validation.md) and
[RTL interface](../../src/rtl/ascon/readme.md) for tested scope and limitations.
The [older RTL audit](../../docs/ascon_rtl_regression_audit.md) retains historical
failures. From the repository root:

```sh
python3 sim/ascon/prepare_rtl_vectors.py
python3 sim/ascon/run_rtl_regression.py
python3 sim/ascon/test_rtl_harness.py
```

Preparation needs Python/GCC and uses the locked C/Python references after a
complete official KAT gate. Simulation needs Python and `iverilog`/`vvp`.
For this Windows environment, use WSL for the C reference and native Icarus:

```powershell
wsl -d Ubuntu -- python3 sim/ascon/prepare_rtl_vectors.py
python sim/ascon/run_rtl_regression.py
python sim/ascon/test_rtl_harness.py
```

Temporary data/libraries/vvp remain in ignored build/local/ascon_rtl. The final
`data/ascon/results/rtl_integration_regression.json` and `.log` contain the peer vector audit,
reference gate metadata, tool/source hashes, actual commands, outcomes and
behavior observations. All five peer expected values are independently checked.
The testbench extraction intentionally fails on changed/unrecognized formatting
instead of silently selecting fewer cases. Frozen vectors and producer source
hashes are checked before use. Case memory packs mlen/adlen (8 bits each), then
128-bit key, nonce, AD, plaintext, expected ciphertext and tag, all as numeric
little-endian buses. Permutation memory retains the earlier 656-bit contract.

Encrypt and independent decrypt pass all 289 official KAT inputs with PT/AD
lengths 0..16, plus 11 peer/tail-zero inputs and control tests. Decrypt runs
2,579 tag/ciphertext/key/nonce/AD tamper rejects and checks external plaintext
on every busy cycle. Both directions reject all 735 unsupported length pairs
in the 5-bit range. Round/P8/P12 also pass. The runner now returns exit 0 for
the current production source set; it excludes only *_tb.v, elaborates all
production roots, and runs encryption and decryption with all production files.
The removed legacy source is not required or silently dropped from an existing
production set. The remaining 800 official cases exceed this packed interface
and are not claimed as RTL-tested. `rtl_integration_harness.json` records four fault tests:
accepting bad tags, wrong plaintext and early plaintext each cause vvp exit 1;
corrupt memory causes runner exit 1. Decrypt uses the unchanged remote 15-port
API; the same TB checks named and positional callers, computed tag and
correct=0/m=0 before authentication and on rejection. No decrypt mlen/error
outputs are needed: use done && correct and the accepted request's clen.
Preexisting tracked `rtl_regression.*` is preserved; earlier dirty local reports
remain in the untouched original workspace and external backup.
Busy-start/key-change/unused-output observations are labelled separately from
valid stable-key algorithm checks. Own TestBenches have watchdogs and $fatal(1).

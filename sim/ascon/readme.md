# Ascon Final host validation and RTL golden interface

Task C01/C03, owner TBD, audited 2026-10-07 (Asia/Shanghai).
The standard and observed issues are in [ascon_standard_baseline](../../docs/ascon_standard_baseline.md).

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
$asconWslRoot = (wsl -d Ubuntu -- wslpath -a $PWD.Path).Trim()
wsl -d Ubuntu -- python3 "$asconWslRoot/sim/ascon/run_validation.py"
wsl -d Ubuntu -- python3 "$asconWslRoot/sim/ascon/test_harness.py"
wsl -d Ubuntu -- python3 "$asconWslRoot/sim/ascon/check_failure_contract.py"
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

The third command is a separate project API acceptance gate. At the audited
HEAD it **fails with exit 1**: repository C returns `-1` for an invalid tag but
retains plaintext and `mlen=17`. The KAT adapter discards failed C output; this
adapter does not repair the actual firmware API. This raw-output issue must be
closed in C02 before claiming the project's authenticated decryption contract.
Python rejects a short tag via assertion (converted to rejection in the test
adapter); it is not a production input-validation wrapper. Timing resistance,
buffer aliasing/huge lengths and target firmware are outside this host suite.

## RTL consumers

No existing RTL is edited or instantiated by this suite. The frozen files
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

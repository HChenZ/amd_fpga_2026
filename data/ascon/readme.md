# Locked Ascon-AEAD128 Final data

Audited 2026-10-07; task C01/C03; owner TBD.

| File | Meaning |
|---|---|
| `provenance.json` | 18 downloaded files: source URLs, immutable upstream commits, original paths, licenses and exact byte SHA-256 |
| `sources/nist_sp_800_232.pdf` | NIST Final publication, August 2025; normative specification |
| `sources/ascon_c_readme.md` | Locked upstream identifies SP 800-232 and new KATs |
| `sources/pyascon_readme.md` | Locked upstream still says draft; used as a checked secondary reference, not the normative standard |
| `kat/asconaead128.txt` | Verbatim ascon-c official upstream KAT, all 1,089 pairs of plaintext/AD lengths 0..32; CT is ciphertext plus tag |
| `aead_cases.json` | 54 selected official cases plus 10 locked-reference extensions; explicit byte lengths, separate ciphertext/tag, stored ciphertext/tag mutations expecting fail |
| `permutation_cases.json` | 22 input states × (12 round constants + P8 + P12) = 308 frozen reference-derived cases |
| `permutation.mem` | The same 308 cases as 656-bit `$readmemh` rows; schema in sim readme |
| `derived_integrity.json` | Exact SHA-256 for the three frozen derived files |
| `results/reference_gate.*` | Complete upstream reference KAT gate before derivation |
| `results/host_validation.*` | Final four-backend host KAT/permutation run |
| `results/failure_contract.*` | Real FAIL of repository C's raw failed-decrypt output contract |
| `results/runner_race_before_fix.*` | Retained transient test-runner build collision; fixed with isolated per-call builds |
| `results/harness.log` | Five tests for failure detection and golden CLI/memory mapping |
| `results/audit_snapshot.json` | Git history, actual commands/exit codes, hashes and reproduction evidence |
| `results/rtl_integration_regression.*` | Fresh 0a425f9 integration: 289 official KAT + 11 extensions, encrypt/decrypt/permutation and complete production compile/simulation PASS; original decrypt interface verified |
| `results/rtl_integration_before.*` | Actual remote decrypt X output/status and duplicate modules from peer include plus explicit sources, before repair |
| `results/rtl_integration_setup_failure.*`, `results/rtl_integration_guard_failure.*.gz` | Retained environment/setup and incomplete include-guard FAILs before final successful run |
| `results/rtl_integration_harness.json` | Four fresh integration fault checks: invalid-tag acceptance, wrong/early plaintext and corrupt vectors all return nonzero |
| `results/host_integration_validation.*` | Fresh integration-worktree four-backend software run, 28,661 PASS / 0 FAIL; full log losslessly gzip archived |

Lengths are measured in bytes and stored explicitly. No consumer may infer a
length from nonzero content or strip trailing `00`. Extensions contain `00`,
`a5`, `a500`, 8/15/16/17-byte tails, and 33/64/129-byte multi-block messages;
AD includes empty, 1/15/16/17/33/48/81-byte inputs. The full official KAT also
covers every 7/8/9/15/16/17-byte boundary with every AD length 0..32.

Official KAT expectations are downloaded independently from the pinned upstream
repository. Additional expected answers come from that locked reference **after**
it passes the full downloaded KAT. Matching two local implementations alone is
never treated as standard correctness evidence.

Third-party ascon-c and pyascon code/KAT use CC0-1.0; original license texts are
in `sim/ascon/reference/ascon_c/license.txt` and
`sim/ascon/reference/pyascon/license.txt`. NIST's PDF authority statement says
the publication is not subject to copyright in the United States and requests
attribution. This does not relicense the whole project or prove the provenance
of historical local files. No real secret material is present; all inputs are
public test data. These results are host software evidence; hardware cycles,
PPA remain `not_measured`. Standalone RTL encrypt/decrypt and round/P8/P12 now
have simulation evidence; see [current audit](../../docs/ascon_rtl_decrypt_validation.md).

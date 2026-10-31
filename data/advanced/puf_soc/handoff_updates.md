# Parent-session log handoff (root logs deliberately not edited)

Task PUF-SOC-V2 / 2026-10-30 / owner TBD.

## Actual progress / development log entry

Created independent CPU/PUF RTL and PS control/UART-mailbox board integration in
`src/rtl/puf_soc_v2/`, `board/vivado_zynq7000_xc7z020_puf_v2/`,
`sim/puf_soc_v2/`, `data/advanced/puf_soc/`. Original CPU/Ascon/PYNQ source and
other agent's keys_v2 files are reused unchanged. Full byte-offset decode is
0x30010000..0x300100ff. PUF response is captured for the CPU's registered MMIO
timing. Bus rejection is visible through a sticky SoC IRQ/LED fault and the PUF
fault register; the CPU has no precise peripheral-access exception interface.

Native xPack GCC 15.2.0 / binutils 2.45 compiled the unchanged real RV32 self-test
with rv32im_zicsr/ilp32/O2 into private 128KiB BRAM initialization. ELF entry is
0x10000000. Actual text/data/bss: 3338/6/4 bytes; initialization is padded to
32768 32-bit words. Compiler emitted the retained RWX load-segment warning.

Icarus 14.0 normal/diagnostic actual SoC firmware execution passed, including real
CPU caches/bus/AXI master/UART plus actual mailbox AXI reads with backpressure.
Final run `icarus_20261030_034234`: normal 11 accepted commands, 4321 PUF reads,
34661 cycles; diagnostic 14 commands, 6428 reads, 47657 cycles. These are simulated
total testbench cycles, **not** measured board performance or CPU crypto benchmark.
Clock models retain 100MHz CPU/25MHz management. Oscillators and DNA are explicitly
behavioral. Earlier `icarus_20261030_032325` used a serial receiver before adding
the real mailbox; `icarus_20261030_033133` is the mailbox check before vendor-mode
testbench support. All raw logs remain; only the final source-matching run is final.

PS control ID is 0x32554650, version 2 normal/258 helper-disclosing diagnostic;
mailbox is ASCII, not Y01. Board CLI checks bit/HWH hashes, mode identity, clocks,
overflow/deadline/failure and retains raw log/JSON. Six host-mocked CLI tests pass;
these are not board results.

New Vivado Tcl session: `vivado-20261030-031422-d4ac106d` only.
Project: `board/vivado_zynq7000_xc7z020_puf_v2/work/puf_soc.xpr`.
Top puf_wrapper, xc7z020clg400-1, Vivado 2025.2. Preflight found 20 logical CPUs,
12% sampled load and 10,352,452KiB free physical RAM before the two-job build;
10,419,948KiB free in the subsequent pre-implementation check. Threads/jobs kept 2.
Other parent/PUF/CPU Vivado sessions were not touched.

## Lessons / preserved failed attempts

1. First synthesis failed with Synth 8-10936 because ro_puf_core_v2.v uses a
   SystemVerilog loop-variable declaration. Fixed project **source language** for
   keys_v2 .v files, without editing their RTL. Resetting the OOC child alone was
   insufficient: launch failed until synth_1 was reset too. Second synthesis
   completed successfully; original failure is in this session's native log.
2. Vivado module-reference parsing emitted ascon_word.v i++ syntax critical
   warnings even though synthesis accepted the separate SystemVerilog file.
   These warnings are retained rather than suppressed. XSim compilation uses
   SystemVerilog explicitly for the include chain.
3. Initial testbench PASS token constants were oversized; the checker was changed
   to a full 128-bit ASCII string comparison. Final compile has no such warning.
4. Windows PowerShell stderr redirection labeled unittest progress as a shell
   failure despite six tests reporting OK. Retained `capture_cli_tests.log`.
   Reran with Python subprocess binary stdout+stderr capture; native exit=0,
   `capture_cli_tests_native.log` and `capture_cli_tests.json` are authoritative.
5. AMD doc-search MCP server was unavailable. Existing verified project IP setup,
   live readback and native errors were used; no invented RO period or blanket
   false paths. Only exact enumerated ring-feedback nets were acknowledged.
6. XSim's project-file language tags override a global xvlog -sv option; the
   crypto_aead/ascon_word include chain required SystemVerilog file properties.
   Leading dash-valued Vivado properties must be passed through -dict. Both
   failures and the successful four-case rerun are retained. No RTL edit needed.
7. The installed2025.2 lacks report_methodology -json and write_json_report from
   the skill's newer-release examples; native full text reports were retained.

## Final completion

Synthesis/route/bit all completed. Initial setup−0.249ns was improved by actual
post-route AggressiveExplore physical optimization to +0.009ns at100MHz;
hold+0.019ns. Management25MHz intra-clock WNS+5.117ns. The actual bit/HWH/firmware
pair is in the new board candidate directory. No clock or timing exception was
changed for that improvement. All69141 routable nets fully routed; no route error.
XSim final four-case evidence is xsim_20261030_040155, covering both modes with
both BFM and actual vendor BRAM/COE initialization. The full verdict, unresolved
7424 no-clock pins/19712 unconstrained endpoints and CDC/methodology warnings are
in validation_20261030.md. This is still structural-diagnostic-only, NOT signoff.

## Acceptance boundaries

No board, eFuse, secure boot, entropy, temperature/aging or multiple-device tests.
Normal ABI mode is independent of the physical **diagnostic-only** classification.
No RO frequency bound exists; unclocked sequential paths must remain exposed in
reports. Do not promote a structural bitstream to full timing signoff. Final
implementation and XSim outcomes are recorded in the validation report alongside
this handoff, not inferred from synthesis or behavioral simulation.

Parent should update actual_progress/development_log/task_board/lessons using the
final validation report. No commit, push, root-log or original-release changes.

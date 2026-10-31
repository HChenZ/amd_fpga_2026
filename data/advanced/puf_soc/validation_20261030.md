# PUF v2 SoC: completed offline integration

Task PUF-SOC-V2; owner TBD; 2026-10-30. **Functional offline PASS;
STRUCTURAL_DIAGNOSTIC_ONLY bitstream. No full timing/CDC/physical-security signoff.**

## Deliverables and scope

- Actual independent CPU integration: `src/rtl/puf_soc_v2/`.
- Board/BD/build/capture/package entry:
  `board/vivado_zynq7000_xc7z020_puf_v2/`.
- Paired normal-ABI diagnostic candidate: that directory's `candidate/`.
- Actual firmware at CPU 0x10000000 in private 128KiB BRAM; native RV32 build,
  full byte-offset PUF decode 0x30010000..0x300100ff; registered response timing.
- Actual `puf_mmio_physical_v2`, DNA reader and 256 physical RO rings. No changes
  to keys_v2 or original CPU/Ascon/release files. No eFuse access or root-log edits.
- PS control ID 0x32554650/version2, mailbox ASCII log; **not Y01**. Normal ABI
  has no raw/internal-key export. Helper-disclosing ABI is parameterized and
  simulated separately; no diagnostic-ABI physical bit was produced.

## Actual tool execution

Only new session **vivado-20261030-031422-d4ac106d** was used. Project
`board/vivado_zynq7000_xc7z020_puf_v2/work/puf_soc.xpr`, part
xc7z020clg400-1, top puf_wrapper, Vivado 2025.2 build6299465. RAM/CPU preflight
and source language repair are documented in `handoff_updates.md`. Jobs/threads=2.
Complete native output is retained by `seal.py` in `vivado_logs/`.

| Command/stage | Exit | Actual result |
|---|---:|---|
| `python .../prepare.py` | 0 | Native xPack GCC15.2.0/binutils2.45, rv32im_zicsr/ilp32/O2; ELF entry0x10000000, text/data/bss3338/6/4B |
| `source setup.tcl` | 0 | New BD/PS100+25MHz/AXI/private BRAM; IP readback in ip_readback.tcldict |
| First `launch_runs synth_1 -jobs 2` / `wait_on_run synth_1` | 0 / 1 | keys_v2 loop-variable declaration needed SystemVerilog; no RTL edit |
| Reset child then premature `launch_runs synth_1` | 1 | Parent synth_1 also needed reset; retained failed attempt |
| Reset parent, `launch_runs synth_1 -jobs 2` / `wait_on_run synth_1` | 0 / 0 | Synthesis complete |
| `launch_runs impl_1 -to_step route_design -jobs 2` / `wait_on_run impl_1` | 0 / 0 | Full route; first WNS−0.249ns, TNS−1.615ns, WHS+0.019ns |
| `source reports.tcl` | 0 | Initial reports retained under implementation/ |
| `phys_opt_design -directive AggressiveExplore` | 0 | Real post-route logic/routing optimization; no clock/exception changes |
| Save final DCP; `source reports.tcl` with optimized/current selection | 0 | Optimized reports retained under optimized/ |
| `write_bitstream -force .../optimized/puf_diagnostic.bit` | 0 | Actual bit write, pre-bit DRC0 errors |
| `source audit_rings.tcl` | 0 | 1280 physical LUTs and exactly256 acknowledged feedback nets |
| `python sim/puf_soc_v2/run.py` | 0 | Both normal/diagnostic real SoC/firmware/mailbox tests PASS |
| First XSim source | 1 | Leading -sv option required a set_property dict |
| Second XSim source | 1 | Per-file project language overrode global -sv; crypto_aead include chain needed SystemVerilog |
| Final `source sim/puf_soc_v2/run_xsim.tcl` | 0 | Four XSim cases PASS, including actual board/vendor BRAM wrapper |
| `report_cdc -details` | 0 | Detailed crossing report retained |
| Optional `report_methodology -json ...`; `help write_json_report` | 1 / 1 | Unsupported in installed2025.2; full native text methodology report retained |
| `python .../test_capture.py` via native subprocess | 0 | Six host-mocked CLI checks PASS; not board evidence |
| `python .../package.py` | 0 | Paired candidate packaged after source-hash verification |
| `python .../verify_delivery.py` | 0 | Candidate/input hashes, BIN↔HEX↔COE mapping, four XSim cases and both Icarus modes verified |

Initial XSim compiler failure is preserved in `xsim_failed_language/`. Corrected
source-language configuration is in setup/run_xsim scripts; RTL bytes are unchanged.
Generated files were never edited to repair the failure. `build.tcl` is the
consolidated reproduction of the executed stages, not a second claimed clean build.

## Functional evidence

Icarus14.0: `icarus_20261030_034234/`; XSim2025.2:
`xsim_20261030_040155/`. Compile/elaborate/runtime transcripts retained. Every case
requires terminal TEST_PASS, no traps/faults/overflow and cleared internal key-ready.

| Backend / memory | ABI | Commands | PUF reads | Simulated testbench cycles |
|---|---|---:|---:|---:|
| Icarus AXI BRAM BFM | normal | 11 | 4321 | 34661 |
| Icarus AXI BRAM BFM | diagnostic | 14 | 6428 | 47657 |
| XSim AXI BRAM BFM | normal | 11 | 4321 | 34661 |
| XSim AXI BRAM BFM | diagnostic | 14 | 6428 | 47657 |
| XSim actual vendor BRAM/board wrapper | normal | 11 | 4321 | 34967 |
| XSim actual vendor BRAM/board wrapper | diagnostic | 14 | 6426 | 48005 |

These are total simulation cycles, not CPU crypto benchmarks. Watchdog20ms;
all cases finish below0.5ms simulated. Models retain 100MHz core/25MHz management
and default sampler dimensions/window. Vendor RAM actually loads generated COE
initialization; no register-level firmware emulation. RO bank and DNA primitive
are explicitly behavioral. Actual UART bits traverse the existing mailbox and
AXI-Lite read backpressure. Default vendor RAM collision limitations remain.

Real firmware verifies enroll/reconstruct consistency, internal-key crypto,
bad-tag rejection/zero outputs, <=16B image-authentication/metadata rejection,
invalid-length rejection and key clear. Diagnostic also exports/reimports helper.
No normal-mode helper/key read path was added.

## Timing and physical boundary

Initial real failure: dcache bus_addr_r[23] → PUF input_data[82]/CE,10 logic
levels, WNS−0.249ns. Post-route optimization improved actual paths, not clock
requirements. Final measured **timed subset**:

| Clock | Period | WNS | WHS |
|---|---:|---:|---:|
| CPU/core | 10ns | +0.009ns | +0.019ns |
| PUF management | 40ns | +5.117ns | +0.119ns |

Final TNS/THS=0; fully routed69141/69141 routable nets; routing errors0.
Utilization:39077 LUTs,40051 registers,34.5 BRAM tiles,4 DSPs. No physical clock
relaxation, invented RO period, global clock-group cut or DRC severity downgrade.

**Not signed off:**7424 non-clocked sequential pins and19712 unconstrained internal
endpoints. TIMING-17 is capped at1000 reported examples; it is not the full count.
TIMING-6/7 each2 expose the undefined relationship of PS primary clock domains;
their reported positive inter-clock slack is not asynchronous CDC proof. Other
methodology:TIMING-23=256,LUTAR-1=4,ULMTCS-1=1. Defined-clock CDC report has
CDC-3=2,CDC-10=1(reset merge),CDC-15=133(bundled-data capture). It omits unclocked
RO domains and cannot establish full CDC safety. No warnings were waived.

DRC warnings include LUTLP-2/PDRC-153/PLHOLDVIO-2 each256; vendor BRAM async-control
reports hit their20-item report limits. Only ring feedback acknowledgement was
added. Applied XDC includes two inherited **vendor reset XPM first-stage** false
paths, not PUF data/reset cuts. The two actual clocks remain10/40ns. Ring cell
LOC/BEL/DONT_TOUCH and acknowledged nets are in optimized/ring_topology.tsv.

Required next physical work: measure RO bounds and health, review reset pulse
width/CDC bundled-data arrival/RO counter timing, compare DNA ordering against
Hardware Manager, and run board self-test with candidate bit/HWH/manifest. No
entropy, reliability, uniqueness, temperature/aging, secure boot or anti-rollback
claims. IMAGE_VERIFY is not wired to CPU execution control.

## Paired candidate hashes (SHA-256, raw file bytes)

| File | SHA-256 |
|---|---|
| puf.bit | 05c955cdc8ca5d7c019eed1194e4f2403ef1d415e582750fa04c7a1b5cf3dc62 |
| puf.hwh | 61d6e30e6191e84015494f31af39de87e1e9d47d7b499f582d8fce528c6eba34 |
| puf_v2.elf | d9194fe495cb7c7c1e4fb0222ae454a3cb19cef4e5bea6866ed9057c1e24facc |
| puf_v2.coe | 2c5b8ffafec56de2f60f87d357a0aa05a1884f95d5cdcda59333bf744b137bb9 |

`candidate/manifest.json` maps the bit/HWH/firmware/reports; `source_snapshot.json`
maps exact RTL/header/firmware inputs. `sealed.json` hashes owned sources and all
retained evidence. Board CLI verifies the pair before programming; board results
remain **NOT_RUN**. Downstream receiver: parent session/board ownerTBD; integrate
the log handoff without altering original release or treating diagnostic status as
P0/PYNQ acceptance. No commit/push performed.

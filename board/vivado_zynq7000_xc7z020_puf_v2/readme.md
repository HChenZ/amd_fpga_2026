# PUF v2 standalone PYNQ SoC candidate

Task PUF-SOC-V2; owner TBD. This is independent of the original PYNQ release.
No Y01 service or DMA protocol is implemented: the firmware prints an ASCII
self-test log over CPU UART → PL mailbox → PS AXI-Lite.

**Completed offline evidence:** `data/advanced/puf_soc/validation_20261030.md`.
Icarus and four XSim configurations passed; an actual paired candidate exists.
Timed-core WNS is +0.009ns after physical optimization, while unclocked RO and
CDC/methodology limitations explicitly prevent full timing signoff.

## Reproduce

1. `python board/vivado_zynq7000_xc7z020_puf_v2/prepare.py`
   invokes unchanged `src/firmware/keys_v2/build.py` with native xPack RV32 GCC.
   Stores ELF/BIN/HEX/COE and compiler commands/exit codes in
   `data/advanced/puf_soc/firmware/`; `source_snapshot.json` records SHA-256.
2. Start a **new** Vivado Tcl session with this directory as working directory.
   `source setup.tcl` creates only `work/puf_soc.xpr` (xc7z020clg400-1).
   It refuses to overwrite an existing project. For a separate helper-disclosing
   build set `::puf_diagnostic 1` before setup and use a separate working copy.
   Default ABI is normal even when the physical candidate is classified diagnostic.
3. `launch_runs synth_1 -jobs 2`, then `wait_on_run synth_1`.
4. `launch_runs impl_1 -to_step route_design -jobs 2`, then `wait_on_run impl_1`.
   `ring_ack.tcl` runs before opt_design and acknowledges exactly the audited
   feedback nets of 256 rings. Unexpected driver/count aborts the build.
5. `source reports.tcl` exports full timing/CDC/DRC/methodology/clock reports.
   Run `phys_opt_design -directive AggressiveExplore`, then set
   `::puf_report_label optimized` and `::puf_report_current 1` and source reports
   again, preserving the initial reports. `audit_rings.tcl` audits the routed
   ring topology. Save `optimized/puf_postroute.dcp` and write
   `optimized/puf_diagnostic.bit` under the evidence directory. Full recipe is
   `build.tcl`; it requires nonnegative timed setup/hold before emitting the bit.
   This does **not** mean the RO subsystem is timing signed off.
6. `source ../../sim/puf_soc_v2/run_xsim.tcl` runs bounded normal/diagnostic
   SoC tests with simulation-only RO/DNA models, first AXI BRAM BFM then actual
   board wrapper/vendor AXI BRAM controller and COE-initialized block RAM.
7. `python package.py` creates `candidate/` with the optimized bit, matching HWH,
   firmware ELF/COE, source hashes and reports. `python seal.py` retains native
   Vivado logs and evidence hashes. Neither script modifies the original release.

PS7 FCLK0=100MHz drives CPU/control/mailbox/private RAM; FCLK1=25MHz drives PUF
management. The setup checks configured clock values and existence of pins.
No new DDR/MIO board preset is applied: the existing vendor SD image configures
PS boot. Board/image compatibility and actual clock setup must be checked on board.
Vendor IP versions and generated context are in `data/advanced/puf_soc/context.txt`.

## Memory / identity / initialization

| Endpoint | Address | Meaning |
|---|---|---|
| CPU private BRAM | 0x10000000, 128KiB | Real crosscompiled firmware; COE incorporated into bitstream |
| CPU UART | 0x20000000 | Existing uncached UART registers; baud divider 16 |
| CPU PUF v2 | 0x30010000..0x300100ff | Full byte-offset ABI 0x50550202 |
| PS control | 0x40000000, 4KiB | CTRL+0 bit0 holds CPU reset; STAT+4; ID+8; version+c |
| PS mailbox | 0x40001000, 4KiB | RXDATA+4, RXSTAT+c, ID+1c; exact HWH authoritative |

Control ID `0x32554650`; version `2` normal or `258` diagnostic. PUF STATUS bit5
matches the diagnostic mode. The reused mailbox ID remains `0x4d424f58`.
The CPU begins held in reset. Firmware is not a PS-loadable image; changing COE
requires regenerating BRAM and rebuilding the candidate. Pair bit and HWH from
the same implementation with firmware/source hashes; never mix another overlay.

Example board capture (not executed offline):

```sh
sudo python3 capture.py --bit candidate/puf.bit \
  --manifest candidate/manifest.json --out board_result_20261030
```

The CLI loads bit/HWH, validates identity and 100/25MHz clocks, resets the SoC,
captures raw ASCII, detects overflow/deadline/failure and returns nonzero on error.
No simulation fallback. It records firmware/bit/HWH hashes. A self-test PASS only
shows this board's sampled reconstruction/crypto checks succeeded once.

## Physical timing boundary

No physical RO minimum-period bound has been measured. No RO clock period is
invented. No global false paths, clock-group exclusions, or DRC severity downgrades
are used. `ring_ack.tcl` only acknowledges intentional feedback. Reports must show
unclocked RO counter endpoints and any actual synchronous clock violations.
This can produce only a **STRUCTURAL_DIAGNOSTIC_ONLY** candidate, not a release
with complete timing signoff. Normal ABI confidentiality is a separate setting
from this physical diagnostic classification. Constraints/CDC still need review
using measured frequency bounds; reset pulse width, hold/snapshot timing and RO
placement must not be inferred from behavioral models.
The only inherited false paths are the vendor proc_sys_reset XPM constraints to
the two first-stage external/auxiliary reset synchronizers; the applied XDC records
their exact scope. No PUF data/reset path was excluded by this integration.

Not measured: board DNA ordering, real oscillator ranges/health, temperature/aging,
multiple-device uniqueness, physical entropy, power-up helper reconstruction.
No eFuse, secure boot, root of trust or anti-rollback is implemented.

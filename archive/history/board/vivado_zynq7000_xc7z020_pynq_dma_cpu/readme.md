# CPU-preserving DMA experimental handoff

> 2026-11-01 scope: independent D01/ABI v2 CPU-DMA experiment, **not PUF3**. The final physical candidate is
> 80 MHz (040257); plain setup.tcl still selects a retained 100 MHz experiment. Both defaults are intentional
> history and are not changed here. Full SW/ISE1089 target simulations belong to this source/firmware version,
> not to PUF3 board validation. Board NOT_RUN; see docs/version_entrypoints.md for current demonstration.

Owner TBD. Independent experimental overlay; **physical-board execution is not claimed**.
The authorized Vivado continuation below supersedes the earlier source-only handoff.
**Qualified candidate is 80 MHz**, not the failed 100 MHz experiment. Start a fresh
qualified build with `build/advanced/cpu_dma_80mhz.tcl`; plain setup.tcl defaults to
the retained 100 MHz experiment. Original released PYNQ stays unchanged at100MHz.
Release UART overlay and original CPU RTL are unchanged. Firmware lives in
`src/firmware/pynq_dma_svc`; endpoint/controlled CPU copies in `src/rtl/pynq_dma_cpu`.

## Block-design wiring

- Top source wrapper: `pynq_dma_cpu.v`, module `pynq_dma_cpu`. It combines
  `dma_control`, `dma_cpu_endpoint`, and `soc_top_dma`.
- One common PL clock for CPU, endpoint, control and both DMA streams. Active-low
  peripheral reset enters `rst_n`; AXI-Lite control itself remains alive when
  control register reset is asserted.
- AXI DMA **simple mode**, 32-bit MM2S/S2MM stream widths, byte-granular final
  TKEEP, TLAST enabled; transfer-length width sufficient for at least 2144 bytes.
  CPU max request is 160 bytes, response 96. SG mode is rejected by the host.
- PS DDR DMA master ports use the normal PYNQ AXI DMA DDR path; MM2S stream feeds
  `s_axis_*`, S2MM receives `m_axis_*`. Arm S2MM before MM2S.
- PS AXI-Lite connects the control slave; use the same-build HWH address, not an
  assumed physical base. AXI DMA register base also comes from HWH.
- CPU `M_AXI` connects its existing private 128-KiB BRAM/controller, initialized
  from `build/local/pynq_dma_svc/dma_svc.coe`. Connect **cpu_resetn** to this
  controller's reset as well: abort must discard outstanding CPU memory bursts.
- Do not expose CPU BRAM as a PS mailbox; CPU transport is uncached 0x20020000.
  Caller key path is preserved by the explicit P0 SoC/MMIO source selection;
  do not substitute current PUF-enabled `soc_top.v`.

Required CPU source manifest is generated in each `sim/pynq_dma_cpu/run.py`
evidence directory as `sources.json`. For synthesis omit the two testbench/memory
model files, add `dma_control.v` and this wrapper; use actual BRAM IP. Exclude
original `soc_top.v`, `bus_interconnect.v`, `top.v`, `top_pl_bram.v` and current
`ascon_mmio.v`; use the named variant copies and
`board/vivado_zynq7000_xc7z020_pynq/rtl_p0/ascon_mmio.v` instead.

The exact shared AXI-Lite map and CPU MMIO map are frozen in
`src/rtl/pynq_dma_cpu/readme.md`. CPU advertises modes 1/2/3, capacities 32/16/32.
Direct mode 4 shares the host codec but is a different overlay/engine.

## PYNQ 2.7 notebook bringup

The permanent command-line entry is now `bringup.py` in this directory. Prefer it
for recorded checks: it validates artifact identities, locks before download,
constructs raw MMIO from HWH (avoiding PYNQ's unbounded DMA-driver constructor),
and saves raw results to a new JSON file. See `pynq27_audit.md` for exact lifecycle
and the exceptional retained-buffer quarantine behavior.

```sh
# CPU overlay: all advertised SW/HW/ISE modes, official vectors within each capacity.
python board/vivado_zynq7000_xc7z020_pynq_dma_cpu/bringup.py \
  --bit /home/xilinx/dma_cpu.bit --hwh /home/xilinx/dma_cpu.hwh \
  --firmware /home/xilinx/dma_svc.bin --download \
  --control-ip engine --dma-ip dma --modes auto \
  --full --output /home/xilinx/evidence/dma_cpu_full_001.json

# Direct overlay: specify its actual HWH control instance; no CPU firmware applies.
python board/vivado_zynq7000_xc7z020_pynq_dma_cpu/bringup.py \
  --bit /home/xilinx/dma_direct.bit --hwh /home/xilinx/dma_direct.hwh \
  --use-loaded --control-ip engine --dma-ip dma --modes 4 \
  --smoke --benchmark 30 --message-bytes 32 --ad-bytes 32 \
  --output /home/xilinx/evidence/dma_direct_smoke_benchmark_001.json
```

`--bit-sha256`, `--hwh-sha256` and `--firmware-sha256` optionally enforce expected
digests before any hardware access. CPU firmware identity is an operator-supplied
build-artifact binding, explicitly **not readback attestation**. `--use-loaded`
checks PYNQ's loaded filename; `--download` programs the selected bit/HWH pair.
Full checks encrypt/decrypt/reject a bad tag for every supported official vector.
Benchmark samples include actual returned cycles (or null) and separately measured
host wall time, after one checked warmup. All modes/capacities come from the shared
control map; unsupported requested modes and oversize benchmarks fail explicitly.
Public fixed test keys/nonces are for KAT/benchmark only.

Run from a checkout on the board, after deploying a matching bit/HWH pair and
checking the firmware/overlay hashes. Substitute the actual HWH instance names.
Keep this notebook process alive on a failed quiesce; retained buffers must not
be released until a successful `recover()` or externally established device reset.

```python
from pynq import Overlay, MMIO
from src.pynq.dma_transport import pynq_backend, DMABackend
from src.pynq.ascon_host_api import AsconHost
from src.pynq.golden_checker import parse_kat

ol = Overlay('/home/xilinx/dma_cpu.bit', download=False)  # already deployed exclusively
ctl = ol.ip_dict['engine']
dma = ol.ip_dict['dma']
transport = pynq_backend(MMIO(ctl['phys_addr'], ctl['addr_range']),
                        MMIO(dma['phys_addr'], dma['addr_range']),
                        parameters=dma['parameters'], timeout=2.0)
caps = transport.recover()  # random fresh nonzero epoch; no implicit retry
assert caps == {1:(32,32), 2:(16,16), 3:(32,32)}
case = next(c for c in parse_kat() if len(c['PT']) == 16 and len(c['AD']) == 16)
for mode in ('sw', 'hw', 'ise'):
    host = AsconHost(DMABackend(transport, mode))
    result = host.encrypt(case['Key'], case['Nonce'], case['AD'], case['PT'])
    assert result.ciphertext + result.tag == case['CT']
    assert host.decrypt(case['Key'], case['Nonce'], case['AD'],
                        result.ciphertext, result.tag).plaintext == case['PT']
```

The public KAT is test-only. Explicitly check tampered tags, 17-byte HW rejection,
32-byte SW/ISE vectors, reset/recover, and deadlines before collecting timings.
Never label host/RTL unit tests as board results. Cycles are CPU AEAD `mcycle`;
wall time is a separate host measurement. `hw_direct` cycles are PL computation.
The Python backend uses a nonblocking process flock and a nonblocking per-instance
mutex; all applications for this device must honor the same lock path.

## No-board commands / XSim handoff

```text
python src/firmware/pynq_dma_svc/build.py --cc-prefix <toolchain>/riscv-none-elf-
python sim/pynq_dma_cpu/run_unit.py --iverilog <iverilog> --vvp <vvp>
python sim/pynq_dma_cpu/run.py --iverilog <iverilog> --vvp <vvp>
```

XSim tops (all files SystemVerilog, 1ns/1ps):

1. `tb_dma_endpoint`: `src/rtl/pynq_dma_cpu/dma_cpu_endpoint.v`,
   `sim/pynq_dma_cpu/tb_dma_endpoint.v`; watchdog 1 ms.
2. `tb_dma_control`: `src/rtl/pynq_dma_cpu/dma_control.v`,
   `sim/pynq_dma_cpu/tb_dma_control.v`; watchdog 1 ms.
3. `tb_dma_cpu`: exact source list in the CPU run's `sources.json`, includes
   `src/rtl`, `src/rtl/ascon`. Plusargs `HEX=<absolute dma_svc.hex>`,
   `DATA=<absolute evidence directory>`, `CASES=<manifest cases>`,
   `REQUEST_BYTES=<manifest value>`, `RESPONSE_BYTES=<manifest value>`;
   current watchdog 10 s simulated time.
   Require `CPU_DMA_TEST_PASS`, all case markers, no fatal/watchdog.

The earlier handoff did not invoke Vivado/XSim. The subsequent explicit user
authorization created an independent CPU session; the parent's sessions remain
untouched. See the continuation below.

Full official CPU vectors for XSim are prepared in
`data/advanced/dma_cpu/full_20261030_002958_293520/xsim_all/`:
top/source list in `sources.json`, exact plusargs and source/vector SHA-256 in
`manifest.json`. This is 7,401 cryptographic transactions (1,089 SW + 289 HW +
1,089 ISE vectors, each enc/dec/badtag), plus 17 negative protocol packets:
`CASES=7418`, `REQUEST_BYTES=895411`, `RESPONSE_BYTES=469856`.
The same TB performs partial/active/pending reset tests and a recovery KAT.
Icarus completed all supported official CPU vectors in 19 shards with PASS;
`verified_full.json` independently confirms packet contents, unique coverage,
source/vector hashes and terminal markers. At that handoff XSim was pending;
the completed full XSim result is now recorded in Final verification closure below.
That earlier offline host/CLI gate was 30/30 and 10/10, with preserved logs in
`data/advanced/dma_cpu/unit_20261030_005944_999468/`.

## Authorized Vivado continuation

Own Tcl session: `vivado-20261030-010908-1cbde35d`, Vivado 2025.2 build 6299465.
Project: `build/local/dma_cpu/cpu_dma.xpr`, top `cpu_dma_wrapper`, part
`xc7z020clg400-1`. Synthesis/implementation use jobs=2.

`setup.tcl` constructs the actual CPU/DMA BD, imports copies of the restored
baseline `axi_bram_ctrl_0` and `blk_mem_gen_0` XCI, sets the real DMA-service COE,
and records readbacks. `dma_private_bram.v` uses those actual IPs and the same
byte-to-word address mapping as the established PYNQ wrapper. No original XCI,
RTL, firmware or release directory is modified.

The BD uses DMA native memory/stream width 32, memory crossbar width 64 and PS
HP0 width 64. GP0 maps `engine` at 0x40000000 and `dma` at 0x40400000. The CPU
private 128KiB BRAM is at 0x10000000. UART RX is tied high and buttons are tied
zero; no PL GPIO ports are exported. PS `FIXED_IO` and `DDR` **are exported** so
the generated PS pin constraints bind to real top ports. DDR/MIO boot settings
remain the vendor SD image's responsibility, following the existing overlay.

The board wrapper now synchronizes CPU/private-BRAM reset release over two clocks
with asynchronous abort. Its interface metadata associates all four AXI buses
and both resets with the PL clock. Vivado inferred CPU `M_AXI` as AXI4/32 and the
post-propagation DMA/HP widths were checked, not merely requested.

Fresh-project flow (the default refuses an existing XPR):

```tcl
source -notrace build/advanced/cpu_dma_80mhz.tcl
launch_runs synth_1 -jobs 2
wait_on_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 2
wait_on_run impl_1
source -notrace board/vivado_zynq7000_xc7z020_pynq_dma_cpu/collect.tcl
```

`collect.tcl` preserves actual timing/utilization/DRC/methodology/route/clock
reports and effective constraints, rejects negative setup/hold or error/critical
DRC, and additionally requires exported PS ports and zero `Netlist 29-160`
pin-constraint failures before copying a bit/HWH candidate. The initial build
in `data/advanced/dma_cpu/vivado_20261030_015408/` is explicitly **intermediate and
superseded**: its PL timing passed, but unexported PS ports caused those critical
warnings. Its bit/HWH/DCP/BD/logs are preserved; it is not the final deliverable.

### Native simulation flow and scope

`build/advanced/cpu_dma_xsim.tcl` prepares `tb_dma_cpu_vendor` for all 7,418 packets.
This test executes the real RV32 firmware with actual vendor AXI BRAM controller
and initialized block-memory models, plus the board reset synchronizer. It does
not substitute the earlier `axi_slave_bram` BFM for the CPU's private memory.
The AXI-Stream stimulus is still a BFM; AXI DMA, PS and DDR silicon are not
instantiated in this CPU test. The actual complete BD is synthesized/implemented;
do not confuse that wiring gate with a whole-PS behavioral simulation.

```text
python sim/pynq_dma_cpu/run_xsim.py --vivado-root <actual Vivado root>
```

The runner executes Vivado-generated compile/elaborate/simulate scripts and
requires all 7,418 case markers plus `CPU_DMA_VENDOR_TEST_PASS`. It records each
stage's exit code, wall duration, source hashes and complete logs. Windows
plusargs must quote `"KEY=value"` because Vivado's batch argument loader splits
unquoted `=`. The source Tcl now emits quoted values; `--quote-plusargs` also
supports a preserved older generated script without editing it. The TB uses an
explicit 64-bit 10-second watchdog literal; an unsized decimal was truncated by
XSim and that first compile warning is retained in the evidence.

Endpoint/control/reset unit tests passed in both Icarus and XSim. Native XSim
evidence: `xsim_20261030_020522_037685` (endpoint),
`xsim_20261030_020527_060098` (control), `xsim_20261030_020531_854284` (reset), all
under `data/advanced/dma_cpu/`. The complete updated Icarus/host/CLI unit gate
passed in `unit_20261030_014759_090699`.

Preserved setup corrections include IP-relative COE path readback, SystemVerilog
file types for the entire include chain, setting BRAM aperture range before its
offset, making the intended simulation fileset current, and exporting PS pins.
The first HWH audit also encountered optional parameters without a VALUE; the
parser now skips such optional entries while still requiring every audited key.

### Final physical candidate and additional native DMA test

The fixed-port 100MHz design did **not** close: WNS -0.046ns, hold +0.020ns.
The worst cache-address path and the bounded, unsuccessful physical refinement
are recorded in `data/advanced/dma_cpu/vivado_20261030_025251/` and
`data/advanced/dma_cpu/physopt_20261030_030502/`. No failing bitstream is promoted.

`build/advanced/cpu_dma_80mhz.tcl` builds a separate genuine PS FCLK variant under
`build/local/dma_cpu/fclk80`. Its requested/calculated/pin readbacks are
80MHz/80.000000MHz/80000000Hz; routed STA uses 12.500ns. The qualified candidate is
`data/advanced/dma_cpu/vivado_20261030_040257/candidate/`: setup **+0.601ns**, hold
**+0.024ns**, error/critical DRC **0**, invalid PS pin constraints **0**. Utilization:
17,179 LUTs, 21,936 registers, 36.5 BRAM tiles, 4 DSPs. No Fmax claim is made.
Five LUTAR-1 methodology warnings and other noncritical DRC findings remain in
the reports; none was waived or suppressed.

In addition to the full CPU/vendor-memory test, a real AXI DMA 7.1 + actual
CPU/control wrapper + vendor-private-BRAM integration test passed **95/95** cases:
`data/advanced/dma_cpu/xsim_20261030_030042_215364/verified.json`. It checks native
DMA reset/halted proof, fresh IOC completion events, actual S2MM_LENGTH, RX before
TX, output guards, odd-byte responses, and 4KiB burst splitting. The DMA model is
a simulation-only native IP configured from the actual BD's readback values;
it is excluded from synthesis. The memory-facing BFM supports aligned 32-bit
INCR bursts with one outstanding read/write burst and random backpressure.
It is **not** a PS DDR/HP silicon model, nor a simulation of the 64-bit HP upsizer.
No PS cache-coherency or physical-board result is inferred from that BFM.

The integration entry is `build/advanced/cpu_dma_xsim_dma.tcl`; vectors are
produced by `sim/pynq_dma_cpu/prepare_system_vectors.py`. Its first attempt could
not find a directly referenced BD-owned DMA module; that FAIL is preserved in
`xsim_20261030_025656_039012`. The simulation-only vendor-IP correction and the
passing compile/elaborate/run logs are preserved separately.

### Final verification closure

The full unsharded vendor-memory CPU XSim completed **7,418/7,418 packets**, plus
partial-packet reset, reset at an actual ISE start, stalled-response reset and a
post-reset KAT. Evidence and independent source/log verification:
`data/advanced/dma_cpu/xsim_20261030_014606_238543/verified.json`.
Runtime was 10,070.438 wall seconds for 1,495,022,810 ns simulated time; no board
throughput is inferred. The native 95-case actual-DMA system test and all three
native unit tests also passed their independent verifiers.

Latest host/CLI/RTL unit evidence is
`data/advanced/dma_cpu/unit_20261030_043721_118939/`: **32 host tests, 10 CLI tests**,
endpoint/control/reset testbenches and board-wrapper elaboration all passed.
The two final host cases verify immutable input snapshots across control
callbacks and byte-capacity checks for typed arrays.

The final candidate is the **80 MHz** artifact, not either 100 MHz intermediate.
It was synthesized and routed with the real PS frequency configuration and has
matching requested/actual/pin/STA readbacks. Behavioral simulations use a 100 MHz
clock and the same CPU/endpoint/firmware logic; there is no post-route SDF or
physical-board result. Candidate hashes are in `candidate_audit.json`.

# HW_DIRECT offline validation

> 2026-11-01 scope: independent no-CPU HW_DIRECT/mode4 experiment, not the PUF3 board entry.
> Offline/vendor-DMA checks do not establish PUF3 DMA support or board throughput. Keep this source set separate.

Independent NIST Final multiblock AEAD, DMA ABI v2, 1024-byte AD/message limits.
The old `src/rtl/ascon/ascon_aead_core.v` and released UART overlay are unchanged.

## Executable checks

```text
python -X utf8 sim/ascon_dma/run_regression.py
python -X utf8 sim/ascon_dma/run_control.py
python -X utf8 sim/ascon_dma/run_lifecycle.py --backend iverilog
```

`run_regression.py` explicitly uses Icarus, not a claimed XSim invocation. The
current vector set is all1089 official cases × encrypt/decrypt/bad-tag, additional
locked-Python randomized cases through1024, all128 tag-bit corruptions, changed
key/nonce/AD/ciphertext, and protocol errors. It has3467 packet cases. The oracle
and KAT integrity are checked via existing provenance manifests.

`tb_axis_direct` checks AXIS output stability under randomized backpressure,
valid-byte masks, exact response contents, no failed payload/cycles, bounded
timeouts and epoch/reset recovery. `tb_dma_control` checks independent AW/W,
WSTRB, held responses, identity, per-mode capacities and reset-only epoch writes.

`run_lifecycle.py` checks the standalone core's registered read contract,
load/start revocation, busy-input isolation, reset/CLEAR in all14 reachable states,
bad tags, scrubbing and maximum length. A local tag-bypass mutation must compile
and fail at runtime. Read `direct_review.md` for earlier defects and closure.

## Vendor simulation

`build/advanced/vendor_dma_xsim.tcl` creates an independent XSim project using
the actual AXI DMA7.1 IP with a byte-addressed AXI memory BFM and the real direct
engine. Requests/responses cross4KiB boundaries; bursts, write strobes, actual
S2MM length and receive-buffer canaries are checked. The two malformed stream
cases that cannot be emitted by a correctly configured DMA are exercised by the
direct AXIS TB instead; all other packet vectors are used.

This proves IP register/stream/burst interaction in simulation, not real PS DDR,
cache maintenance on Linux, PYNQ device allocation, board timing or throughput.
Preserve per-run source hashes. Early XSim3335/vendor3333 results predate the
BRAM refactor; final source validation must be distinguished from those snapshots.

## Memory architecture and bounds

Final design stores packet body and AD/message/result in synchronous memories.
The first80 packet bytes also populate explicit header/key/nonce registers for
validation. No asynchronous all-packet read mux is needed. Each memory has one
synchronous write port and bounded scrub sweep. Result read data AND its in-range
qualification are registered; abort/busy/authentication suppression remains live.
First accepted input LOAD revokes the previous result/tag.

Core complete cycles include computation/fetch stages, exclude PS/DMA transfer.
RX watchdog bounds the whole partial packet, not just idle gaps. Output-stall
watchdog latches fault but retains valid/data until handshake or reset; it does
not silently violate AXIS by dropping a stalled beat. Host must explicitly recover.
Normal completion scrubs before idle-ready: host must await idle, not immediately
send another packet based only on DMA transfer completion.

## Physical handoff

Use `board/vivado_zynq7000_xc7z020_dma_direct/`. IP readbacks verified32-bit native
DMA/stream, simple mode,64-bit crossbar/HP0. AXI-interconnect ID width warnings
arise from its one-bit source tag versus the PS six-bit ID port; the unused upper
request bits are padded and return upper bits are unused. These are retained in
the logs, not described as zero warnings. Actual PS-port behavior still needs the
board checklist. Exported DDR/FIXED_IO ports prevent PS generated constraints
from being applied to internal pins.

No source-only or simulation-only result is a hardware PASS. Failed first runs
are retained in `data/advanced/dma_direct/` and `build/local/dma_direct/`.

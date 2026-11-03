# PUF SoC simulation

> 2026-11-01 scope: independent PUF v2, not PUF3. Behavioral/model validation remains valid for its recorded source,
> but the old physical candidate is INVALID_DO_NOT_PROGRAM; simulation PASS does not authorize programming it.

`python sim/puf_soc_v2/run.py` runs Icarus normal and diagnostic configurations.
First prepare firmware using the board entry. XSim entry: `run_xsim.tcl`, sourced
only in the new PUF board project/session.

The actual independent SoC includes the CPU, both caches, bus decoder, AXI bridge,
AXI master, UART, P0 Ascon MMIO, and **puf_mmio_physical_v2**. Default physical
digital parameters are retained (20-bit counters, 1024-tick sample window).
Core=100MHz and management=25MHz. Only the ring bank and DNA primitive are modeled;
the main regression uses an AXI BRAM BFM containing the real 128KiB firmware image.
Actual UART bytes enter the existing `pynq_mbox`, then are read through its AXI-Lite
interface with response backpressure. Registered PUF responses are checked.

The real firmware requires reconstruction without enrollment to fail, then enrolls,
encrypts, reconstructs and reproduces ciphertext/tag, decrypts, rejects tampered
tag, tests <=16B image authentication and modified metadata rejection, rejects
invalid length, and clears key-ready. Diagnostic additionally exports/reimports
helper. Required accepted commands: normal 11, diagnostic 14. Terminal PASS also
requires no CPU trap, PUF bus rejection, mailbox overflow, or retained key-ready.
Watchdog is 20ms simulated time, host timeout 600s per run.

Deterministic oscillators are simulation-only; their frequency separation and DNA
value are not physical entropy, reliability or binding evidence. The image test
does not control CPU execution and is not secure boot. Simulation is not STA/CDC
proof. XSim additionally selects `PUF_VENDOR_BRAM` to exercise the actual board
wrapper with vendor AXI BRAM controller and COE-initialized block RAM, in both
normal and diagnostic modes. Vendor BRAM models do not precisely model memory
collisions; this private single-port-memory self-test is not collision coverage.
Physical implementation reports remain separate.

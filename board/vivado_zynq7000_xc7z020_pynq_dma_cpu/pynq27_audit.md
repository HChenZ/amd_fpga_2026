# PYNQ 2.7 DMA backend audit

Owner TBD; source review performed 2026-10-30. This is a software/register audit
and offline test record, not hardware execution evidence.

Reviewed version-pinned upstream source:

- https://pynq.readthedocs.io/en/v2.7.0/_modules/pynq/lib/dma.html
- https://pynq.readthedocs.io/en/v2.7.0/_modules/pynq/buffer.html
- https://pynq.readthedocs.io/en/v2.7.0/_modules/pynq/ps.html

## Findings and implementation

| PYNQ 2.7 behavior | This backend |
|---|---|
| `DMA.__init__` constructs `_SDMAChannel`, whose constructor calls `start()` with an unbounded `while not running` loop | Permanent CLI constructs **raw `MMIO` from `Overlay.ip_dict`**, never accesses `overlay.axi_dma_0` to instantiate the DMA driver |
| `start`, `stop`, `wait` spin; `wait_async` waits for an interrupt | None is used; DMA register polls and quiescence checks have finite monotonic deadlines |
| `_SDMAChannel.idle` reads DMASR bit1; `running` is inverse bit0 | Adapter requires both current-transfer IOC bit12 and idle bit1, rejects halted/error completion; stale IOC/DLY/ERR events are W1C-cleared before each launch |
| `wait` reads actual transferred bytes from channel offset+0x28 | Adapter reads S2MM_LENGTH at **0x58**, after both completion events and before DMA reset; a 48-byte failure response into a larger RX allocation is accepted only at its actual received size |
| `transfer` writes physical address low/high at offset+0x18/+0x1c and byte count at offset+0x28 | Same ordering; S2MM is programmed before MM2S |
| HWH determines SG/micro mode, maximum size, memory-port alignment and DRE | Factory rejects SG/micro/one-channel configurations and derives limits/alignment from HWH; both actual packet size and physical alignment are checked |
| TX `transfer` flushes, RX `wait` invalidates | TX and initialized RX are flushed before publishing addresses; RX invalidates only after completion; no candidate output is returned before protocol validation |
| `PynqBuffer.close()` is a deprecated no-op; `freebuffer()` releases storage; destructor also calls it | Backend uses `freebuffer()` only after quiescence proof, holds strong references on failure, and never uses a context manager around an active DMA buffer |

Direct-core completion has two boundaries: DMA completes at TLAST, but the core
can remain busy while scrubbing approximately 1,024 clocks. `transact()` therefore
waits for exact status **1 (idle-ready)** after validating a successful **or
rejected** response, before returning or releasing buffers. The same deadline
covers transfer and scrub wait. A transient busy state before submission is also
waited out; fault, epoch change, invalid status or deadline triggers recovery.

## Abort and ownership

On transport error the backend first holds endpoint/CPU reset, then requests AXI
DMA reset. Both DMA channels must report halted and the reset bit must clear
before any DDR buffer is wiped/flushed/freed. This separates cancellation of CPU
work from cancellation of DMA memory traffic. The private CPU BRAM controller
must also follow exported `cpu_resetn` as described in the board readme.

Normal completed transactions wait for scrub, then quiesce DMA without resetting
the CPU session. Valid AUTH_FAILED is an ordinary rejected transaction, not an
automatic epoch change. Error paths require explicit `recover()` before reuse.
Recovery aborts the endpoint before quiescing DMA, sets a fresh epoch under held
reset, releases reset, and checks readiness. It never silently resends a request.

Each transaction has the caller's finite deadline. Cleanup has a separate finite
transport timeout; thus a failed transaction can take up to its transaction
budget plus the cleanup budget. Individual MMIO accesses still depend on the
platform's AXI/interconnect behavior; Python cannot interrupt a kernel MMIO load
that the platform itself does not complete.

Process lock acquisition precedes overlay download in the CLI. The backend also
uses a nonblocking single-client mutex and claims each injected DMA adapter.
Do not mix raw-register transfers with PYNQ channel methods on the same DMA.

If reset/halted proof fails, buffers stay globally referenced. A standalone CLI
cannot both terminate and guarantee their lifetime: process exit can let XRT
reclaim them. Therefore this exceptional failure writes `passed=false`,
`quarantined=true`, `exit_code_when_safe=1` immediately and keeps its owning
process alive. Each cleanup retry remains bounded; an external hardware reset
can permit a later verified close. It then exits **1**, never success. Ordinary
validation/protocol/KAT failures exit nonzero after bounded cleanup. This
quarantine is not a retry of the cryptographic request or a benchmark sample.

## Offline checks

Host tests exercise fresh completion events, shorter actual S2MM length, stale
IOC rejection, error bits, HWH limits/alignment, delayed scrub on success/failure,
scrub timeout, CPU reset before quiescence, retained buffers and close retry.
Interruption after RX launch and interruption during cleanup are also covered;
critical cleanup handles `BaseException` so Ctrl-C cannot unwind an active DMA
allocation without quiescence or retention.
CLI tests verify raw-MMIO construction (an IP-driver attribute access deliberately
fails), process-lock-before-download ordering, artifact mismatch rejection,
CPU firmware identity requirement, nonzero failures and explicit quarantine.
Full CLI orchestration uses an explicitly simulated reference adapter and is
labelled `simulated_adapter`; its timings are never reported as board evidence.

The CLI additionally records `Clocks.fclk0_mhz` and the PYNQ reference-clock
assumption used to calculate it. Stock PYNQ 2.7 `_ClocksZynq` defaults to a
50.0MHz reference, whereas this PS IP's metadata declares 33.333333MHz. The
vendor image may customize that assumption. The value is explicitly labelled
register-derived, not an oscillator measurement; no running PLL/DDR configuration
or PYNQ reference assumption is altered by the CLI. Hardware bringup must use
the actual platform reference when interpreting absolute MHz. Raw hardware
cycles and host wall seconds remain separate measurements.

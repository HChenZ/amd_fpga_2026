# Independent CPU DMA variant (owner TBD)

> 2026-11-01 scope: independent CPU-DMA source copies and D01 ABI, not the PUF3 source set.
> Keep its SoC/bus/endpoint selection separate; source changes here do not update the released PUF3 bitstream.

ABI: `docs/advanced_dma_contract.md`, D01Q/D01R v2, 48-byte headers.
Single clock, 32-bit stream, low-contiguous TKEEP, TLAST. One 160-byte request
and 96-byte response slot; no second packet accepted until response consumed.
Whole-transaction watchdog defaults to 50,000,000 clocks. Fault requires reset.
CPU reset must follow `cpu_rst_n`, including epoch changes and faults.
`top_dma.cpu_resetn` exports that reset for the private AXI BRAM controller.
Reset that controller too so aborted memory bursts cannot return stale data.

Controlled copies: `bus_interconnect_dma.v` comes from `src/rtl/bus_interconnect.v`
and adds only the uncached window/registered read mux; `soc_top_dma.v` comes from
the existing board P0 `rtl_p0/soc_top.v`, preserving caller-supplied keys rather
than enabling PUF key selection; `top_dma.v` comes from `src/rtl/top.v` with the
endpoint/stream/reset ports added. All are distinct module names, RV32-only for
this variant. No original RTL file was edited. Exclude original SoC/bus/top from
the variant synthesis list and select the P0 `ascon_mmio.v` explicitly.

## Frozen host AXI-Lite control map

`dma_control` may also wrap the parent's direct engine. All offsets are bytes.

| Offset | Register |
|---|---|
| 00 | RO identity 0x32414d44 (DMA2) |
| 04 | RO version 2 |
| 08 | RW bit0 reset **level**, 1 holds endpoint and CPU in reset; reset value 1 |
| 0c/10 | RW epoch low/high, writes permitted **only with reset held** |
| 14/18 | RO global max message/AD |
| 1c | RO mode mask: bit(mode-1), CPU 7, direct 8 |
| 20 | RO bit0 ready/idle, bit1 busy, bit2 fault; zero while reset held |
| 30/34 | RO SW message/AD capacity (32 CPU) |
| 38/3c | RO old HW message/AD capacity (16 CPU) |
| 40/44 | RO ISE message/AD capacity (32 CPU) |
| 48/4c | RO direct message/AD capacity (0 CPU, 1024 direct) |

Unlisted reads return zero, invalid writes SLVERR. Byte strobes respected.
Epoch must be fresh and nonzero. Quiesce AXI DMA, assert reset, write both epoch
halves, release reset, wait ready. Reset must cancel computation, not just FIFOs.
Direct wrapper parameters: MAX_MSG=MAX_AD=DIRECT_MAX=1024, MODE_MASK=8,
SW_MAX=HW_MAX=ISE_MAX=0. Direct ready must exclude active or faulted work.

## RV32 uncached window 0x20020000

| Offset | Register |
|---|---|
| 00 | RO bit0 complete request available, bit1 response transmitting, bit2 fault |
| 04 | RO request packet byte count |
| 08 | RO pop request word (last high padding zero); invalid read returns zero |
| 0c | WO append response word; full 32-bit stores required |
| 10 | WO response byte length (48..96) |
| 14 | WO 1 publishes response, only after complete request read and exact word count |
| 18/1c | RO epoch low/high |

Read data is registered to match the existing CPU MMIO bus. Candidate plaintext
remains private in firmware until AEAD authentication finishes. Input words clear
on CPU read, output words clear on stream consumption; reset clears both arrays.

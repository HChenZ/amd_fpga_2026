# Independent PUF v2 CPU integration

Owner TBD, task PUF-SOC-V2. New modules only; no original RTL or keys_v2 edits.

- `bus_interconnect_puf_v2`: inherited DMA extension slot repurposed for
  exact `cpu_addr[31:8] == 24'h300100`. Legacy `dma_*` internal names mean
  **PUF MMIO**, not a DMA engine. The complete byte offset `[7:0]` is preserved.
- `soc_top_puf_v2`: real RV32 CPU, caches, AXI bridge/master, CLINT, UART,
  GPIO, cycle-event counters, existing P0 Ascon MMIO, and actual
  `puf_mmio_physical_v2`. The physical wrapper contains DNA and 256 five-LUT rings.
- `top_puf_v2`: AXI naming wrapper; `pynq_puf_soc_v2`: private vendor
  AXI BRAM controller / 32x32768 BRAM. Reset PC and memory base `0x10000000`.
  The original broad memory decode still aliases beyond physical 128KiB;
  firmware/linker are bounded to `0x10000000..0x1001ffff`.

## Timing / errors

CPU fixed-latency MMIO requests are registered by the CPU. On the PUF request
edge the SoC captures combinational `rdata`; the bus registers read selection
on the same edge. Both remain available during the following response cycle.
Writes execute once per request edge with all four byte strobes.

The CPU does not expose a peripheral bus-error input. Rejected PUF reads return
`0xbad0b005`; any rejected access sets a SoC reset-cleared sticky fault that is
ORed into LED[1] and external interrupt. PUF's own fault status remains at
`+0x1c`. This is not an architectural precise load/store access-fault exception.
PS control STAT bit3 observes LED[1]. No normal self-test access may set it.

`DIAGNOSTIC=0` is the default and preserves the v2 no-key-export ABI. Explicit
`DIAGNOSTIC=1` allows reference/helper readback and must have a distinct control
version. It is not a secure helper format. Neither mode exposes internal key.

Clock ports: `clk` 100MHz; `ro_clk` **management** 25MHz, not an oscillator.
Reset release synchronization within the sampler is unchanged. The SoC does not
connect image_ready to CPU execution: image authentication remains a <=16B demo,
not secure boot. No eFuse access, entropy claim, or board measurement is implied.

Build and evidence: `board/vivado_zynq7000_xc7z020_puf_v2/` and
`data/advanced/puf_soc/`. Behavioral oscillator/DNA models exist only in
`sim/puf_soc_v2/`; they must never appear in synthesis source manifests.

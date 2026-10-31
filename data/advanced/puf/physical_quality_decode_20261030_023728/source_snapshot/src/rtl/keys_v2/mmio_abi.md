# PUF v2 MMIO ABI 2, revision 2

2026-10-30; owner TBD. Independent integration, not the existing Ascon/PUF ABI.
`puf_mmio_v2` adds unchanged `keys/device_dna.v` and internally connects
`puf_key_v2` to `crypto_aead`. `puf_mmio_physical_v2` also instantiates 256
physical rings. Earlier v2 module port contracts are unchanged.

## Bus / integration

Inputs: `clk,ro_clk,rst_n,valid,write`, byte offset `addr[7:0]`,
`wdata[31:0],wstrb[3:0]`. Nonphysical wrapper additionally takes `osc[255:0]`.
Outputs: `ready` (constant 1), combinational `rdata[31:0],bus_error`, sticky `irq`,
`image_ready,image_data[127:0]`. No key/raw/debug output port.

Transfer occurs once per rising clk with valid&&ready. Master must deassert valid
or present a new transfer next cycle. No AXI channels or CPU address decode are
implied. For the existing CPU registered MMIO requests, capture rdata on request
edge and hold through the following response cycle, as in the CPU TB. Integrator
must propagate bus_error. Word-aligned offsets only; WSTRB independently merges
little-endian bytes; zero strobes do nothing. Reads have no side effects.

Self-test fixture assigns uncached **0x30010000**, 256 bytes, with full upper-24-bit
decode. This address is NOT added to original SoC/bus_interconnect. Integration must
explicitly allocate/decode it. Core controls/reset release are clk-synchronous;
management/oscillator reset release is synchronized inside sampler. Physical
clock/reset/loop constraints remain parent-owned.

## Registers

| Offset | Access | Meaning |
|---|---|---|
| 00 | R | 0x50550202: magic PU, ABI 2, revision 2 |
| 04 | W | Command byte, only WSTRB[0] acts |
| 08 | R | bit0 busy, 1 live key_ready, 2 sticky done, 3 success, 4 dna_ready, 5 diagnostic, 6 image_ready, 7 enrolled, 8 dna_failed |
| 0c | R | [7:0] operation error, [15:8] sampler error mask |
| 10 | R | transaction_id, increments each accepted command including CLEAR |
| 14,18 | diag R | DNA low32/high25; normal reads zero |
| 1c | R | Rejected bus access flag (1); clears on accepted command/reset |
| 20 | RW | data length byte0, AD length byte1, 0..16; full bytes validated before narrowing |
| 30..3c | RW | Four little-endian input-data words |
| 40..4c | RW | AD words |
| 50..5c | RW | Nonce words |
| 60..6c | RW | Input-tag words |
| 70..7c | W / diag R | Staged helper reference; normal reads zero |
| 80..8c | W / diag R | Staged helper mask; normal reads zero |
| a0,a4 | RW | Image version, target address |
| a8,ac | RW | Caller-expected version, target |
| b0..bc | R | Successful result, zero while active/on failure/revocation |
| c0..cc | R | Successful tag, zero on failure/revocation |
| d0..dc | diag R | Enrolled full reference; normal reads zero |
| e0..ec | diag R | Enrolled mask; normal reads zero |
| f0 | R | Selected-bit quality count, NOT entropy |

`DIAGNOSTIC=0` is default in both wrappers. Explicit `DIAGNOSTIC=1` enables
full-reference/staging/DNA readback and STATUS bit5. This leaks key-recomputation
material and is NOT a secure helper. No address exposes raw response/internal key
in either mode. No existing overlay/release is modified.

Commands: **1 ENROLL, 2 RECONSTRUCT, 3 LOAD_HELPER, 4 ENCRYPT, 5 DECRYPT,
6 IMAGE_VERIFY, 7 CLEAR**. While busy, all nonzero-strobe writes except CLEAR are
rejected with bus_error. Rejected START/helper writes neither queue nor mutate the
active transaction. CLEAR aborts, resets sampling, revokes key/results/image,
clears staged helper/input buffers, and completes successfully. Enrolled helper
survives CLEAR; reset erases it. Use CLEAR to recover sampler lockout. Late
completion cannot revive a cleared operation.

Accepted commands clear previous outputs/image readiness; key commands revoke
key_ready. LOAD requires all **32 helper bytes** written since reset/CLEAR/previous
LOAD attempt. Partial import fails 0x94, revokes key and consumes written-byte map.
Complete LOAD atomically imports helper; RECONSTRUCT must still follow. Helper
staging is locked during all operations; normal provisioning trusts its caller.

Any accepted nonzero-strobe data/helper/metadata write also revokes prior
success/output/image readiness. Changed target/header cannot reuse an old
image_ready. Configuration freezes during operations. done remains sticky until
the next command; irq mirrors done. Status/id use single-client ownership.

Errors: puf_key_v2 0x81..0x85; 0x91 unavailable/revoked key or cipher deadline;
0x92 authentication/core failure; 0x93 missing key, length or image-policy mismatch;
0x94 incomplete helper. Bus errors remain separate from operation completion.

## DNA and image-authentication boundaries

Reset release automatically starts the existing reader once; its DNA is captured
before ENROLL/RECONSTRUCT acceptance. Missing reader completion sets dna_failed
after 256 cycles. SHIFT_SKIP defaults 1, passed to existing reader. Simulation
uses existing `sim/keys/DNA_PORT_sim.v`; physical synthesis uses UNISIM DNA_PORT.
**Physical DNA ordering / SHIFT_SKIP still require board comparison against
hardware-manager DNA.** DNA is not secret.

IMAGE_VERIFY accepts 1..16 bytes and builds AD internally:
LE32(version) || LE32(length) || LE32(target) || LE32(0x32474d49).
Header must match caller-expected version/target. Only successful full-tag decrypt
publishes image_data/image_ready. Tests encrypt a fixed synthetic image with this
AD/internal key, then verify it and reject changed tag/authenticated metadata.

This is an **offline image-authentication demo**, not secure boot. No CPU execution
interlock, trusted boot stub/configuration, monotonic version storage, rollback
protection, helper authentication, physical entropy evidence or larger-image
support is claimed. Caller-controlled expected metadata is not a root of trust.

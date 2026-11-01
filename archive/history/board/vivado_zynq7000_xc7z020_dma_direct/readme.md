# Independent AXI DMA / HW_DIRECT experimental overlay

> 2026-11-01 scope: independent mode4/D01 experiment, no RV32 and no PUF3 UART service.
> Only the 024214 final candidate is the documented experiment candidate; the board remains NOT_RUN.
> Do not mix its PL cycles or 1024-byte capacity into the PUF3 performance table. Original defaults stay unchanged.

Target xc7z020clg400-1, Vivado 2025.2. This is NOT the released RV32/PYNQ overlay.
`setup.tcl` creates a fresh BD: PS7 GP0 control, HP0 DDR, simple AXI DMA with 64-bit
memory crossbar/HP0 and 32-bit native DMA/stream interfaces, and `dma_direct_top`. `loopback` is an optional
setup mode (`set ::dma_variant loopback` before source) connecting MM2S directly to S2MM for transport validation.
Actual DMA native memory width is 32 bits, converted by the 64-bit memory crossbar
to HP0. The first 64-bit DMA/32-bit-stream proposal produced an ignored propagation
write warning; the native width was revised and read back before synthesis.

Control base 0x40000000, DMA AXI-Lite base 0x40400000 (confirm generated HWH).
Control offsets: ID 0=0x32414d44, version4=2, reset8(bit0, default1), epoch low/high
0xc/0x10 (write only in reset), maximum data/AD 0x14/0x18=1024, mode mask0x1c=(1<<(4-1)),
status0x20 bits idle-ready/busy/fault. Per-mode message/AD capacities0x30+8*(mode-1):
modes1..3 zero, mode4 at0x48/0x4c both1024. Same ABI as CPU DMA endpoint.
Assert reset, set a new nonzero epoch, release, wait for scrub before transfer.
DMA completion is not authentication: parse D01R, status and exact byte length.

Build flow: source setup.tcl; launch_runs synth_1 then wait_on_run synth_1;
launch_runs impl_1 -to_step write_bitstream then wait_on_run impl_1; source collect.tcl.
`collect.tcl` and `build/advanced/package_direct.py` are DIRECT-only collectors.
The optional loopback setup is a transport-development entry, not a published
mode-4 candidate; do not use the direct collector/manifest for it.
Never publish a timing-failing candidate as released. Source/bit/HWH/report hashes
and actual test outcomes are in data/advanced; board tests remain NOT_RUN until executed.
PS DDR/MIO setup is supplied by the existing board SD image; board HP-port enablement
must be checked on hardware. Buffer/cache/timeout contracts: docs/advanced_dma_contract.md.
PS DDR and FIXED_IO interfaces are exported rather than left internal; this is required
for the generated dedicated PS pin constraints to bind to top ports. New runs may set
`::dma_work` to a fresh independent path; setup refuses existing projects.

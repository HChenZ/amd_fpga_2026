# Qualified non-board CPU DMA candidate: 80MHz configuration

Owner TBD. Vivado 2025.2 build 6299465, XC7Z020CLG400-1,
`build/local/dma_cpu/fclk80/cpu_dma.xpr`, top `cpu_dma_wrapper`.

| Actual result | Value |
|---|---:|
| Requested / calculated PS FCLK0 | 80 / 80.000000 MHz |
| Clock pin metadata | 80000000 Hz |
| Routed STA period | 12.500 ns |
| Setup WNS | +0.601 ns |
| Hold worst slack | +0.024 ns |
| Error/critical DRC violations | 0 |
| Netlist29-160 pin-constraint failures | 0 |
| LUTs | 17179 |
| Registers | 21936 |
| BRAM tiles | 36.5 (34 RAMB36 + 5 RAMB18) |
| DSPs | 4 |

Latest synthesis/implementation run logs contain no ERROR or CRITICAL WARNING
messages. Methodology retains five LUTAR-1 warnings (reset-combining logic,
legacy Ascon reset logic and vendor converter FIFO logic). Other noncritical DRC
warnings are retained in `drc.rpt`; no severity downgrade or waiver was used.
This is a measured implementation result at one configured frequency, **not Fmax**
and not physical-board validation.

The 100MHz fixed-port design failed setup by 0.046ns. Its path analysis and
artifacts are preserved in `../vivado_20261030_025251/`. A bounded supported
post-route optimization produced no improvement; evidence is in
`../physopt_20261030_030502/`. This candidate changes the PS frequency configuration
in a separate project, rather than editing an XDC period while leaving hardware
clock programming unchanged. The 80MHz requested/calculated/pin/STA values were
checked for agreement. PS DDR/FIXED_IO are top interfaces, not internal pins.

Candidate files are in `candidate/`: `dma_cpu.bit`, `dma_cpu.hwh`, `dma_svc.bin`,
`firmware_build.json`. Their SHA-256 values and the exact HWH memory map are in
`candidate_audit.json`; source/report hashes are in `sha256.json`.

Use CLI instances `--control-ip engine --dma-ip dma`. GP0 windows are 0x40000000
and 0x40400000; CPU private BRAM is 0x10000000..0x1001ffff. DMA memory/stream
widths are 32, memory crossbar/HP0 widths 64. Vendor SD PS initialization is not
replaced. On a board, the CLI records PYNQ's register-derived FCLK value and its
reference-clock assumption; actual platform frequency still requires appropriate
board interpretation, not an assumed conversion from this STA report.

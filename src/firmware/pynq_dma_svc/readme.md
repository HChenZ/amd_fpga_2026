# DMA RV32 firmware v2

Task: advanced DMA CPU path; owner TBD. Independent firmware, no UART v1 changes.
Requests use uncached MMIO at 0x20020000. The CPU reads only a complete bounded
packet, checks ABI/session/id/mode/capacity/framing, then dispatches AEAD.

| Mode | Message/AD maximum | Implementation |
|---|---:|---|
| 1 SW | 32/32 bytes | included production final-standard C |
| 2 HW | 16/16 bytes | existing P0 Ascon MMIO accelerator |
| 3 ISE | 32/32 bytes | included multi-block CPU helpers and custom-0 |
| 4 direct | unsupported | parent independent hardware engine |

The shared helpers already contain multi-block SW/ISE loops and 48-byte SW
scratch buffers; this variant expands the service capacity rather than changing
the production UART ABI. The DMA wrapper checks capacities again and separates
HW timeout/internal failure from tag authentication failure. A still-busy HW
engine latches endpoint fault, resetting CPU instead of allowing stale reuse.

Every valid session ID is consumed even for semantic/framing rejection. A fresh
epoch resets the CPU/last ID. Failure responses have no payload, flags or cycles.
Candidate plaintext is private until complete authentication, then copied to the
response packet; buffers are wiped after use. HW idle state is explicitly zeroized.
The firmware boot has no text/UART or service frame: readiness is transport-level
control readiness; the first request may arrive while startup completes.

## Build evidence

```text
python src/firmware/pynq_dma_svc/build.py --cc-prefix C:/wenjian/toolchain/xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf-
```

Actual compiler: xPack GNU RISC-V GCC 15.2.0, RV32IM_Zicsr/ILP32, `-O2`.
WSL Ubuntu-22.04 and Ubuntu-20.04 `command -v riscv64-unknown-elf-gcc` returned
exit 1; native toolchain from the existing repository build configuration used.
All build commands exit 0. Existing linker script emits an RWX LOAD warning.
No linker/production source was changed to suppress that warning.

Final artifacts are under `build/local/pynq_dma_svc/`:

| Artifact | SHA-256 |
|---|---|
| dma_svc.bin | 8d2d48fa404daaadb9bd0f717fa0e33c1b89aa1e44b959f194ee08eb1b37238d |
| dma_svc.elf | 8b8300bfc8af812db042a4ffd63f560e1f4d5ac495a2e0cd2b97dbc6fbd0cec8 |
| dma_svc.coe | 129698e548fae9c1deefe04eb9ce9d7186bda663432aed1a2be9b680278bbec6 |
| dma_svc.hex | 92b4d05192acf16d63b8c98fa786de32702f9f2e902b42d22a4fc699ef619e51 |

Disassembly check: 27 custom-0 instructions, including one static P12 opcode
0x0000200b, four P8 opcodes 0x0000300b, and state read/write encodings. Real CPU
integration also observes an actual ISE start before testing active cancellation.
Source hashes, commands, binary hashes and complete disassembly are preserved in
`data/advanced/dma_cpu/build_20261030_0021/`. No board cycles are claimed.

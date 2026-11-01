# PUF v2 transport-neutral firmware helper

> 2026-11-01 scope: independent PUF v2 helper/self-test, not the PUF3 service firmware.
> The related old puf_v2 SoC candidate is INVALID; this helper's offline tests do not authorize board programming.

## Integrated RV32 self-test (2026-10-30 update)

`puf_mmio_v2.h/.c` implement the independent ABI in
`src/rtl/keys_v2/mmio_abi.md`, with explicit MMIO I/O fences, transaction-id polling,
bounded timeout and CLEAR recovery. Fixture base is 0x30010000; original SoC decode
is unchanged. `main.c` exercises enroll/reconstruct, ciphertext/tag equality,
decrypt/bad-tag rejection, helper export/import only when diagnostic capability is
advertised, image header authentication, invalid length, and final key revocation.

Build: `python src/firmware/keys_v2/build.py`. Reuses unchanged `keys_rv32` crt0.S,
riscv.ld, uart.c/h, libc_min.c and bin2vhex.py. Real xPack GCC 15.2.0 / binutils
2.45 compile rv32im_zicsr/ilp32, O2, freestanding/no libc, -lgcc. ELF entry
0x10000000, 128KiB RAM, explicit load/store/fence instructions in disassembly.
Unique evidence directories retain ELF/bin/32768-word hex, compiler outputs,
readelf, size, complete objdump, command exit codes and source/artifact hashes.
The unchanged linker emits an RWX LOAD-segment warning; not suppressed.

Execution: `python sim/keys_v2/run_cpu.py` builds firmware then runs actual
unchanged cpu_core + PUF MMIO in normal and diagnostic modes. Memory/cache-fill
and UART-register BFMs replace board memory/UART transport only; real CPU executes
the ELF-derived instructions, including actual peripheral reads/writes.

## Earlier transport-neutral HAL

`puf_v2.c` + `puf_v2.h` implement bounded key-operation polling. ABI=2.
This generic API is retained independently of the integrated MMIO driver above.
An adapter provides status/start/clear callbacks using `struct puf_v2_io` and must:

- Atomically expose transaction_id/busy/done/key_ready/error; latch RTL done until
  the next start/clear (raw single-cycle pulses cannot be polled directly).
- Increment id once per command acceptance; clear old done before start, order
  register writes with platform-correct I/O barriers, keep ownership single-client.
- Implement clear as sampler reset plus key revocation and preserve helper.
- Bind imported helper to a trusted board/build/version/configuration before writes.

The helper accepts success only from the expected new transaction id with done,
not busy, no error and key_ready. Stale completion is ignored; timeout/error invokes
clear. Timeout is a poll budget, not an assumed time unit. Callback transport errors
are returned; an unsuccessful clear is not proof hardware has reset. No key read API,
fallback, automatic retry or reenrollment. Host GCC mock test is in sim/keys_v2;
The real RV32 self-test uses the newer direct MMIO driver. Board execution remains
unverified; host mock results alone do not establish RV32 execution of this generic HAL.

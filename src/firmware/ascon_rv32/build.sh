#!/usr/bin/env bash
# Build the Ascon-AEAD128 software image for the RV32IM softcore.
# Cross-compile, then produce a 32-bit little-endian $readmemh hex file.
set -euo pipefail

cd "$(dirname "$0")"

TOOLCHAIN="${RISCV_TOOLCHAIN:-/c/wenjian/toolchain/xpack-riscv-none-elf-gcc-15.2.0-1/bin}"
export PATH="$TOOLCHAIN:$PATH"

ASCON_DIR="../../../ascon/ascon_c/aead"
OUT_DIR="../../../build/local/ascon_sw"
mkdir -p "$OUT_DIR"

MARCH="rv32im_zicsr"
MABI="ilp32"

CFLAGS="-march=$MARCH -mabi=$MABI -O2 -ffreestanding -nostdlib -fno-builtin \
        -fno-stack-protector -msmall-data-limit=0 -Wall -Wextra -I. -I$ASCON_DIR"

riscv-none-elf-gcc $CFLAGS -T riscv.ld \
    crt0.S main.c uart.c libc_min.c -lgcc \
    -o "$OUT_DIR/ascon_sw.elf"

riscv-none-elf-objcopy -O binary "$OUT_DIR/ascon_sw.elf" "$OUT_DIR/ascon_sw.bin"
# Pad to 32768 words (the hardware BRAM depth) so $readmemh fills every word.
python bin2vhex.py "$OUT_DIR/ascon_sw.bin" "$OUT_DIR/ascon_sw.hex" 32 32768

echo "========================================"
echo "Build OK: $OUT_DIR/ascon_sw.elf"
riscv-none-elf-size "$OUT_DIR/ascon_sw.elf"
echo "========================================"

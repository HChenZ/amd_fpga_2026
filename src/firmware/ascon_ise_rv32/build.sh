#!/usr/bin/env bash
# Build the Ascon-AEAD128 ISE firmware (permutation via custom instruction).
set -euo pipefail

cd "$(dirname "$0")"

TOOLCHAIN="${RISCV_TOOLCHAIN:-/c/wenjian/toolchain/xpack-riscv-none-elf-gcc-15.2.0-1/bin}"
export PATH="$TOOLCHAIN:$PATH"

OUT_DIR="../../../build/local/ascon_ise"
mkdir -p "$OUT_DIR"

MARCH="rv32im_zicsr"
MABI="ilp32"

CFLAGS="-march=$MARCH -mabi=$MABI -O2 -ffreestanding -nostdlib -fno-builtin \
        -fno-stack-protector -msmall-data-limit=0 -Wall -Wextra -I."

riscv-none-elf-gcc $CFLAGS -T riscv.ld \
    crt0.S main.c uart.c libc_min.c -lgcc \
    -o "$OUT_DIR/ascon_ise.elf"

riscv-none-elf-objcopy -O binary "$OUT_DIR/ascon_ise.elf" "$OUT_DIR/ascon_ise.bin"
python bin2vhex.py "$OUT_DIR/ascon_ise.bin" "$OUT_DIR/ascon_ise.hex" 32 32768

echo "========================================"
echo "Build OK: $OUT_DIR/ascon_ise.elf"
riscv-none-elf-size "$OUT_DIR/ascon_ise.elf"
echo "========================================"

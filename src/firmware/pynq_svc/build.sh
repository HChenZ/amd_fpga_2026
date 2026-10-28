#!/usr/bin/env bash
# build.sh —— 交叉编译 pynq_svc（PS<->RV32 邮箱服务固件）并生成 COE
#
# 复用 ascon_hw_rv32 的 crt0.S / libc_min.c / riscv.ld（未修改），
# 只新增 svc_io.c / ascon_modes.c / main.c。
set -euo pipefail

cd "$(dirname "$0")"

if [[ -n "${RISCV_TOOLCHAIN:-}" ]]; then export PATH="$RISCV_TOOLCHAIN:$PATH"; fi
if [[ -z "${CROSS_COMPILE:-}" ]]; then
    if command -v riscv-none-elf-gcc >/dev/null; then CROSS_COMPILE=riscv-none-elf-;
    else CROSS_COMPILE=riscv64-unknown-elf-; fi
fi
PYTHON=${PYTHON:-python3}

ASCON_DIR="../../../ascon/ascon_c/aead"
COMMON="../ascon_hw_rv32"
OUT_DIR="../../../build/local/pynq_svc"
mkdir -p "$OUT_DIR"

MARCH="rv32im_zicsr"
MABI="ilp32"

CFLAGS="-march=$MARCH -mabi=$MABI -O2 -ffreestanding -nostdlib -fno-builtin \
        -fno-stack-protector -msmall-data-limit=0 -Wall -Wextra -I. -I$ASCON_DIR"

"${CROSS_COMPILE}gcc" $CFLAGS -T "$COMMON/riscv.ld" \
    "$COMMON/crt0.S" "$COMMON/libc_min.c" \
    svc_io.c ascon_modes.c main.c -lgcc \
    -o "$OUT_DIR/pynq_svc.elf"

"${CROSS_COMPILE}objcopy" -O binary "$OUT_DIR/pynq_svc.elf" "$OUT_DIR/pynq_svc.bin"
"${CROSS_COMPILE}objdump" -d "$OUT_DIR/pynq_svc.elf" > "$OUT_DIR/pynq_svc.disasm.txt"

"$PYTHON" "$COMMON/bin2vhex.py" "$OUT_DIR/pynq_svc.bin" "$OUT_DIR/pynq_svc.hex" 32 32768
"$PYTHON" bin2coe.py  "$OUT_DIR/pynq_svc.bin" "$OUT_DIR/pynq_svc.coe" 32768

# ISE 指令是否真的进了二进制：custom-0 (opcode 0x0B) 的精确编码
#   ascon.p12 = 0x0000200B (funct3=2)、ascon.p8 = 0x0000300B (funct3=3)
#   ascon.w   = funct3=0（rs1=data, rs2=idx）、ascon.rd = funct3=1（rs1=idx）
ISE_P12=$(grep -c "0000200b" "$OUT_DIR/pynq_svc.disasm.txt" || true)
ISE_P8=$(grep -c "0000300b" "$OUT_DIR/pynq_svc.disasm.txt" || true)
# 所有 custom-0（opcode 0x0B，低 8 位 = 0x0B）指令条数，含 ascon.w / ascon.rd
ISE_ALL=$(grep -cE "^[0-9a-f]+:\s+[0-9a-f]{6}0b\s" "$OUT_DIR/pynq_svc.disasm.txt" || true)

echo "========================================"
echo "Build OK: $OUT_DIR/pynq_svc.elf"
"${CROSS_COMPILE}size" "$OUT_DIR/pynq_svc.elf"
echo "custom-0: p12(0x200B)=$ISE_P12  p8(0x300B)=$ISE_P8  all-opcode-0x0B=$ISE_ALL"
echo "sha256:"
sha256sum "$OUT_DIR/pynq_svc.elf" "$OUT_DIR/pynq_svc.bin" "$OUT_DIR/pynq_svc.coe"
echo "========================================"

#!/bin/bash
#============================================================================
# merge_hex.sh
# Description:
#   Build a shared memory image for JasperGold formal runs.
#   The current system uses a unified RAM, so one merged image is enough.
#
# Usage:
#   bash merge_hex.sh            # default: RV32 official tests
#   ARCH=RV64 bash merge_hex.sh  # merge RV64 official tests
#   ARCH=ALL  bash merge_hex.sh  # merge RV32 and RV64 official tests
#============================================================================

set -euo pipefail

OUTFILE="all_tests.hex"
ROOT="../test/riscv-test"
ARCH="${ARCH:-RV32}"

case "${ARCH}" in
    RV32|rv32)
        PATTERNS=(
            "${ROOT}/RV32/hex/rv32ui-p-*.hex"
            "${ROOT}/RV32/hex/rv32um-p-*.hex"
        )
        ;;
    RV64|rv64)
        PATTERNS=(
            "${ROOT}/RV64/hex/rv64ui-p-*.hex"
            "${ROOT}/RV64/hex/rv64um-p-*.hex"
        )
        ;;
    ALL|all)
        PATTERNS=(
            "${ROOT}/RV32/hex/rv32ui-p-*.hex"
            "${ROOT}/RV32/hex/rv32um-p-*.hex"
            "${ROOT}/RV64/hex/rv64ui-p-*.hex"
            "${ROOT}/RV64/hex/rv64um-p-*.hex"
        )
        ;;
    *)
        echo "Unsupported ARCH=${ARCH}. Use RV32, RV64, or ALL." >&2
        exit 1
        ;;
esac

shopt -s nullglob
FILES=()
for pattern in "${PATTERNS[@]}"; do
    for f in ${pattern}; do
        FILES+=("${f}")
    done
done
shopt -u nullglob

if [ ${#FILES[@]} -eq 0 ]; then
    echo "No hex files matched for ARCH=${ARCH}" >&2
    exit 1
fi

echo "Merging ${#FILES[@]} hex files for ARCH=${ARCH} into ${OUTFILE} ..."
cat "${FILES[@]}" > "${OUTFILE}"

LINECOUNT=$(wc -l < "${OUTFILE}")
echo "Done: merged ${#FILES[@]} files (${LINECOUNT} lines) -> ${OUTFILE}"

#!/bin/bash
#============================================================================
# run_all_tests.sh
# Description:
#   Run JasperGold formal verification test-by-test using the current unified
#   memory model. For each run, the selected hex is copied to all_tests.hex,
#   which is the memory image consumed by unified_ram_formal.sv.
#
# Usage:
#   bash run_all_tests.sh [--gui] [--arch RV32|RV64] [--filter PATTERN]
#============================================================================

set -euo pipefail

JG=${JG:-jg}
MODE="-batch"
ARCH="RV32"
FILTER="*"
RESULTS_DIR="results"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --gui)    MODE=""; shift ;;
        --arch)   ARCH="$2"; shift 2 ;;
        --filter) FILTER="$2"; shift 2 ;;
        *)        echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

case "${ARCH}" in
    RV32|rv32)
        HEX_GLOBS=(
            ../test/riscv-test/RV32/hex/rv32ui-p-${FILTER}.hex
            ../test/riscv-test/RV32/hex/rv32um-p-${FILTER}.hex
        )
        ;;
    RV64|rv64)
        HEX_GLOBS=(
            ../test/riscv-test/RV64/hex/rv64ui-p-${FILTER}.hex
            ../test/riscv-test/RV64/hex/rv64um-p-${FILTER}.hex
        )
        ;;
    *)
        echo "Unsupported ARCH=${ARCH}. Use RV32 or RV64." >&2
        exit 1
        ;;
esac

mkdir -p "${RESULTS_DIR}"
rm -f all_tests.hex

RUN_TCL="run_cpu.tcl"
if [[ "${ARCH}" == "RV64" || "${ARCH}" == "rv64" ]]; then
    RUN_TCL="run_cpu64.tcl"
fi

shopt -s nullglob
HEX_FILES=()
for pattern in "${HEX_GLOBS[@]}"; do
    for file in ${pattern}; do
        HEX_FILES+=("${file}")
    done
done
shopt -u nullglob

TOTAL=0
PASS=0
FAIL=0
ERRORS=""

echo "=========================================="
echo "  JasperGold Batch Formal Verification"
echo "  ARCH   : ${ARCH}"
echo "  Filter : ${FILTER}"
echo "=========================================="

for hex_file in "${HEX_FILES[@]}"; do
    TEST_NAME=$(basename "${hex_file}" .hex)
    TOTAL=$((TOTAL + 1))

    echo ""
    echo ">>> [${TOTAL}] Running: ${TEST_NAME}"

    cp "${hex_file}" all_tests.hex
    rm -rf jgproject/

    ${JG} ${MODE} "${RUN_TCL}" > "${RESULTS_DIR}/${TEST_NAME}.log" 2>&1 || true

    if grep -q "cex\|falsified\|undetermined" "${RESULTS_DIR}/${TEST_NAME}.log" 2>/dev/null; then
        echo "    [FAIL] ${TEST_NAME}"
        FAIL=$((FAIL + 1))
        ERRORS="${ERRORS}\n  - ${TEST_NAME}"
    elif grep -q "proven" "${RESULTS_DIR}/${TEST_NAME}.log" 2>/dev/null; then
        echo "    [PASS] ${TEST_NAME}"
        PASS=$((PASS + 1))
    else
        echo "    [FAIL] ${TEST_NAME}"
        FAIL=$((FAIL + 1))
        ERRORS="${ERRORS}\n  - ${TEST_NAME}"
    fi
done

echo ""
echo "=========================================="
echo "  Summary: ${PASS} PASS / ${FAIL} FAIL / ${TOTAL} TOTAL"
echo "=========================================="

if [ ${FAIL} -gt 0 ]; then
    echo "  Failed tests:"
    echo -e "${ERRORS}"
    echo ""
fi

if [ ${FAIL} -eq 0 ] && [ ${TOTAL} -gt 0 ]; then
    echo ">>> ALL TESTS PASSED <<<"
fi

exit ${FAIL}

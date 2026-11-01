#!/bin/bash
#============================================================================
# run_all_formal.sh
# Description:
#   Run all module-level and CPU-level JasperGold formal checks and print a
#   compact pass/fail summary.
#============================================================================

set -euo pipefail

TARGETS=(
  bypass
  bypass64
  regfile
  regfile64
  predictor
  predictor64
  icache
  icache64
  dcache
  dcache64
  bus_interconnect
  bus_interconnect64
  cpu_axi_bridge
  cpu_axi_bridge64
  axi_master
  axi_master64
  cpu
  cpu64
)

RESULT_FILES=(
  bypass_results.txt
  bypass64_results.txt
  regfile_results.txt
  regfile64_results.txt
  predictor_results.txt
  predictor64_results.txt
  icache_results.txt
  icache64_results.txt
  dcache_results.txt
  dcache64_results.txt
  bus_interconnect_results.txt
  bus_interconnect64_results.txt
  cpu_axi_bridge_results.txt
  cpu_axi_bridge64_results.txt
  axi_master_results.txt
  axi_master64_results.txt
  cpu_results.txt
  cpu64_results.txt
)

echo "=============================================="
echo "  JasperGold Full Formal Regression"
echo "=============================================="

run_target() {
  local target="$1"
  local tries=0
  local max_tries=3

  while (( tries < max_tries )); do
    tries=$((tries + 1))
    echo ">>> Running make ${target} (try ${tries}/${max_tries})"

    if make "${target}"; then
      return 0
    fi

    echo "    [WARN] make ${target} failed"
    if (( tries < max_tries )); then
      echo "    [INFO] waiting before retry..."
      sleep 3
    fi
  done

  return 1
}

check_summary_pass() {
  local summary_file="$1"

  if [[ ! -f "${summary_file}" ]]; then
    return 1
  fi

  if grep -Eq " - cex[[:space:]]*:[[:space:]]*[1-9]" "${summary_file}"; then
    return 1
  fi
  if grep -Eq " - falsified[[:space:]]*:[[:space:]]*[1-9]" "${summary_file}"; then
    return 1
  fi
  if grep -Eq " - undetermined[[:space:]]*:[[:space:]]*[1-9]" "${summary_file}"; then
    return 1
  fi
  if grep -Eq " - unknown[[:space:]]*:[[:space:]]*[1-9]" "${summary_file}"; then
    return 1
  fi
  if grep -Eq " - error[[:space:]]*:[[:space:]]*[1-9]" "${summary_file}"; then
    return 1
  fi

  return 0
}

for idx in "${!TARGETS[@]}"; do
  target="${TARGETS[$idx]}"
  result_file="${RESULT_FILES[$idx]}"
  summary_file="${result_file/_results.txt/_summary.txt}"

  echo ""
  if ! run_target "${target}"; then
    echo "    [FAIL] ${target}  -> make failed after retries"
    continue
  fi

  if check_summary_pass "${summary_file}"; then
    echo "    [PASS] ${target}  -> ${summary_file}"
  else
    echo "    [FAIL] ${target}  -> ${summary_file}"
  fi

  sleep 2
done

echo ""
echo "=============================================="
echo "  Formal regression finished"
echo "=============================================="

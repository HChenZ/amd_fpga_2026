#!/usr/bin/env bash
# Launch a wave of backend variants in parallel and log every one of them.
#
#   build/backend_opt_20261021/run_wave.sh <parallel> <variant> [variant ...]
#   BOPT_SMOKE=1 build/backend_opt_20261021/run_wave.sh 3 fp2 fp3 fpc   # place only
#   BOPT_MAXTHREADS=5 build/backend_opt_20261021/run_wave.sh 4 rep256 ...
#
# Each variant runs with its own working directory (build/local/backend_opt_20261021/logs/<variant>/)
# so Vivado's default vivado.log/jou never collide between parallel runs.
# Its RESULT line is appended to build/local/backend_opt_20261021/results.tsv.
# Refuses to relaunch a variant that already has build/reports/.../result.txt.
set -u
ROOT="C:/wenjian/game/FPGA2026/ours/amd_fpga_2026"
LOCAL="$ROOT/build/local/backend_opt_20261021"
VIVADO="/c/ruanjian/2025.2/Vivado/bin/vivado.bat"
PAR="${1:-3}"; shift || true
if [ "$#" -eq 0 ]; then echo "usage: run_wave.sh <parallel> <variant...>" >&2; exit 2; fi
mkdir -p "$LOCAL/logs"
echo "WAVE start $(date '+%F %T') parallel=$PAR smoke=${BOPT_SMOKE:-0} variants=$*"

running=0
for v in "$@"; do
  if [ -f "$ROOT/build/reports/backend_opt_20261021/$v/result.txt" ]; then
    echo "SKIP $v (already has result.txt)"; continue
  fi
  vdir="$LOCAL/logs/$v"
  mkdir -p "$vdir"
  (
    cd "$vdir" || exit 1
    "$VIVADO" -mode batch -notrace -nojournal \
      -source "$ROOT/build/backend_opt_20261021/run_variant.tcl" \
      -tclargs "$v" > "$vdir/stdout.txt" 2>&1
    rc=$?
    res=$(grep -hE "^RESULT |^SMOKE .*PLACE FAILED|^SMOKE .*place_ok" "$vdir/stdout.txt" | tail -1)
    printf '%s\t%s\t%s\n' "$(date '+%F %T')" "$v" "${res:-EXIT=$rc}" >> "$LOCAL/results.tsv"
    echo "DONE $v rc=$rc :: ${res:-no result line}"
  ) &
  running=$((running+1))
  if [ "$running" -ge "$PAR" ]; then wait -n; running=$((running-1)); fi
done
wait
echo "WAVE end $(date '+%F %T')"
echo "=== collected results ==="
tail -n 40 "$LOCAL/results.tsv" 2>/dev/null

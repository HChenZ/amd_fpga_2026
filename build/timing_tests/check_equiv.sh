#!/usr/bin/env bash
# 等价比对：同一份固件分别跑 control RTL 树与 patched RTL 树，比较 KAT 与周期数。
#
#   bash build/timing_tests/check_equiv.sh <control_rtl_dir> <patched_rtl_dir> [case ...]
#
# 例（C+D 落地后回查 C 之前）：
#   cp -r src/rtl /tmp/rtl_ctrl && (cd /tmp/rtl_ctrl && git apply -p1 -R ../../build/patches/timing_C_*.patch)
#   bash build/timing_tests/check_equiv.sh /tmp/rtl_ctrl src/rtl
#
# 固件输入取自 build/local/key_audit/<case>/firmware.hex（不在库里，见 docs/timing_route_tests_20261024.md）。
set -uo pipefail
cd "$(dirname "$0")/../.."
IV=${IVERILOG_BIN:-/c/wenjian/.vscode/iverilog/bin}
CTL=${1:?usage: check_equiv.sh <control_rtl_dir> <patched_rtl_dir> [case ...]}
PAT=${2:?usage: check_equiv.sh <control_rtl_dir> <patched_rtl_dir> [case ...]}
shift 2
CASES=("$@")
[ ${#CASES[@]} -eq 0 ] && CASES=(ise ise_stall ise_reset ise_sec hw sw)

key=$(date +%s)
OUT=build/local/timing_tests/$key
mkdir -p "$OUT"

build_vvp () { # $1 root  $2 out
  local root="$1" out="$2" rtl rtl2
  rtl=$(ls "$root"/*.v | grep -v -E "/(top|top_pl_bram)\.v$")
  rtl2=$(ls "$root"/ascon/*.v | grep -v "_tb.v$")
  $IV/iverilog -g2012 -I "$root" -I "$root/ascon" -s tb_ascon_sw -o "$out" \
      $rtl $rtl2 sim/ascon/axi_slave_bram.v sim/ascon/tb_ascon_sw.v
}

build_vvp "$CTL" "$OUT/ctl.vvp" || { echo "control build FAILED"; exit 1; }
build_vvp "$PAT" "$OUT/pat.vvp" || { echo "patched build FAILED"; exit 1; }
echo "both vvp built -> $OUT"

hex_of () {
  case "$1" in
    ise)        echo build/local/key_audit/ise_timing_acb_ise/firmware.hex ;;
    ise_stall)  echo build/local/key_audit/ise_timing_acb_ise_stall/firmware.hex ;;
    ise_reset)  echo build/local/key_audit/ise_timing_acb_ise_reset/firmware.hex ;;
    ise_sec)    echo build/local/key_audit/ise_security_timing_acb_ise_security/firmware.hex ;;
    hw)         echo build/local/key_audit/hw_timing_acb_hw/firmware.hex ;;
    sw)         echo build/local/key_audit/sw_timing_acb_sw/firmware.hex ;;
    *)          echo "" ;;
  esac
}
extra_of () {
  case "$1" in
    ise_stall) echo "+HOLD_ISE" ;;
    ise_reset) echo "+RESET_ISE" ;;
    *)         echo "" ;;
  esac
}

fail=0
for c in "${CASES[@]}"; do
  for v in ctl pat; do
    hex=$(hex_of "$c"); extra=$(extra_of "$c")
    log=$OUT/run_${c}_${v}.log
    $IV/vvp "$OUT/$v.vvp" "+HEX=$hex" $extra > "$log" 2>&1
    printf "%-10s %-4s rc=%d PASS=%-2s FAIL=%-2s %s\n" "$c" "$v" "$?" \
      "$(grep -c PASS "$log")" "$(grep -c FAIL "$log")" \
      "$(grep -oE 'ISE cycles *: *[0-9]+|cycles *: *[0-9]+|full MMIO *: *[0-9]+|latency *: *[0-9]+' "$log" | head -3 | tr '\n' ' ')"
  done
  # 周期数与 PASS 行数必须逐条一致
  if ! diff -q <(grep -oE '[0-9]+ cycles|cycles *: *[0-9]+|full MMIO *: *[0-9]+|latency *: *[0-9]+' "$OUT/run_${c}_ctl.log") \
               <(grep -oE '[0-9]+ cycles|cycles *: *[0-9]+|full MMIO *: *[0-9]+|latency *: *[0-9]+' "$OUT/run_${c}_pat.log") > /dev/null; then
    echo "  !! $c: cycle numbers differ"; fail=1
  fi
  if [ "$(grep -c FAIL "$OUT/run_${c}_pat.log")" != "0" ]; then echo "  !! $c: FAIL lines in patched"; fail=1; fi
done
[ $fail -eq 0 ] && echo "EQUIV OK (logs: $OUT)" || echo "EQUIV MISMATCH (logs: $OUT)"
exit $fail

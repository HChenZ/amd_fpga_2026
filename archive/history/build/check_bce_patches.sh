#!/usr/bin/env bash
# Equivalence check for the TIMING B (dcache bus_addr_r CE) and TIMING E
# (ascon_ise cancel out of the 320-bit CE) patches.
# Runs the recorded timing_acb_firmware hexes against the unpatched RTL and the
# patched copy, then compares PASS/FAIL and reported cycles.
# Nothing in src/ or board/ is modified: the patched RTL lives in
# build/local/patches/rtl_patched.
set -uo pipefail
cd "$(dirname "$0")/.."
IV=/c/wenjian/.vscode/iverilog/bin
OUT=build/local/patches
mkdir -p $OUT

build_vvp () { # $1 = rtl root, $2 = output
  local root="$1" out="$2"
  local rtl rtl2
  rtl=$(ls "$root"/*.v | grep -v -E "/(top|top_pl_bram)\.v$")
  rtl2=$(ls "$root"/ascon/*.v | grep -v "_tb.v$")
  $IV/iverilog -g2012 -I "$root" -I "$root/ascon" -s tb_ascon_sw -o "$out" \
      $rtl $rtl2 sim/ascon/axi_slave_bram.v sim/ascon/tb_ascon_sw.v || return 1
}

run_case () { # $1 label  $2 hex  $3.. extra vvp args
  local label="$1" hex="$2"; shift 2
  for v in control patched; do
    local vvp=$OUT/soc_$v.vvp
    local log=$OUT/run_${label}_${v}.log
    $IV/vvp "$vvp" "+HEX=$hex" "$@" > "$log" 2>&1
    local rc=$?
    local cycles=$(grep -oE "ISE cycles *: *[0-9]+|SW cycles *: *[0-9]+|MMIO cycles *: *[0-9]+|cycles *: *[0-9]+" "$log" | head -3 | tr '\n' ' ')
    local kats=$(grep -c "PASS" "$log")
    local fails=$(grep -c "FAIL" "$log")
    printf "%-22s %-8s rc=%d PASS_lines=%-3s FAIL_lines=%-3s %s\n" "$label" "$v" "$rc" "$kats" "$fails" "$cycles"
  done
}

build_vvp src/rtl $OUT/soc_control.vvp || { echo "control build FAILED"; exit 1; }
build_vvp ${PATCH_TREE:-build/local/patches/rtl_patched} $OUT/soc_patched.vvp || { echo "patched build FAILED"; exit 1; }
echo "both vvp built"
echo

run_case ise        build/local/key_audit/ise_timing_acb_ise/firmware.hex
run_case ise_stall  build/local/key_audit/ise_timing_acb_ise_stall/firmware.hex  +HOLD_ISE
run_case ise_reset  build/local/key_audit/ise_timing_acb_ise_reset/firmware.hex  +RESET_ISE
run_case ise_sec    build/local/key_audit/ise_security_timing_acb_ise_security/firmware.hex
run_case hw         build/local/key_audit/hw_timing_acb_hw/firmware.hex
run_case sw         build/local/key_audit/sw_timing_acb_sw/firmware.hex
echo "BCE EQUIVALENCE DONE"

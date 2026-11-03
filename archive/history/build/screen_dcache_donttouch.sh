#!/bin/bash
# Screen the DONT_TOUCH dcache variant (dcache_timing_optimized.v) for
# functional correctness WITHOUT touching the working tree: isolated RTL copy
# with dcache.v replaced; firmware build + iverilog commands mirror
# sim/ascon/run_cpu_regression.py (sw mode).
set -e
R=build/local/dcache_dt_sim
rm -rf "$R"
mkdir -p "$R/rtl/ascon" "$R/out"
cp src/rtl/*.v "$R/rtl/" 2>/dev/null || true
cp src/rtl/*.vh "$R/rtl/" 2>/dev/null || true
cp src/rtl/ascon/*.v src/rtl/ascon/*.vh "$R/rtl/ascon/" 2>/dev/null || true
# dcache source selection: "dt" (DONT_TOUCH experiment) | "head" (committed original)
# | "wt" (working-tree src/rtl/dcache.v, already copied above)
DC="${1:-dt}"
if [ "$DC" = "head" ]; then
  git show HEAD:src/rtl/dcache.v > "$R/rtl/dcache.v"
elif [ "$DC" = "wt" ]; then
  :
else
  cp src/rtl/dcache_experiments/dcache_timing_optimized.v "$R/rtl/dcache.v"
fi
P="C:/wenjian/toolchain/xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf-"
FW=src/firmware/ascon_rv32
"${P}gcc" -march=rv32im_zicsr -mabi=ilp32 -O2 -ffreestanding -nostdlib \
  -fno-builtin -fno-stack-protector -msmall-data-limit=0 -Wall -Wextra \
  -I"$FW" -Iascon/ascon_c/aead -Ibuild/local/key_audit -DTEST_SW \
  -T "$FW/riscv.ld" "$FW/crt0.S" "$FW/main.c" "$FW/uart.c" "$FW/libc_min.c" \
  -lgcc -o "$R/out/firmware.elf"
"${P}objcopy" -O binary "$R/out/firmware.elf" "$R/out/firmware.bin"
python "$FW/bin2vhex.py" "$R/out/firmware.bin" "$R/out/firmware.hex" 32 32768
RTLS=$(ls "$R/rtl"/*.v | grep -vE '/top\.v$|/top_pl_bram\.v$')
RTLS="$RTLS $(ls "$R/rtl/ascon"/*.v | grep -v _tb)"
iverilog -g2012 -I "$R/rtl" -I "$R/rtl/ascon" -s tb_ascon_sw \
  -o "$R/out/soc.vvp" $RTLS sim/ascon/axi_slave_bram.v sim/ascon/tb_ascon_sw.v
vvp "$R/out/soc.vvp" "+HEX=$R/out/firmware.hex" | tee "$R/out/sim.log"
if grep -q '\[RESULT\] tb_ascon_sw PASS' "$R/out/sim.log"; then
  echo "DT_SIM_PASS"
else
  echo "DT_SIM_FAIL"
  exit 1
fi

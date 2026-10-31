"""Real RV32 build using unchanged keys_rv32 startup/linker/UART support."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument("--prefix", default=shutil.which("riscv-none-elf-gcc") or
                    "C:/wenjian/toolchain/xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf-gcc.exe")
parser.add_argument("--out")
args = parser.parse_args()
out = ROOT / (args.out or ("data/advanced/puf/rv32_v2_" + datetime.datetime.now().strftime("%Y%m%d_%H%M%S_%f")))
out.mkdir(parents=True, exist_ok=True)
prefix = args.prefix.removesuffix(".exe").removesuffix("gcc")
records = []


def run(name, cmd):
    p = subprocess.run(list(map(str, cmd)), cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120)
    (out / (name + ".log")).write_bytes(p.stdout)
    records.append(dict(command=list(map(str, cmd)), exit_code=p.returncode, log=name + ".log"))
    print(name, p.returncode, p.stdout.decode(errors="replace")[:1000])
    if p.returncode:
        raise RuntimeError(name)
    return p.stdout


common = "src/firmware/keys_rv32/"
sources = [common + f for f in ("crt0.S", "uart.c", "libc_min.c")]
sources += ["src/firmware/keys_v2/main.c", "src/firmware/keys_v2/puf_mmio_v2.c"]
elf, binary = out / "puf_v2.elf", out / "puf_v2.bin"
try:
    run("compiler_version", [prefix + "gcc", "--version"])
    run("binutils_version", [prefix + "objdump", "--version"])
    run("compile", [prefix + "gcc", "-march=rv32im_zicsr", "-mabi=ilp32", "-O2",
                    "-ffreestanding", "-nostdlib", "-fno-builtin", "-fno-stack-protector",
                    "-msmall-data-limit=0", "-Wall", "-Wextra", "-Werror", "-I" + common,
                    "-T", common + "riscv.ld", *sources, "-lgcc", "-o", elf])
    run("objcopy", [prefix + "objcopy", "-O", "binary", elf, binary])
    run("disassembly", [prefix + "objdump", "-d", "-S", elf])
    run("headers", [prefix + "readelf", "-h", "-A", elf])
    run("size", [prefix + "size", elf])
    run("hex", [sys.executable, common + "bin2vhex.py", binary, out / "puf_v2.hex", "32", "32768"])
finally:
    inputs = sources + [common + "riscv.ld", common + "uart.h", common + "bin2vhex.py",
                        "src/firmware/keys_v2/puf_mmio_v2.h", "src/firmware/keys_v2/build.py"]
    summary = dict(records=records, execution="not_measured_by_build", base="0x30010000 independent fixture",
                   source_sha256={p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in inputs},
                   artifact_sha256={p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in out.iterdir() if p.is_file()})
    (out / "build.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print("EVIDENCE", out)

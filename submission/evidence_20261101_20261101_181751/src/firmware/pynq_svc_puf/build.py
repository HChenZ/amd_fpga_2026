"""Cross-compile pynq_svc_puf (pynq_svc three-mode service + PUF v1 frames) and emit COE/hex.

Same flags, startup, linker script and Ascon sources as src/firmware/pynq_svc/build.sh;
only main.c (copied + Y01P dispatch) and puf_svc.c are new. Run from any directory:
    python -X utf8 src/firmware/pynq_svc_puf/build.py
Output: build/local/pynq_svc_puf/pynq_svc_puf.{elf,bin,hex,coe,disasm.txt,build.json}
"""
import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument("--prefix", default=shutil.which("riscv-none-elf-gcc") or
                    "C:/wenjian/toolchain/xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf-gcc.exe")
parser.add_argument("--out", default="build/local/pynq_svc_puf")
args = parser.parse_args()
prefix = args.prefix.removesuffix(".exe").removesuffix("gcc")
out = ROOT / args.out
out.mkdir(parents=True, exist_ok=True)
records = []


def run(name, cmd):
    p = subprocess.run([str(c) for c in cmd], cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=300)
    (out / (name + ".log")).write_bytes(p.stdout)
    records.append(dict(command=[str(c) for c in cmd], exit_code=p.returncode, log=name + ".log"))
    if p.returncode:
        print(p.stdout.decode(errors="replace"))
        raise SystemExit("%s failed (exit %d)" % (name, p.returncode))
    return p.stdout.decode(errors="replace")


svc = "src/firmware/pynq_svc/"
common = "src/firmware/ascon_hw_rv32/"
here = "src/firmware/pynq_svc_puf/"
sources = [common + "crt0.S", common + "libc_min.c", svc + "svc_io.c", svc + "ascon_modes.c",
           here + "main.c", here + "puf_svc.c"]
elf, binary = out / "pynq_svc_puf.elf", out / "pynq_svc_puf.bin"
run("compiler_version", [prefix + "gcc", "--version"])
run("compile", [prefix + "gcc", "-march=rv32im_zicsr", "-mabi=ilp32", "-O2", "-ffreestanding", "-nostdlib",
                "-fno-builtin", "-fno-stack-protector", "-msmall-data-limit=0", "-Wall", "-Wextra",
                "-I" + svc, "-I" + here, "-Iascon/ascon_c/aead", "-T", common + "riscv.ld", *sources, "-lgcc",
                "-o", elf])
run("objcopy", [prefix + "objcopy", "-O", "binary", elf, binary])
disasm = run("disasm", [prefix + "objdump", "-d", elf])
(out / "pynq_svc_puf.disasm.txt").write_text(disasm, encoding="utf-8")
size = run("size", [prefix + "size", elf])
run("hex", [sys.executable, common + "bin2vhex.py", binary, out / "pynq_svc_puf.hex", "32", "32768"])
run("coe", [sys.executable, svc + "bin2coe.py", binary, out / "pynq_svc_puf.coe", "32768"])

ise = {"p12_0x200b": disasm.count("0000200b"), "p8_0x300b": disasm.count("0000300b"),
       "all_opcode_0x0b": len(re.findall(r"^\s*[0-9a-f]+:\s+[0-9a-f]{6}0b\s", disasm, re.M))}
# The PUF frame handler must really be linked in (not just compiled).
assert "<puf_handle_request>:" in disasm, "puf_handle_request missing from image"
assert ise["p12_0x200b"] >= 1 and ise["p8_0x300b"] >= 1, "ISE instructions missing from image"
inputs = sources + [common + "riscv.ld", svc + "svc.h", here + "puf_svc.h", here + "build.py",
                    common + "bin2vhex.py", svc + "bin2coe.py"]
summary = dict(records=records, size=size.strip(), custom0=ise,
               source_sha256={p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in inputs},
               artifact_sha256={p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                                for p in (binary, out / "pynq_svc_puf.hex", out / "pynq_svc_puf.coe")},
               note="elf hash varies with build metadata; bin/coe are the image fingerprint")
(out / "build.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
print(size)
print("custom-0:", ise)
print("BUILD OK", out)

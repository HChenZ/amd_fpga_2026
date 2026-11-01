"""Extra Icarus regression, not a replacement for parent-owned XSim runs."""
import datetime
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
STAMP = datetime.datetime.now().strftime("%Y%m%d_%H%M%S_%f")
OUT = ROOT / "data/advanced/puf" / ("offline_v2_" + STAMP)
OUT.mkdir(parents=True)
records = []


def run(name, command):
    try:
        result = subprocess.run(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=360)
        code, output = result.returncode, result.stdout
    except subprocess.TimeoutExpired as exc:
        code, output = 124, (exc.stdout or b"") + b"\nHOST_TIMEOUT after 360 seconds\n"
    text = output.decode("utf-8", errors="replace").replace("\r\n", "\n")
    (OUT / (name + ".log")).write_text(text, encoding="utf-8", newline="\n")
    records.append(dict(name=name, command=list(map(str, command)), exit_code=code, log=name + ".log"))
    print(name, code, text[-1500:])
    return code, text


manifest = json.loads((ROOT / "sim/keys_v2/sources.json").read_text())
iverilog = shutil.which("iverilog") or "C:/wenjian/.vscode/iverilog/bin/iverilog.exe"
vvp = shutil.which("vvp") or "C:/wenjian/.vscode/iverilog/bin/vvp.exe"
run("iverilog_version", [iverilog, "-V"])
run("vvp_version", [vvp, "-V"])
run("python_version", [sys.executable, "--version"])
passed = True
for top, tb in zip(manifest["tops"], manifest["testbenches"]):
    image = OUT / (top + ".vvp")
    code, _ = run(top + "_compile", [iverilog, "-g2012", "-Wall", "-I", "src/rtl/ascon", "-s", top,
                                     "-o", str(image), *manifest["sources"], *manifest.get("simulation_only_sources", []), tb])
    if code:
        passed = False
        continue
    code, text = run(top + "_run", [vvp, str(image)])
    passed &= code == 0 and ("TEST_PASS " + top) in text
code, _ = run("helper", [sys.executable, "sim/keys_v2/test_helper_v2.py"])
passed &= code == 0
gcc = shutil.which("gcc")
if gcc:
    run("gcc_version", [gcc, "--version"])
    exe = OUT / "test_firmware_v2.exe"
    code, _ = run("firmware_compile", [gcc, "-std=c99", "-Wall", "-Wextra", "-Werror",
                                       "-I", "src/firmware/keys_v2", "src/firmware/keys_v2/puf_v2.c",
                                       "sim/keys_v2/test_firmware_v2.c", "-o", str(exe)])
    passed &= code == 0
    if code == 0:
        code, text = run("firmware_run", [str(exe)])
        passed &= code == 0 and "TEST_PASS test_firmware_v2" in text
else:
    records.append(dict(name="firmware", status="not_measured", reason="gcc unavailable"))
paths = set(manifest["sources"] + manifest["testbenches"])
paths.update(manifest.get("simulation_only_sources", []))
for folder in ("src/rtl/keys_v2", "sim/keys_v2", "src/firmware/keys_v2", "src/rtl/ascon"):
    paths.update(str(p.relative_to(ROOT)).replace("\\", "/") for p in (ROOT / folder).glob("*") if p.is_file())
paths.add("src/pynq/puf_helper_v2.py")
summary = dict(evidence_kind="behavioral_simulation_and_host_unit_test", backend="Icarus extra fast regression",
               passed=bool(passed), board="not_measured", xsim="parent_owned_not_run_by_this_script",
               records=records, source_sha256={p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in sorted(paths)})
(OUT / "results.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8", newline="\n")
print("EVIDENCE", OUT)
sys.exit(0 if passed else 1)

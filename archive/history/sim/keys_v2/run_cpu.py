"""Build real RV32 firmware, execute normal/diagnostic CPU+PUF integration."""
import datetime
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT / "data/advanced/puf" / ("cpu_v2_"+datetime.datetime.now().strftime("%Y%m%d_%H%M%S_%f"))
OUT.mkdir(parents=True)
records=[]
passed=True


def run(name,command):
    p=subprocess.run(list(map(str,command)),cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=180)
    (OUT/(name+".log")).write_bytes(p.stdout)
    records.append(dict(command=list(map(str,command)),exit_code=p.returncode,log=name+".log"))
    text=p.stdout.decode(errors="replace")
    print(name,p.returncode,text[-1800:])
    return p.returncode,text


cpu=json.loads((ROOT/"sim/keys_v2/cpu_sources.json").read_text())
puf=json.loads((ROOT/cpu["append_manifest"]).read_text())
sources=cpu["sources"]+puf["sources"]+puf["simulation_only_sources"]+[cpu["testbench"]]
iv=shutil.which("iverilog") or "C:/wenjian/.vscode/iverilog/bin/iverilog.exe"
vvp=shutil.which("vvp") or "C:/wenjian/.vscode/iverilog/bin/vvp.exe"
code,_=run("firmware_build",[sys.executable,"src/firmware/keys_v2/build.py","--out",str(OUT/"firmware")])
passed &= code==0
run("iverilog_version",[iv,"-V"])
if passed:
    for top in cpu["tops"]:
        image=OUT/(top+".vvp")
        code,_=run(top+"_compile",[iv,"-g2012","-I","src/rtl","-I","src/rtl/ascon","-s",top,"-o",image,*sources])
        passed &= code==0
        if code==0:
            code,text=run(top+"_run",[vvp,image,"+HEX="+str(OUT/"firmware/puf_v2.hex")])
            passed &= code==0 and "TEST_PASS tb_puf_cpu_v2" in text
paths=set(sources+["src/rtl/defines.v","src/rtl/ascon/ascon_constants.vh",
                  "src/rtl/ascon/ascon_permutation.v","src/rtl/ascon/ascon_round.v","src/rtl/ascon/ascon_word.v",
                  "sim/keys_v2/run_cpu.py","sim/keys_v2/cpu_sources.json","sim/keys_v2/sources.json"])
(OUT/"results.json").write_text(json.dumps(dict(passed=bool(passed),backend="Icarus CPU RTL execution",records=records,
    source_sha256={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in sorted(paths)},
    board="not_measured",xsim="parent_owned"),indent=2)+"\n",encoding="utf-8")
print("EVIDENCE",OUT)
sys.exit(0 if passed else 1)

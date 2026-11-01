"""Read back ISE screenshot evidence, including handshake events in the VCD."""
import hashlib
import json
import re
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "build/local/pynq_puf3/ise_screenshot"
RUN = ROOT / "build/local/pynq_puf3/vivado/pynq_puf3.sim/sim_ise_screenshot/behav/xsim"
DEST = ROOT / "data/ascon/results/ise_screenshot_20261031"


def main():
    identifiers, events, values, scope = {}, {}, {}, []
    time_ps = 0
    vcd = (OUT / "ise_screenshot.vcd").read_text(encoding="utf-8")
    assert re.search(r"\$timescale\s+1ps", vcd), "Unexpected VCD time unit"
    for line in vcd.splitlines():
        fields = line.split()
        if line.startswith("$scope"):
            scope.append(fields[2])
        elif line.startswith("$upscope"):
            scope.pop()
        elif line.startswith("$var"):
            name = "/".join(scope + [fields[4]])
            identifiers[fields[3]] = name
            events[name] = []
        elif line.startswith("#"):
            time_ps = int(line[1:])
        else:
            code = value = None
            if line and line[0] in "01xz" and line[1:] in identifiers:
                code, value = line[1:], line[0]
            elif line.startswith("b") and len(fields) == 2 and fields[1] in identifiers:
                code, value = fields[1], fields[0][1:]
            if code is not None:
                name = identifiers[code]
                values[name] = value
                events[name].append([time_ps / 1000, value])
    checks = int(values["tb_key_ise/checks"], 2)
    errors = int(values["tb_key_ise/errors"], 2)
    transcript = (RUN / "simulate.log").read_text(encoding="utf-8")
    assert "SUMMARY ISE checks=1502 errors=0" in transcript
    assert not re.search(r"(?m)^FAIL|Fatal:|ERROR:", transcript)
    assert checks == 1502 and errors == 0 and time_ps == 37390000
    handshake = {name: rows for name, rows in events.items()
                 if name.rsplit("/", 1)[-1] in ("perm_start", "perm_run", "perm_done", "perm_ack", "cancel")}
    for name in handshake:
        assert any(value == "1" for _, value in handshake[name]), name
    sources = [ROOT / "sim/ascon/tb_key_ise.v", ROOT / "src/rtl/ascon/ascon_ise.v",
               ROOT / "src/rtl/ascon/ascon_permutation.v", ROOT / "src/rtl/ascon/ascon_round.v",
               ROOT / "data/ascon/permutation.mem", ROOT / "sim/ascon/configure_ise_screenshot.tcl",
               ROOT / "sim/ascon/run_ise_screenshot.tcl", ROOT / "sim/ascon/ise_screenshot_view.wcfg"]
    artifacts = [OUT / name for name in ["ise_screenshot.wdb", "ise_screenshot.wcfg", "ise_screenshot.vcd",
                                       "configuration.txt", "verdict.txt"]]
    artifacts += [RUN / name for name in ["xvlog.log", "elaborate.log", "simulate.log"]]
    for path in artifacts:
        assert path.is_file() and path.stat().st_size > 0, path
    summary = {"status": "PASS", "evidence_kind": "behavioral_rtl_simulation", "tool": "Vivado/XSim 2025.2",
               "part": "xc7z020clg400-1", "design_top": "pynq_puf3_wrapper", "simset": "sim_ise_screenshot",
               "simulation_top": "tb_key_ise", "checks": checks, "errors": errors, "finish_ns": time_ps / 1000,
               "handshake_events_ns": handshake,
               "source_sha256": {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources},
               "artifacts": {p.relative_to(ROOT).as_posix(): {"bytes": p.stat().st_size,
                             "sha256": hashlib.sha256(p.read_bytes()).hexdigest()} for p in artifacts},
               "scope": "Existing ISE unit TB; not whole-SoC, timing, CDC, or board validation"}
    DEST.mkdir(parents=True, exist_ok=True)
    for path in [RUN / "xvlog.log", RUN / "elaborate.log", RUN / "simulate.log", OUT / "configuration.txt", OUT / "verdict.txt"]:
        (DEST / path.name).write_bytes(path.read_bytes())
    (DEST / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    project = ROOT / "build/local/pynq_puf3/vivado/pynq_puf3.xpr"
    backup = ROOT / "build/local/pynq_puf3/ise_screenshot_backup/20261031_224938"
    if backup.is_dir():
        before = json.loads((backup / "before.json").read_text(encoding="utf-8"))
        preserved = {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == h
                     for name, h in before.items() if not name.endswith(".xpr")}
        old, new = ET.parse(backup / project.name), ET.parse(project)

        def entries(tree, name):
            fs = next(f for f in tree.iter("FileSet") if f.get("Name") == name)
            return [ET.tostring(f, encoding="unicode") for f in fs.findall("File")]

        protection = {"sources_1_entries_unchanged": entries(old, "sources_1") == entries(new, "sources_1"),
                      "constrs_1_entries_unchanged": entries(old, "constrs_1") == entries(new, "constrs_1"),
                      "candidate_hashes_unchanged": preserved,
                      "project_sha256": hashlib.sha256(project.read_bytes()).hexdigest()}
        assert protection["sources_1_entries_unchanged"] and protection["constrs_1_entries_unchanged"]
        assert all(preserved.values())
        (DEST / "project_preservation.json").write_text(json.dumps(protection, indent=2) + "\n", encoding="utf-8")
    print(f"PASS: {checks} checks, {errors} errors, finish {time_ps / 1000:g} ns")
    for name, rows in handshake.items():
        print(name, "first rising edges (ns):", [t for t, v in rows if v == "1"][:5])
    print("Evidence:", DEST)


if __name__ == "__main__":
    main()

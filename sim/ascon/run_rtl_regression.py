"""Run isolated RTL correctness and full production-source integration gates."""
import argparse
from collections import Counter
import json
from pathlib import Path
import re
import subprocess
import sys
from support import DATA, HERE, ROOT, sha256, verify_sources


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--vectors", type=Path, default=ROOT / "build/local/ascon_rtl")
    parser.add_argument("--iverilog", default="iverilog")
    parser.add_argument("--vvp", default="vvp")
    parser.add_argument("--report", type=Path, default=DATA / "results/rtl_regression.json")
    args = parser.parse_args()
    args.vectors = args.vectors.resolve()
    args.report.parent.mkdir(parents=True, exist_ok=True)
    evidence = dict(schema_version=1, task_ids=["C03", "I04"], owner="TBD",
        evidence_kind="simulation", source_head=subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        origin_main=subprocess.check_output(["git", "rev-parse", "origin/main"], cwd=ROOT, text=True).strip(),
        production_sources_edited=False, commands=[], gates={}, decryption="not_implemented",
        interface_capacity=dict(plaintext_bytes=16, ad_bytes=16, unsupported_length_cases_executed=False),
        source_hashes={p.relative_to(ROOT).as_posix(): sha256(p)
                       for p in sorted((ROOT / "src/rtl/ascon").glob("*")) if p.is_file()},
        validation_source_hashes={p.relative_to(ROOT).as_posix(): sha256(p)
                                  for p in sorted(HERE.glob("*")) if p.suffix in (".py", ".v")})
    full_log = []

    def execute(name, command, timeout=30):
        try:
            run = subprocess.run(command, cwd=ROOT, capture_output=True, timeout=timeout)
            output = (run.stdout + run.stderr).decode("utf-8", errors="replace")
            output = output.replace("\r\n", "\n").replace("\r", "\n")
            record = dict(name=name, command=command, exit_code=run.returncode, output=output)
        except Exception as exc:
            record = dict(name=name, command=command, exit_code=None,
                          output=f"{type(exc).__name__}: {exc}")
        evidence["commands"].append(record)
        full_log.append(f"COMMAND {name}: {command}\nEXIT {record['exit_code']}\n{record['output']}")
        return record

    def compile_gate(name, sources, top, extra=None, run_simulation=False, plusargs=None):
        target = args.vectors / (name + ".vvp")
        command = [args.iverilog, "-g2012", "-Wall", "-I", "src/rtl/ascon",
                   "-s", top, "-o", str(target)] + (extra or []) + sources
        build = execute(name + "/compile", command)
        gate = dict(status="FAIL", compile_exit=build["exit_code"], top=top,
                    sources=sources, functional_simulation=run_simulation)
        if build["exit_code"] == 0:
            gate["status"] = "PASS"
            if run_simulation:
                run = execute(name + "/run", [args.vvp, str(target)] + (plusargs or []))
                gate["simulation_exit"] = run["exit_code"]
                lines = run["output"].splitlines()
                gate["pass_lines"] = sum(line.startswith("PASS ") for line in lines)
                gate["failure_lines"] = [line for line in lines if line.startswith("FAIL ") or "FATAL:" in line]
                gate["observations"] = [line for line in lines if line.startswith("OBSERVATION ")]
                gate["pass_categories"] = dict(Counter(line.split("/", 1)[0][5:] for line in lines if line.startswith("PASS ")))
                expected_marker = "ALL PASS" if name == "peer_testbench" else "SUMMARY errors=0"
                if run["exit_code"] != 0 or gate["failure_lines"] or expected_marker not in run["output"]:
                    gate["status"] = "FAIL"
        evidence["gates"][name] = gate
        print(f"{gate['status']} {name} compile_exit={gate['compile_exit']} simulation_exit={gate.get('simulation_exit', 'not_run')}")

    try:
        manifest = verify_sources()
        vectors = json.loads((args.vectors / "vectors.json").read_text(encoding="utf-8"))
        reference_gate = json.loads((args.vectors / "reference_gate.json").read_text(encoding="utf-8"))
        assert reference_gate["summary"] == dict(passed=12936, failed=0, exit_code=0)
        assert vectors["reference_commits"] == {k: manifest[k] for k in ("ascon_c_commit", "pyascon_commit")}
        assert vectors["official_kat_sha256"] == sha256(DATA / "kat/asconaead128.txt")
        assert vectors["memory_sha256"] == sha256(args.vectors / "aead.mem")
        assert vectors["peer_source_sha256"] == sha256(ROOT / "src/rtl/ascon/ascon_aead_2_tb.v")
        assert vectors["permutation_sha256"] == sha256(DATA / "permutation.mem")
        evidence["reference_preparation_gate"] = dict(
            summary=reference_gate["summary"], metadata=reference_gate["metadata"],
            report_sha256=sha256(args.vectors / "reference_gate.json"))
        evidence["vector_metadata"] = {k: v for k, v in vectors.items() if k != "cases"}
        evidence["cases"] = vectors["cases"]
        peer = [row for row in vectors["cases"] if row["id"].startswith("peer_")]
        evidence["gates"]["peer_expected_reference"] = dict(
            status="PASS" if len(peer) == 5 and vectors["peer_expected_pass"] == 5 else "FAIL",
            cases=5, passed=vectors["peer_expected_pass"], original_provenance="not_documented")
        for tool in (args.iverilog, args.vvp):
            execute(tool + "/version", [tool, "-V"])
        compile_gate("permutation", ["src/rtl/ascon/ascon_permutation.v", "sim/ascon/tb_rtl_permutation.v"],
                     "tb_ascon_permutation_regression", run_simulation=True,
                     plusargs=["+vectors=" + str(DATA / "permutation.mem")])
        compile_gate("isolated_aead_2", ["src/rtl/ascon/ascon_aead_2.v", "sim/ascon/tb_rtl_aead.v"],
                     "tb_ascon_aead_regression", extra=[f"-Ptb_ascon_aead_regression.CASES={len(vectors['cases'])}"],
                     run_simulation=True, plusargs=["+vectors=" + str(args.vectors / "aead.mem")])
        compile_gate("peer_testbench", ["src/rtl/ascon/ascon_aead_2.v", "src/rtl/ascon/ascon_aead_2_tb.v"],
                     "tb", run_simulation=True)
        compile_gate("legacy_aead_interface", ["src/rtl/ascon/ascon_aead.v"], "crypto_aead_encrypt")
        production = [p.relative_to(ROOT).as_posix() for p in sorted((ROOT / "src/rtl/ascon").glob("*.v"))
                      if not p.name.endswith("_tb.v")]
        evidence["full_source_policy"] = "All production .v files included; only *_tb.v excluded as testbench; .vh reached by -I/includes"
        compile_gate("full_production_source_set", production, "crypto_aead_encrypt")
        evidence["production_module_definitions"] = {}
        for path in production:
            text = (ROOT / path).read_text(encoding="utf-8")
            for match in re.finditer(r"^module\s+(\w+)", text, re.M):
                evidence["production_module_definitions"].setdefault(match.group(1), []).append(
                    dict(path=path, line=text[:match.start()].count("\n") + 1))
        evidence["duplicate_modules"] = {name: places for name, places in evidence["production_module_definitions"].items() if len(places) > 1}
    except Exception as exc:
        evidence["gates"]["setup"] = dict(status="FAIL", reason=f"{type(exc).__name__}: {exc}")
        print(f"FAIL setup: {exc}")
    failed = [k for k, v in evidence["gates"].items() if v["status"] != "PASS"]
    evidence["summary"] = dict(status="FAIL" if failed else "PASS", failed_gates=failed,
                               exit_code=1 if failed else 0)
    args.report.write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8", newline="\n")
    args.report.with_suffix(".log").write_text("\n".join(full_log).rstrip("\n") + "\n",
                                             encoding="utf-8", newline="\n")
    print(f"{evidence['summary']['status']} SUMMARY failed_gates={failed}")
    return evidence["summary"]["exit_code"]


if __name__ == "__main__":
    raise SystemExit(main())

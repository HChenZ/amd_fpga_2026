"""Prove the decrypt TB and runner reject functional faults without editing RTL."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from support import DATA, HERE, ROOT, sha256


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--vectors", type=Path, default=ROOT / "build/local/ascon_rtl")
    parser.add_argument("--iverilog", default="iverilog")
    parser.add_argument("--vvp", default="vvp")
    parser.add_argument("--report", type=Path, default=DATA / "results/rtl_integration_harness.json")
    args = parser.parse_args()
    vectors = args.vectors.resolve()
    source_path = ROOT / "src/rtl/ascon/ascon_aead_2.v"
    original_hash = sha256(source_path)
    source = source_path.read_text(encoding="utf-8")
    count = len(json.loads((vectors / "vectors.json").read_text())["cases"])
    records = []

    def run(command):
        result = subprocess.run(command, cwd=ROOT, capture_output=True, timeout=60)
        output = (result.stdout + result.stderr).decode("utf-8", errors="replace").replace("\r\n", "\n")
        return dict(command=command, exit_code=result.returncode,
                    first_failures=[line for line in output.splitlines() if "FAIL " in line or "FATAL:" in line][:4],
                    summaries=[line for line in output.splitlines() if "SUMMARY" in line])

    local = ROOT / "build/local/ascon_rtl"
    local.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="faults_", dir=local) as temporary:
        directory = Path(temporary)
        mutations = {
            "accept_bad_tag": ("if (diff == 0) begin", "if (1'b1) begin"),
            "wrong_plaintext": ("m <= m_reg;", "m <= m_reg ^ 128'h1;"),
            "early_plaintext": ("case (state)\n                IDLE: begin", "if (busy) m <= m_reg;\n            case (state)\n                IDLE: begin"),
        }
        # Mutate only the decrypt portion of an isolated disposable source copy.
        offset = source.index("module crypto_aead_decrypt")
        for name, (old, new) in mutations.items():
            if source[offset:].count(old) != 1:
                raise ValueError(f"Mutation target changed: {name}")
            mutant = directory / (name + ".v")
            mutant.write_text(source[:offset] + source[offset:].replace(old, new, 1), encoding="utf-8", newline="\n")
            executable = directory / (name + ".vvp")
            build = run([args.iverilog, "-g2012", "-I", str(ROOT / "src/rtl/ascon"),
                         "-s", "tb_ascon_decrypt_regression", f"-Ptb_ascon_decrypt_regression.CASES={count}",
                         "-o", str(executable), str(mutant), str(HERE / "tb_rtl_decrypt.v")])
            simulation = run([args.vvp, str(executable), "+vectors=" + str(vectors / "aead.mem")]) if build["exit_code"] == 0 else None
            passed = build["exit_code"] == 0 and simulation["exit_code"] != 0 and bool(simulation["first_failures"])
            records.append(dict(name=name, status="PASS" if passed else "FAIL", compile=build, simulation=simulation,
                                mutated_source_sha256=sha256(mutant)))
            print(f"{'PASS' if passed else 'FAIL'} harness/{name} simulation_exit={simulation['exit_code'] if simulation else 'not_run'}")

        corrupt = directory / "corrupt_vectors"
        corrupt.mkdir()
        for name in ("aead.mem", "vectors.json", "reference_gate.json"):
            shutil.copyfile(vectors / name, corrupt / name)
        with (corrupt / "aead.mem").open("a", encoding="ascii") as handle:
            handle.write("0\n")
        rejection = run([sys.executable, str(HERE / "run_rtl_regression.py"),
                         "--vectors", str(corrupt), "--report", str(directory / "rejected.json")])
        rejected_report = json.loads((directory / "rejected.json").read_text(encoding="utf-8"))
        passed = rejection["exit_code"] != 0 and "Invalid AEAD memory hash" in rejected_report["gates"]["setup"]["reason"]
        records.append(dict(name="corrupt_vector_hash", status="PASS" if passed else "FAIL", run=rejection))
        print(f"{'PASS' if passed else 'FAIL'} harness/corrupt_vector_hash runner_exit={rejection['exit_code']}")
    if sha256(source_path) != original_hash:
        raise ValueError("Production source unexpectedly changed")
    failed = sum(row["status"] != "PASS" for row in records)
    report = dict(task_ids=["C03", "I04"], owner="TBD", evidence_kind="fault_injection",
                  production_source_sha256=original_hash, harness_sha256=sha256(__file__),
                  decrypt_tb_sha256=sha256(HERE / "tb_rtl_decrypt.v"), tests=records,
                  summary=dict(passed=len(records)-failed, failed=failed, exit_code=int(bool(failed))))
    args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8", newline="\n")
    return report["summary"]["exit_code"]


if __name__ == "__main__":
    raise SystemExit(main())

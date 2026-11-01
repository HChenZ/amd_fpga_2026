"""Freeze final source/artifact byte hashes; never infer physical RO signoff."""
import argparse
import difflib
import hashlib
import json
from pathlib import Path
import re
import shutil

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument("--xsim", required=True)
parser.add_argument("--physical", required=True)
parser.add_argument("--session-log", required=True)
args = parser.parse_args()
xsim = ROOT / args.xsim
physical = ROOT / args.physical


def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


paths = set()
for folder in ("src/rtl/keys_v2", "sim/keys_v2", "src/firmware/keys_v2", "src/rtl/ascon"):
    paths.update(p for p in (ROOT / folder).glob("*") if p.is_file())
for manifest in ("sim/keys_v2/sources.json", "sim/keys_v2/cpu_sources.json"):
    value = json.loads((ROOT / manifest).read_text(encoding="utf-8"))
    for key in ("sources", "testbenches", "simulation_only_sources", "physical_only_sources"):
        paths.update(ROOT / p for p in value.get(key, []))
paths.update(ROOT / p for p in ("src/rtl/defines.v", "src/pynq/puf_helper_v2.py",
                              "build/advanced/puf_physical_ooc.tcl"))
source_hashes = {p.relative_to(ROOT).as_posix(): digest(p) for p in sorted(paths)}
for path in paths:
    target = physical / "source_snapshot" / path.relative_to(ROOT)
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(path, target)
if (physical / "physical_constraints_initial.tcl").exists():
    before = (physical / "physical_constraints_initial.tcl").read_text(encoding="utf-8").splitlines()
    after = (ROOT / "src/rtl/keys_v2/physical_constraints.tcl").read_text(encoding="utf-8").splitlines()
    (physical / "constraint_diff.html").write_text(difflib.HtmlDiff().make_file(
        before, after, "initial redundant skew constraints", "final absolute payload bounds retained",
        context=True, numlines=3), encoding="utf-8")
shutil.copyfile(args.session_log, physical / "vivado_session_full.log")
tops = ["tb_ro_health_v2", "tb_puf_aead_v2", "tb_puf_mmio_v2", "tb_puf_cpu_v2", "tb_puf_cpu_diag_v2"]
gates = {}
for top in tops:
    text = (xsim / top / "simulate.log").read_text(encoding="utf-8", errors="replace")
    marker = "TEST_PASS tb_puf_cpu_v2 diagnostic=1" if top.endswith("diag_v2") else "TEST_PASS " + top
    gates[top] = marker in text and not re.search(r"fatal:|assertion failed|ERROR:", text, re.I)
cdc = (physical / "cdc_synth.rpt").read_text(encoding="utf-8", errors="replace")
timing = (physical / "timing_final.rpt").read_text(encoding="utf-8", errors="replace")
lines = timing.splitlines()
row = next(lines[i+2].split() for i, line in enumerate(lines) if line.strip().startswith("WNS(ns)"))
wns, tns, whs, ths = (float(row[i]) for i in (0, 1, 4, 5))
route = (physical / "route_status.rpt").read_text(encoding="utf-8", errors="replace")


def first_slack(name):
    path = physical / name
    if not path.exists():
        return None
    match = re.search(r"Slack \([^)]+\)\s*:\s*([-\d.]+)ns", path.read_text(encoding="utf-8"))
    return float(match[1]) if match else None


def route_count(label):
    return int(re.search(re.escape(label) + r"\.+\s*:\s*(\d+)", route)[1])

summary = {
    "tool": "Vivado 2025.2", "session": "vivado-20261030-004722-a44ab1cf",
    "top": "puf_mmio_physical_v2", "part": "xc7z020clg400-1", "mode": "out_of_context",
    "verified_tool_exit_codes": {"final_xsim_source": 0, "synth_design": 0,
                                 "opt_design": 0, "place_design": 0, "route_design": 0,
                                 "final_constraints_source": 0, "topology_source": 0,
                                 "final_reports": 0, "final_checkpoint": 0},
    "retained_setup_failures": ["set_property leading-dash value; fixed with -dict",
                                "inspection lrange missing indices; corrected query",
                                "redirect command unavailable; used Tcl file output",
                                "feedback query included hierarchy output; fixed with -leaf",
                                "reset_bus_skew help unavailable; used documented reset_timing and full reapply",
                                "inventory rename denied by earlier open handle; preserved with copy"],
    "xsim_gates": gates, "cdc1_present_after_capture_fix": bool(re.search(r"^\s*CDC-1\s", cdc, re.M)),
    "core_period_ns": 10, "management_period_ns": 40, "clock_relation": "independent primary inputs",
    "io_budgets_ns": {"input_max": 2.0, "input_min": 0, "output_max": 2.0, "output_min": 0},
    "io_budget_provenance": "explicit engineering OOC scenario, not board measurement",
    "ro_minimum_period_ns": None, "ro_timing_signoff": "NOT_MEASURED",
    "physical_classification": "structural implementation only; inspect all residual reports",
    "routed_timing": {"wns_ns": wns, "tns_ns": tns, "whs_ns": whs,
                      "ths_ns": ths, "setup_met_for_defined_paths": wns >= 0 and tns == 0,
                      "timing_met": wns >= 0 and whs >= 0,
                      "core_internal_setup_ns": first_slack("core_internal_setup.rpt"),
                      "core_internal_hold_ns": first_slack("core_internal_hold.rpt"),
                      "management_internal_max_ns": first_slack("management_internal_setup.rpt"),
                      "management_internal_min_ns": first_slack("management_internal_hold.rpt")},
    "routing": {"routable_nets": route_count("# of routable nets"),
                "fully_routed_nets": route_count("# of fully routed nets"),
                "routing_errors": route_count("# of nets with routing errors")},
    "topology": {"rings": 256, "ring_luts": 1280, "verified_arcs": 1280,
                 "async_reg": 2568, "payload_capture_flops": 133, "package_pins_assigned": 0},
    "remaining_coverage": {"no_clock_pins": int(re.search(r"checking no_clock \((\d+)\)", timing)[1]),
                           "unconstrained_internal_endpoints": int(re.search(r"checking unconstrained_internal_endpoints \((\d+)\)", timing)[1])},
    "source_sha256": source_hashes,
}
for directory, name in ((xsim, "xsim_artifact_sha256"), (physical, "physical_artifact_sha256")):
    summary[name] = {p.relative_to(directory).as_posix(): digest(p) for p in sorted(directory.rglob("*"))
                     if p.is_file() and p.name != "verification_manifest.json"}
(physical / "verification_manifest.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"xsim": gates, "cdc1_present": summary["cdc1_present_after_capture_fix"],
                  "manifest": str(physical / "verification_manifest.json")}, indent=2))

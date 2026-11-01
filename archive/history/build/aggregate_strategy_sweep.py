#!/usr/bin/env python
"""Aggregate the implementation-strategy sweep results into CSV/JSON.

Parses per-strategy Vivado reports under build/reports/strategy_sweep_20261017/,
merges durations from sweep_summary.tsv, and optionally includes the V06
round-one/round-two reports as reference rows (same tool/part/RTL, measured on
a different worktree/machine).

Usage: python build/aggregate_strategy_sweep.py
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REPORT = ROOT / "build" / "reports" / "strategy_sweep_20261017"
OUT = ROOT / "data" / "ascon" / "results" / "strategy_sweep_20261017"
REFERENCE_REPORTS = [
    # (name, strategy, report_dir, note)
    ("r1_default_reference", "Vivado Implementation Defaults",
     ROOT / "build" / "reports" / "ascon_timing_r1",
     "V06 round 1, E:/ worktree 2026-10-16, same tool/part/RTL"),
    ("r2_perfexplorepostroute_reference", "Performance_ExplorePostRoutePhysOpt",
     ROOT / "build" / "reports" / "ascon_timing_r2",
     "V06 round 2, E:/ worktree 2026-10-16, same tool/part/RTL"),
]

NUM = r"([-+]?\d+(?:\.\d+)?)"


def parse_timing_summary(path: Path):
    """Return dict with wns/tns/failing endpoints/hold/pulse-width numbers."""
    text = path.read_text(errors="replace")
    lines = text.splitlines()
    header = re.compile(r"WNS\(ns\).*TNS Failing Endpoints")
    data = re.compile(
        rf"^\s*{NUM}\s+{NUM}\s+(\d+)\s+(\d+)\s+{NUM}\s+{NUM}\s+(\d+)\s+(\d+)"
        rf"\s+{NUM}\s+{NUM}\s+(\d+)\s+(\d+)\s*$"
    )
    for i, line in enumerate(lines):
        if header.search(line):
            for j in range(i + 1, min(i + 4, len(lines))):
                m = data.match(lines[j].strip())
                if m:
                    (wns, tns, fep, tep, whs, ths, fep_h, tep_h,
                     wpws, tpws, fep_p, tep_p) = m.groups()
                    return {
                        "wns": float(wns), "tns": float(tns),
                        "failing_endpoints": int(fep), "total_endpoints": int(tep),
                        "whs": float(whs), "ths": float(ths),
                        "wpws": float(wpws), "tpws": float(tpws),
                    }
    return {}


def parse_utilization(path: Path):
    """Return {lut, ff, bram, dsp} from a report_utilization .rpt."""
    text = path.read_text(errors="replace")
    out = {}
    keys = {
        "Slice LUTs": "lut", "Slice Registers": "ff",
        "Block RAM Tile": "bram", "DSPs": "dsp",
    }
    # LUT line appears twice (table + hierarchy); first occurrence is the table.
    for name, key in keys.items():
        m = re.search(rf"\|\s*{re.escape(name)}\s*\|\s*([\d.]+)", text)
        if m:
            out[key] = float(m.group(1))
    return out


def parse_worst_path(path: Path):
    """First path block of report_timing: startpoint, endpoint, slack."""
    text = path.read_text(errors="replace")
    sp = re.search(r"(?:Startpoint|Source)\s*:\s*(\S+)", text)
    ep = re.search(r"(?:Endpoint|Destination)\s*:\s*(\S+)", text)
    sl = re.search(r"[Ss]lack(?:\s*\(VIOLATED\))?\s*:\s*([-+]?\d+\.\d+)", text)
    return {
        "worst_startpoint": sp.group(1) if sp else None,
        "worst_endpoint": ep.group(1) if ep else None,
        "worst_slack": float(sl.group(1)) if sl else None,
    }


def parse_summary_tsv(path: Path):
    """strategy -> duration_s (from the sweep script's live summary)."""
    if not path.exists():
        return {}
    out = {}
    for line in path.read_text(errors="replace").splitlines():
        parts = line.split("\t")
        if len(parts) < 4 or parts[0].startswith("strategy"):
            continue
        # strategy run duration_s wns tns failing whs
        try:
            out[parts[1]] = int(parts[2])
        except ValueError:
            continue
    return out


def collect(dirpath: Path, name: str, strategy: str, note: str,
            durations: dict):
    entry = {
        "run": name, "strategy": strategy, "note": note,
        "duration_s": durations.get(name),
    }
    tp = dirpath / "route_timing.rpt"
    if tp.exists():
        entry["parsed"] = True
        entry.update(parse_timing_summary(tp))
    else:
        entry["parsed"] = False
    up = dirpath / "route_utilization.rpt"
    if up.exists():
        entry.update(parse_utilization(up))
    pp = dirpath / "route_paths.rpt"
    if pp.exists():
        entry.update(parse_worst_path(pp))
    entry["missing_reports"] = [
        f for f in ("route_timing.rpt", "route_utilization.rpt",
                    "route_paths.rpt", "route_drc.rpt", "methodology.rpt",
                    "check_timing.rpt", "route_status.rpt")
        if not (dirpath / f).exists()
    ]
    return entry


def main():
    if not REPORT.is_dir():
        raise SystemExit('Historical sweep reports were pruned by the authorized cleanup. '
                         'Use build/summarize_timing_acb.py for the final dual-strategy reports, '
                         'or regenerate the sweep in an isolated project before aggregation.')
    results = []
    durations = parse_summary_tsv(REPORT / "sweep_summary.tsv")
    if REPORT.exists():
        for sub in sorted(p for p in REPORT.iterdir() if p.is_dir()):
            strategy = ""
            props = sub / "strategy_props.txt"
            if props.exists():
                m = re.search(r"^strategy=(.*)$", props.read_text(
                    errors="replace"), re.M)
                if m:
                    strategy = m.group(1).strip()
            results.append(collect(sub, sub.name, strategy,
                                   "sweep run, this machine", durations))
    for name, strategy, dirpath, note in REFERENCE_REPORTS:
        if dirpath.exists():
            results.append(collect(dirpath, name, strategy, note, {}))

    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "strategy_sweep_summary.json").write_text(
        json.dumps(results, indent=2) + "\n", encoding="utf-8")

    cols = ["run", "strategy", "note", "duration_s", "wns", "tns",
            "failing_endpoints", "total_endpoints", "whs", "ths", "wpws",
            "tpws", "lut", "ff", "bram", "dsp", "worst_startpoint",
            "worst_endpoint", "worst_slack", "parsed", "missing_reports"]
    with (OUT / "strategy_sweep_summary.csv").open("w", encoding="utf-8",
                                                   newline="") as fh:
        fh.write(",".join(cols) + "\n")
        for e in results:
            fh.write(",".join(str(e.get(c, "")) for c in cols) + "\n")
    print(f"Wrote {len(results)} entries to {OUT}")
    for e in results:
        t = e.get("wns")
        print(f"  {e['run']:42s} WNS={t if t is not None else 'missing'}")


if __name__ == "__main__":
    sys.exit(main())

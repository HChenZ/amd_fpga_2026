#!/usr/bin/env python3
"""Extract the sign-off criteria from the io_sta report directories.

Reads, for every variant directory under build/reports/io_sta_20261027/:
  route_timing.rpt   -> WNS/TNS/failing endpoints/WHS/THS/total endpoints (Design Timing Summary)
  check_timing.rpt   -> counts of every check_timing rule (first "checking <rule> (n)" line)
  route_drc.rpt      -> DRC errors / warnings (report summary table)
  route_paths.rpt    -> worst path startpoint/endpoint/slack
and writes result.txt next to them in the same "RESULT ..." shape used by
build/build_keys_sta.tcl.

Numbers are parsed from Vivado's own reports; nothing is typed by hand.
"""
import re
import sys
from pathlib import Path

ROOT = Path(r"C:/wenjian/game/FPGA2026/ours/amd_fpga_2026/build/reports/io_sta_20261027")


def parse_timing(p: Path):
    txt = p.read_text(errors="replace")
    # Design Timing Summary: header line then the value line
    m = re.search(
        r"Design Timing Summary.*?\n\s*WNS\(ns\).*?\n\s*-+\s+-+\s*-+\s*-+\s*-+\s+-+\s+-+\s*-+\s*-+\s*-+\s*-+\s*-+\s*-+\s*-+\s*-+\s*\n\s*(-?[\d.]+)\s+(-?[\d.]+)\s+(\d+)\s+(\d+)\s+(-?[\d.]+)\s+(-?[\d.]+)\s+(\d+)\s+(\d+)",
        txt,
        re.S,
    )
    if not m:
        return None
    keys = ["wns", "tns", "fail_ep", "total_ep", "whs", "ths", "ths_fail", "th_total"]
    return dict(zip(keys, m.groups()))


def parse_checks(p: Path):
    seen, out = set(), []
    for line in p.read_text(errors="replace").splitlines():
        m = re.search(r"checking\s+([A-Za-z0-9_]+)\s+\((\d+)\)", line)
        if m and m.group(1) not in seen:
            seen.add(m.group(1))
            out.append(f"{m.group(1)}={m.group(2)}")
    return out


def parse_drc(p: Path):
    txt = p.read_text(errors="replace")
    m = re.search(r"Checks found:\s*(\d+)", txt)
    checks = m.group(1) if m else "?"
    sev = re.findall(r"^\|\s*([A-Z]+[A-Z0-9-]*)\s*\|\s*(Error|Critical Warning|Warning|Advisory)\s*\|", txt, re.M)
    counts = {}
    for _, s in sev:
        counts[s] = counts.get(s, 0) + 1
    return checks, counts


def parse_worst(p: Path):
    txt = p.read_text(errors="replace")
    m = re.search(r"Slack \((?:MET|VIOLATED)\)\s*:\s*(-?[\d.]+)ns.*?\n\s*Source:\s*(\S+).*?\n\s*Destination:\s*(\S+)", txt, re.S)
    if not m:
        return None
    return m.group(1), m.group(2), m.group(3)


def main():
    rc = 0
    for d in sorted(p for p in ROOT.iterdir() if p.is_dir()):
        t = d / "route_timing.rpt"
        c = d / "check_timing.rpt"
        if not (t.exists() and c.exists()):
            print(f"SKIP {d.name}: missing reports")
            continue
        tm = parse_timing(t)
        checks = parse_checks(c)
        drc = parse_drc(d / "route_drc.rpt") if (d / "route_drc.rpt").exists() else ("?", {})
        worst = parse_worst(d / "route_paths.rpt") if (d / "route_paths.rpt").exists() else None
        lines = []
        if tm:
            lines.append(
                "RESULT io_sta variant={v} wns={wns} tns={tns} failing={fail_ep} total_endpoints={total_ep} "
                "whs={whs} ths={ths} ths_failing={ths_fail}".format(v=d.name, **tm)
            )
        else:
            lines.append(f"RESULT io_sta variant={d.name} TIMING_TABLE_NOT_PARSED")
            rc = 1
        lines.append("CHECK_TIMING " + " ".join(checks))
        (d / "check_timing_summary.txt").write_text(
            "\n".join(checks) + "\n# parsed from check_timing.rpt (first occurrence of each rule)\n"
        )
        lines.append(f"DRC checks_found={drc[0]} severities={drc[1]}")
        if worst:
            lines.append(f"PATH slack={worst[0]} start={worst[1]} end={worst[2]}")
        lines.append("NOTE numbers parsed from Vivado reports in this directory; no hand-typed values")
        (d / "result.txt").write_text("\n".join(lines) + "\n")
        print("\n".join(lines))
        print()
    return rc


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python
"""Collect the R2 replication wave (build/reports/tests_20261025) into a table.

Per arm it reports: WNS/TNS/failing/WHS, replica cells, the four sel_* net
fanouts after routing, the worst path, and every phys_opt fanout-optimization
verdict taken from the run log ("Identified N candidate nets" / "Optimized M net").

usage: python build/timing_tests/collect_r2.py [wave] [--md]
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
WAVE = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith("--") else "tests_20261025"
RPT = os.path.join(ROOT, "build", "reports", WAVE)
LOG = os.path.join(ROOT, "build", "local", WAVE, "logs")

ORDER = ["r2_ctl", "r2_popt", "r2_net1", "r2_net2",
         "r2_net1_cell", "r2_all4_cell", "r2_net1_aggr", "r2_net1_mf16"]


def read(path):
    try:
        with open(path, "r", errors="replace") as fh:
            return fh.read()
    except OSError:
        return ""


def parse_result(tag):
    txt = read(os.path.join(RPT, tag, "result.txt"))
    if not txt:
        return None
    out = {"tag": tag}
    m = re.search(r"wns=(-?[\d.]+) tns=(-?[\d.]+) failing=(\d+) whs=(-?[\d.]+)", txt)
    if m:
        out["wns"], out["tns"], out["failing"], out["whs"] = m.groups()
    m = re.search(r"luts=(\d+) ffs=(\d+) rep_cells=(\d+)", txt)
    if m:
        out["luts"], out["ffs"], out["reps"] = m.groups()
    m = re.search(r"PATH start=(\S+) end=(\S+) dp=([\d.]+) logic=([\d.]+) net=([\d.]+) levels=(\d+)", txt)
    if m:
        out["start"], out["end"], out["dp"], out["logic"], out["net"], out["levels"] = m.groups()
    fo = re.findall(r"NET fo=(\S+) (\S+)", txt)
    out["sel_fo"] = "/".join(f[0] for f in fo)
    out["hook"] = (re.search(r"HOOK (\S+)", txt) or [None, "none"])[1]
    return out


def parse_log(tag):
    txt = read(os.path.join(LOG, f"{tag}.log"))
    ev = {"identified": [], "optimized": [], "parent_alias": 0, "hook": []}
    if not txt:
        return ev
    for m in re.finditer(r"Identified (\d+) candidate nets? for fanout optimization", txt):
        ev["identified"].append(int(m.group(1)))
    for m in re.finditer(r"Optimized (\d+) net\. Created (\d+) new instance", txt):
        ev["optimized"].append((int(m.group(1)), int(m.group(2))))
    ev["parent_alias"] = len(re.findall(r"Using parent net", txt))
    for m in re.finditer(r"^R2 (.*)$", txt, re.M):
        ev["hook"].append(m.group(1).strip())
    return ev


def main():
    rows = []
    for tag in ORDER:
        r = parse_result(tag)
        if r is None:
            rows.append({"tag": tag, "missing": True})
            continue
        r["ev"] = parse_log(tag)
        rows.append(r)

    for r in rows:
        if r.get("missing"):
            print(f"{r['tag']:<14} (no result.txt)")
            continue
        print(f"{r['tag']:<14} WNS {r['wns']:>7}  TNS {r['tns']:>7}  fail {r['failing']:>3}  WHS {r['whs']:>6}  "
              f"reps {r['reps']:>3}  LUT {r['luts']}  FF {r['ffs']}  sel fo {r['sel_fo']}")
        print(f"               hook={r['hook']}  levels={r['levels']} dp={r['dp']} logic={r['logic']} net={r['net']}")
        print(f"               start={r['start']}")
        print(f"               end  ={r['end']}")
        ev = r["ev"]
        print(f"               phys_opt: identified={ev['identified']} optimized(net,created)={ev['optimized']} "
              f"parent_net_lines={ev['parent_alias']}")
        for line in ev["hook"]:
            if any(k in line for k in ("replica_cells", "repl_error", "candidates", "after", "before")):
                print(f"               {line}")


if __name__ == "__main__":
    main()

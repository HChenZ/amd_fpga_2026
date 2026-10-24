#!/usr/bin/env python3
"""Compare post-route high-fanout reports across variants.

Shows, for the nets that dominate the reference run, how replication split them:
the same driver/alias keeps fewer pins per net copy, and the net count grows.

    python build/backend_opt_20261021/fanout_compare.py ctl rep256 fp3

Reads build/reports/backend_opt_20261021/<variant>/route_high_fanout.rpt
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
REP = ROOT / "build/reports/backend_opt_20261021"

ROW = re.compile(r"^\|\s*(\S+)\s*\|\s*(\d+)\s*\|\s*(\w+)\s*\|\s*(-?[\d.]+)\s*\|\s*(-?[\d.]+)\s*\|")


def load(v):
    f = REP / v / "route_high_fanout.rpt"
    if not f.exists():
        return None
    out = []
    for line in f.read_text(encoding="utf-8", errors="replace").splitlines():
        m = ROW.match(line)
        if m:
            net, fan, drv, slack, delay = m.groups()
            out.append((net, int(fan), drv, float(slack), float(delay)))
    return out


def family(net):
    """net name minus the replicated-copy suffix, so copies group together."""
    n = re.sub(r"_rep(_\d+)?(_\d+)?$", "", net)
    n = re.sub(r"__\d+$", "", n)
    return n


def main():
    variants = sys.argv[1:] or ["ctl"]
    data = {}
    for v in variants:
        rows = load(v)
        if rows is None:
            print(f"!! no route_high_fanout.rpt for {v}")
            continue
        data[v] = rows
    if not data:
        return
    base = data.get("ctl") or next(iter(data.values()))
    fams = {}
    for net, fan, drv, slack, delay in base:
        fams.setdefault(family(net), []).append(fan)
    keep = sorted(fams.items(), key=lambda kv: -max(kv[1]))[:12]

    for fam, fans in keep:
        print(f"\n{fam}   (ctl: {len(fans)} net(s), max fanout {max(fans)})")
        for v, rows in data.items():
            copies = [r for r in rows if family(r[0]) == fam]
            if not copies:
                print(f"   {v:10s} -> below 256 pins after optimization (replicated/folded)")
                continue
            tot = sum(c[1] for c in copies)
            mx = max(c[1] for c in copies)
            print(f"   {v:10s} nets={len(copies):3d} max_fan={mx:5d} total_pins={tot:6d} "
                  f"worst_net_delay={max(c[4] for c in copies):5.3f} ns")


if __name__ == "__main__":
    main()

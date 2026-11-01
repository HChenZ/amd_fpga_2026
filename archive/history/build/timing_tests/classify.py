#!/usr/bin/env python3
"""Family-level comparison of near-critical paths (slack < 2.0 ns) between two
routed netlists dumped by probe_classes.tcl.

Family key = (startpoint register, endpoint module) — the same identity matching
used for the 2026-10-21 campaign page (not worst1/worst2 rank order, which is not
comparable across netlists).

  python build/local/tests_20261024/classify.py <control.csv> <variant.csv> [out.md]
"""
import csv
import re
import sys
from collections import defaultdict


def load(path):
    rows = []
    with open(path, newline="") as fh:
        for rec in csv.DictReader(fh):
            try:
                slack = float(rec["slack"])
            except (TypeError, ValueError):
                continue
            rows.append((slack, rec["start_pin"], rec["end_pin"]))
    return rows


def module_of(pin):
    """Instance path minus the last element (the pin/reg name)."""
    path = pin.split("/")[0:-1]
    return "/".join(path)


def cell_of(pin):
    """Last instance/reg element before the pin, plus the pin clock suffix stripped."""
    parts = pin.split("/")
    if len(parts) < 2:
        return pin
    p = parts[-1]
    p = re.sub(r"_reg(\[\d+\])?(_i_\d+)?(/[A-Z0-9]+)?$", r"_reg\1", p)
    return p


def family_key(start, end):
    """(startpoint register, endpoint module) — matches the campaign page identity."""
    sp = "/".join(start.split("/")[:-1])
    sp = re.sub(r"_reg(\[\d+\])?(_i_\d+)*$", "_reg", sp)
    ep_mod = module_of(end)
    return (sp, ep_mod)


def summarize(rows):
    fam = defaultdict(list)
    for slack, s, e in rows:
        fam[family_key(s, e)].append(slack)
    return fam


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    ctl = summarize(load(sys.argv[1]))
    var = summarize(load(sys.argv[2]))
    keys = set(ctl) | set(var)
    lines = []
    lines.append("| family (start reg → endpoint module) | ctl paths | ctl worst | var paths | var worst | Δ paths | Δ worst |")
    lines.append("|---|---|---|---|---|---|---|")
    recs = []
    for k in keys:
        c, v = ctl.get(k, []), var.get(k, [])
        cw = min(c) if c else None
        vw = min(v) if v else None
        recs.append((k, len(c), cw, len(v), vw))
    recs.sort(key=lambda r: (0 if r[2] is None else 1, 0 if r[4] is None else 1,
                             (r[4] if r[4] is not None else -9) - (r[2] if r[2] is not None else -9)))
    def fnum(x):
        return "—" if x is None else f"{x:+.3f}"
    for k, cn, cw, vn, vw in recs:
        if cn + vn < 8:
            continue
        d_p = vn - cn
        d_w = "—" if (cw is None or vw is None) else f"{vw - cw:+.3f}"
        lines.append(f"| `{k[0]}` → `{k[1].split('/')[-1]}` | {cn} | {fnum(cw)} | {vn} | {fnum(vw)} | {d_p:+d} | {d_w} |")
    out = "\n".join(lines)
    print(out)
    print()
    print(f"total paths<2.0ns: control={sum(len(v) for v in ctl.values())} variant={sum(len(v) for v in var.values())}")
    if len(sys.argv) > 3:
        with open(sys.argv[3], "w", encoding="utf-8") as fh:
            fh.write(out + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())

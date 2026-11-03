#!/usr/bin/env python3
"""Collect every backend_opt_20261021 variant result into one ranked table.

    python build/backend_opt_20261021/summarize.py [--md PATH] [--top 0]
"""
import argparse
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[2]
REP = ROOT / "build/reports/backend_opt_20261021"

KEYS = ("variant", "wns", "tns", "failing", "whs", "luts", "ffs", "rep_cells", "routing_errors")


def parse(path):
    txt = path.read_text(encoding="utf-8", errors="replace")
    rec = {}
    m = re.search(r"^RESULT (.*)$", txt, re.M)
    if m:
        for k, v in re.findall(r"(\w+)=(\S+)", m.group(1)):
            rec[k] = v
    m = re.search(r"^PATH (.*)$", txt, re.M)
    if m:
        for k, v in re.findall(r"(\w+)=(\S+)", m.group(1)):
            rec["p_" + k] = v
    m = re.search(r"^KNOBS (.*)$", txt, re.M)
    if m:
        for k, v in re.findall(r"(\w+)=(\S*)", m.group(1)):
            rec["k_" + k] = v
    # routing errors: prefer the report file (the .txt field is only a convenience)
    rs = path.parent / "route_status.rpt"
    if rs.exists():
        m = re.search(r"nets with routing errors[.\s]*:\s*(\d+)", rs.read_text(encoding="utf-8", errors="replace"))
        if m:
            rec["routing_errors"] = m.group(1)
    # LUT/FF: take report_utilization's Slice LUTs / Slice Registers -- the raw
    # PRIMITIVE_GROUP cell count over-counts by ~15% and is not comparable with the
    # project's 11752 LUT reference.
    ru = path.parent / "route_utilization.rpt"
    if ru.exists():
        t = ru.read_text(encoding="utf-8", errors="replace")
        m = re.search(r"\|\s*Slice LUTs\s*\|\s*(\d+)", t)
        if m:
            rec["luts"] = m.group(1)
        m = re.search(r"\|\s*Slice Registers\s*\|\s*(\d+)", t)
        if m:
            rec["ffs"] = m.group(1)
    return rec


def short(pin, n=34):
    if not pin or pin == "na":
        return "-"
    return pin if len(pin) <= n else "..." + pin[-(n - 3):]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--md", default=str(ROOT / "build/reports/backend_opt_20261021/summary.md"))
    ap.add_argument("--min-show", type=int, default=0)
    args = ap.parse_args()

    rows = []
    for d in sorted(REP.iterdir()):
        f = d / "result.txt"
        if d.is_dir() and f.exists():
            rec = parse(f)
            rec.setdefault("variant", d.name)
            rows.append(rec)
    if not rows:
        print("no results yet")
        return

    def fnum(rec, k, default=-9.9):
        try:
            return float(rec.get(k, default))
        except (TypeError, ValueError):
            return default

    rows.sort(key=lambda r: -fnum(r, "wns"))
    base = next((r for r in rows if r["variant"] in ("ctl", "ctl_et")), None)
    bwn = fnum(base, "wns") if base else None

    hdr = ("| # | variant | WNS | Δctl | TNS | fail | WHS | LUT | FF | rep | place | popt | route | fp | dens "
           "| worst path (start → end) |")
    sep = "|" + "---|" * 17
    lines = [hdr, sep]
    for i, r in enumerate(rows, 1):
        d = f"{fnum(r,'wns') - bwn:+.3f}" if bwn is not None else "-"
        lines.append(
            f"| {i} | `{r['variant']}` | {fnum(r,'wns'):+.3f} | {d} | {r.get('tns','-')} | "
            f"{r.get('failing','-')} | {fnum(r,'whs'):+.3f} | {r.get('luts','-')} | {r.get('ffs','-')} | "
            f"{r.get('rep_cells','-')} | {r.get('k_place','-')} | {r.get('k_popt','-')} | "
            f"{r.get('k_route','-')} | {r.get('k_fp','') or '-'} | {r.get('k_dens','') or '-'} | "
            f"{short(r.get('p_start'))} → {short(r.get('p_end'))} |"
        )
    out = "\n".join(lines) + "\n"
    pathlib.Path(args.md).write_text(out, encoding="utf-8")
    print(out)
    print(f"ranked {len(rows)} variants -> {args.md}")


if __name__ == "__main__":
    main()

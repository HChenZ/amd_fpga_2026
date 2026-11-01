#!/usr/bin/env python3
"""Dependency analysis of the near-critical path set -> placement evidence.

Reads build/local/backend_opt_20261021/recon/paths_lt2p0.csv
(slack,start_pin,end_pin) exported from the accepted routed reference and prints:

  1. per-module counts + worst slack, as startpoint and as endpoint
  2. module-pair weights (count, worst slack, sum of (2.0 - slack))
  3. the slack distribution of each pair, so a floorplan can separate modules that
     are only weakly coupled and keep strongly coupled ones adjacent

    python build/backend_opt_20261021/dep_analysis.py [--top 25]
"""
import argparse
import collections
import csv
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
CSV_PATH = ROOT / "build/local/backend_opt_20261021/recon/paths_lt2p0.csv"

# order matters: first match wins (most specific first)
MODULES = [
    ("ascon_mmio", "/u_ascon_mmio/"),
    ("ascon_ise", "/u_ex_stage/u_ascon_ise/"),
    ("multiplier", "/u_ex_stage/u_multiplier/"),
    ("divider", "/u_ex_stage/u_divider/"),
    ("icache", "/u_icache/"),
    ("dcache", "/u_dcache/"),
    ("if_stage", "/u_if_stage/"),
    ("if_id", "/u_if_id/"),
    ("id_ex", "/id_ex_u/"),
    ("ex_stage", "/u_ex_stage/"),
    ("csr_file", "/u_csr_file/"),
    ("ex_mem", "/u_ex_mem/"),
    ("mem_wb", "/u_mem_wb/"),
    ("predictor", "/u_predictor/"),
    ("regfile", "/u_regfile/"),
    ("bus_interconnect", "/u_bus_interconnect/"),
    ("cpu_axi_bridge", "/u_cpu_axi_bridge/"),
    ("axi_master", "/u_axi_master/"),
    ("uart_ctrl", "/u_uart_ctrl/"),
    ("gpio_ctrl", "/u_gpio_ctrl/"),
    ("clint", "/u_clint/"),
    ("cpi_cnt", "/u_cpi_cnt/"),
    ("bram_ctrl", "/u_axi_bram_ctrl_0/"),
    ("clk_wiz", "/u_clk_wiz_0/"),
]


def mod_of(pin: str) -> str:
    for name, pat in MODULES:
        if pat in pin:
            return name
    return "other"


def load():
    rows = []
    with open(CSV_PATH, newline="", encoding="utf-8", errors="replace") as fh:
        for rec in csv.DictReader(fh):
            try:
                slack = float(rec["slack"])
            except (TypeError, ValueError):
                continue
            rows.append((slack, rec["start_pin"], rec["end_pin"]))
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--top", type=int, default=25)
    args = ap.parse_args()
    rows = load()
    if not rows:
        sys.exit(f"no paths in {CSV_PATH}")
    print(f"paths={len(rows)}  worst={min(r[0] for r in rows):+.3f} ns  "
          f"clock/paths file={CSV_PATH.relative_to(ROOT)}")

    starts = collections.defaultdict(lambda: [0, 10.0])
    ends = collections.defaultdict(lambda: [0, 10.0])
    pairs = collections.defaultdict(lambda: [0, 10.0, 0.0])
    intra = collections.defaultdict(lambda: [0, 10.0])
    for slack, sp, ep in rows:
        ms, me = mod_of(sp), mod_of(ep)
        starts[ms][0] += 1
        starts[ms][1] = min(starts[ms][1], slack)
        ends[me][0] += 1
        ends[me][1] = min(ends[me][1], slack)
        if ms == me:
            intra[ms][0] += 1
            intra[ms][1] = min(intra[ms][1], slack)
        key = (ms, me)
        pairs[key][0] += 1
        pairs[key][1] = min(pairs[key][1], slack)
        pairs[key][2] += max(0.0, 2.0 - slack)

    print("\n== startpoint owner ==")
    for m, (n, w) in sorted(starts.items(), key=lambda kv: -kv[1][0])[:14]:
        print(f"  {m:18s} n={n:6d}  worst={w:+.3f}")
    print("\n== endpoint owner ==")
    for m, (n, w) in sorted(ends.items(), key=lambda kv: -kv[1][0])[:14]:
        print(f"  {m:18s} n={n:6d}  worst={w:+.3f}")
    print("\n== intra-module ==")
    for m, (n, w) in sorted(intra.items(), key=lambda kv: -kv[1][0])[:10]:
        print(f"  {m:18s} n={n:6d}  worst={w:+.3f}")

    print(f"\n== top {args.top} module pairs (count, worst slack, affinity) ==")
    for (a, b), (n, w, aff) in sorted(pairs.items(), key=lambda kv: -kv[1][2])[: args.top]:
        tag = " <-- keep adjacent" if w < 0.5 else ""
        print(f"  {a:18s} -> {b:18s} n={n:5d} worst={w:+.3f} aff={aff:8.1f}{tag}")

    # strong-coupling list used by floorplan.py: worst slack < 0.5 ns
    print("\n== pairs whose worst slack < 0.5 ns (floorplan must keep them close) ==")
    for (a, b), (n, w, aff) in sorted(pairs.items(), key=lambda kv: kv[1][1]):
        if w < 0.5:
            print(f"  {a:18s} -> {b:18s} n={n:5d} worst={w:+.3f}")

    # how much would separating cpu_core from ascon_mmio hurt?
    for a, b in [("ascon_mmio", "dcache"), ("dcache", "ascon_mmio"),
                 ("ascon_mmio", "bus_interconnect"), ("bus_interconnect", "ascon_mmio")]:
        if (a, b) in pairs:
            n, w, aff = pairs[(a, b)]
            print(f"\n  [{a} -> {b}] n={n} worst={w:+.3f}")


if __name__ == "__main__":
    main()

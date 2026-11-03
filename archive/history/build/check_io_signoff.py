#!/usr/bin/env python3
"""Gate for the board-IO timing sign-off (XC7Z020 ascon project).

Purpose: make "the IO constraints are still correct" a machine-checkable condition
instead of a human claim. Any future rebuild / edit of const_io.xdc is expected to be
re-verified by running this; a non-zero exit means the sign-off no longer holds.

Checks (each maps to a claim in docs/io_timing_signoff.md):
  C1 coverage      no_input_delay == 0 and no_output_delay == 0
  C2 timing        TNS == 0, failing endpoints == 0, WNS >= 0
  C3 DRC           0 Error in route_drc.rpt (warnings allowed)
  C4 clocks        methodology TIMING-8 (no common period) == 0
  C5 semantics     applied_constraints.xdc still contains the 5 required false_paths
  C6 no-trap       no IO set_input_delay/set_output_delay references `-clock clk`
  C7 zero-cost     io variant timing equals the no-constraint control (same snapshot)
                   -> this is what proves the constraint set does not squeeze internals

Usage:  python build/check_io_signoff.py [report_root]
Exit:   0 all checks pass; 1 any check failed or input missing.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

DEFAULT_ROOT = Path(r"C:/wenjian/game/FPGA2026/ours/amd_fpga_2026/build/reports/io_sta_20261027")


class Fail(Exception):
    pass


def read(p: Path) -> str:
    if not p.exists():
        raise Fail(f"missing report: {p}")
    return p.read_text(errors="replace")


def result(tag_dir: Path) -> dict:
    txt = read(tag_dir / "result.txt")
    m = re.search(
        r"wns=(-?[\d.]+) tns=(-?[\d.]+) failing=(\d+) total_endpoints=(\d+) whs=(-?[\d.]+)", txt
    )
    if not m:
        raise Fail(f"cannot parse result.txt in {tag_dir}")
    return dict(wns=float(m.group(1)), tns=float(m.group(2)),
                failing=int(m.group(3)), total=int(m.group(4)), whs=float(m.group(5)))


def checks(rd: Path) -> dict[str, str]:
    out = {}
    for line in read(rd / "check_timing_summary.txt").splitlines():
        m = re.match(r"([A-Za-z0-9_]+)=(\d+)", line)
        if m:
            out[m.group(1)] = m.group(2)
    return out


def main(argv: list[str]) -> int:
    root = Path(argv[1]) if len(argv) > 1 else DEFAULT_ROOT
    io_dir, noio_dir = root / "io", root / "noio"
    failures: list[str] = []
    notes: list[str] = []

    def check(name: str, ok: bool, detail: str) -> None:
        print(f"[{'PASS' if ok else 'FAIL'}] {name}: {detail}")
        if not ok:
            failures.append(f"{name}: {detail}")

    try:
        c = checks(io_dir)
        r = result(io_dir)

        # C1 coverage
        ni, no = c.get("no_input_delay"), c.get("no_output_delay")
        check("C1 coverage", ni == "0" and no == "0",
              f"no_input_delay={ni} no_output_delay={no} (require 0/0)")

        # C2 timing
        check("C2 timing", r["tns"] == 0.0 and r["failing"] == 0 and r["wns"] >= 0.0,
              f"WNS={r['wns']} TNS={r['tns']} failing={r['failing']}/{r['total']}")

        # C3 DRC errors
        drc = read(io_dir / "route_drc.rpt")
        err_rows = re.findall(r"\|\s*[A-Z]+[A-Z0-9-]*\s*\|\s*Error\s*\|", drc)
        checks_found = re.search(r"Checks found:\s*(\d+)", drc)
        check("C3 DRC", len(err_rows) == 0,
              f"Error rows={len(err_rows)} (checks found={checks_found.group(1) if checks_found else '?'})")

        # C4 no-common-period critical warning
        meth = read(io_dir / "methodology.rpt")
        t8 = re.search(r"\|\s*TIMING-8\s*\|", meth)
        check("C4 TIMING-8", t8 is None, "no TIMING-8 rule row" if t8 is None else "TIMING-8 present")

        # C5 required false_paths still applied
        ac = read(io_dir / "applied_constraints.xdc")
        need = {
            "uart_rxd (from)": r"set_false_path\s+-from\s+\[get_ports\s+uart_rxd\]",
            "uart_txd (to)": r"set_false_path\s+-to\s+\[get_ports\s+uart_txd\]",
            "led (to)": r"set_false_path\s+-to\s+\[get_ports\s+\{\{?led\[0\]\}?\s+\{?led\[1\]\}?\}\]",
            "button (from)": r"set_false_path\s+-from\s+\[get_ports\s+\{\{?button\[0\]\}?\s+\{?button\[1\]\}?\}\]",
            "reset_btn (from const.xdc)": r"set_false_path\s+-from\s+\[get_ports\s+reset_btn\]",
        }
        missing = [k for k, pat in need.items() if not re.search(pat, ac)]
        check("C5 false_path set", not missing,
              "all 5 present" if not missing else f"missing: {missing}")

        # C6 the trap must not reappear: no IO delay referenced to the board clock
        trap = [ln for ln in ac.splitlines()
                if re.match(r"\s*set_(input|output)_delay\b", ln) and re.search(r"-clock\s+clk\b", ln)]
        check("C6 no -clock clk IO delay", not trap, f"{len(trap)} such line(s)")

        # C7 zero-cost vs control
        rn = result(noio_dir)
        cn = checks(noio_dir)
        same = (r["wns"] == rn["wns"] and r["tns"] == rn["tns"]
                and r["failing"] == rn["failing"] and r["total"] == rn["total"])
        check("C7 zero-cost vs control", same,
              f"io={r['wns']}/{r['tns']}/{r['failing']} vs noio={rn['wns']}/{rn['tns']}/{rn['failing']}")
        if not same:
            notes.append("io 与对照的时序指标不同 -> 需确认是否新增了会挤压内部路径的约束")

        # informational: PUF/RO domain gaps are known and explicitly out of IO scope
        notes.append(f"PUF/RO 域未覆盖（不在本门禁范围，见文档 §10）："
                     f"no_clock={c.get('no_clock')} unconstrained_internal_endpoints={c.get('unconstrained_internal_endpoints')}")
        notes.append(f"对照组的 IO 覆盖计数应为非零且未变："
                     f"no_input_delay={cn.get('no_input_delay')} no_output_delay={cn.get('no_output_delay')}")
        if cn.get("no_input_delay") != "4" or cn.get("no_output_delay") != "3":
            notes.append("⚠ 对照组的 IO 覆盖计数不是 4/3 —— 说明板级端口集合或约束集被改过，需复核")
    except Fail as e:
        print(f"[FAIL] input: {e}")
        failures.append(str(e))

    print()
    for n in notes:
        print(f"note: {n}")
    print()
    if failures:
        print(f"RESULT: FAIL ({len(failures)} check(s))")
        for f in failures:
            print(f"  - {f}")
        return 1
    print("RESULT: PASS (7/7)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

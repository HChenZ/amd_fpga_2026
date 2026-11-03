#!/usr/bin/env python3
"""Generate an editable draw.io performance chart from a PUF3 result.json."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import datetime, timezone
from html import escape
import json
from pathlib import Path
import xml.etree.ElementTree as ET


DESIGN_WIDTH = 1600
DESIGN_HEIGHT = 900
PAGE_WIDTH = 1920
PAGE_HEIGHT = 1080
LAYOUT_SCALE = PAGE_WIDTH / DESIGN_WIDTH
FONT_FAMILY = "Microsoft YaHei"

COLORS = {
    "background": "#000000",
    "panel": "#1C2636",
    "panel_border": "#5B7396",
    "track": "#2A2D31",
    "white": "#F4F6F8",
    "muted": "#B8C0CC",
    "subtle": "#7E8794",
    "teal": "#B47B25",
    "teal_dark": "#31230E",
    "teal_border": "#7A551E",
    "amber": "#5C8A52",
    "amber_dark": "#203020",
    "amber_border": "#54754C",
    "slate": "#7D91AB",
    "slate_dark": "#242C38",
    "cyan": "#8EA7C7",
}


@dataclass
class Shape:
    kind: str
    x: float
    y: float
    w: float
    h: float
    text: str = ""
    fill: str = "none"
    stroke: str = "none"
    stroke_width: float = 0.0
    radius: float = 0.0
    font_size: float = 16.0
    font_color: str = COLORS["white"]
    bold: bool = False
    align: str = "left"
    valign: str = "middle"
    opacity: float = 1.0
    shadow: bool = False


class Canvas:
    def __init__(self) -> None:
        self.shapes: list[Shape] = []

    def rect(
        self,
        x: float,
        y: float,
        w: float,
        h: float,
        *,
        fill: str,
        stroke: str = "none",
        stroke_width: float = 0.0,
        radius: float = 0.0,
        opacity: float = 1.0,
        shadow: bool = False,
    ) -> None:
        self.shapes.append(
            Shape(
                kind="rect",
                x=x * LAYOUT_SCALE,
                y=y * LAYOUT_SCALE,
                w=w * LAYOUT_SCALE,
                h=h * LAYOUT_SCALE,
                fill=fill,
                stroke=stroke,
                stroke_width=stroke_width * LAYOUT_SCALE,
                radius=radius * LAYOUT_SCALE,
                opacity=opacity,
                shadow=shadow,
            )
        )

    def text(
        self,
        x: float,
        y: float,
        w: float,
        h: float,
        text: str,
        *,
        size: float = 16,
        color: str = COLORS["white"],
        bold: bool = False,
        align: str = "left",
        valign: str = "middle",
        opacity: float = 1.0,
    ) -> None:
        self.shapes.append(
            Shape(
                kind="text",
                x=x * LAYOUT_SCALE,
                y=y * LAYOUT_SCALE,
                w=w * LAYOUT_SCALE,
                h=h * LAYOUT_SCALE,
                text=text,
                font_size=size * LAYOUT_SCALE,
                font_color=color,
                bold=bold,
                align=align,
                valign=valign,
                opacity=opacity,
            )
        )


def load_benchmark(result_path: Path) -> tuple[dict, dict, dict]:
    result = json.loads(result_path.read_text(encoding="utf-8"))
    if result.get("status") != "PASS":
        raise ValueError(f"result.json status is {result.get('status')!r}, expected PASS")
    try:
        benchmark = result["sections"]["benchmark"]
        modes = benchmark["modes"]
        speedups = benchmark["speedup_median_vs_sw"]
    except KeyError as exc:
        raise ValueError(f"result.json lacks benchmark field: {exc}") from exc

    for mode in ("sw", "hw", "ise"):
        for operation in ("encrypt", "decrypt"):
            value = modes[mode][operation]["summary"]["median"]
            if not isinstance(value, (int, float)) or value <= 0:
                raise ValueError(f"invalid median at {mode}.{operation}: {value!r}")
    return result, benchmark, speedups


def fmt_int(value: float) -> str:
    return f"{value:,.0f}"


def add_header(canvas: Canvas, result: dict, benchmark: dict) -> None:
    canvas.rect(0, 0, DESIGN_WIDTH, DESIGN_HEIGHT, fill=COLORS["background"])
    timestamp = str(result.get("timestamp", "")).replace("T", " ")[:16]
    date_label = timestamp or "2026-10-31"
    canvas.text(64, 48, 900, 52, "Ascon-AEAD128 性能对比", size=32, bold=True)
    canvas.text(
        64,
        104,
        1020,
        26,
        f"PUF3 实板实测 · KAT #{benchmark['kat']} · 16 B Plaintext · 0 B AD · {date_label}",
        size=14,
        color=COLORS["muted"],
    )
    canvas.rect(
        1234,
        56,
        310,
        40,
        fill=COLORS["panel"],
        stroke=COLORS["panel_border"],
        stroke_width=1,
        radius=20,
    )
    canvas.text(
        1234,
        56,
        310,
        40,
        "RV32 AEAD mcycle · 100 MHz",
        size=13,
        color=COLORS["muted"],
        align="center",
    )
    canvas.rect(64, 148, 1472, 1, fill="#3B3D40")


def add_chart_panel(
    canvas: Canvas,
    x: float,
    *,
    title: str,
    operation: str,
    benchmark: dict,
    speedups: dict,
    max_cycles: float,
) -> None:
    y = 176
    panel_w = 728
    panel_h = 500
    canvas.rect(
        x,
        y,
        panel_w,
        panel_h,
        fill=COLORS["panel"],
        stroke=COLORS["panel_border"],
        stroke_width=1,
        radius=14,
    )

    canvas.text(x + 28, y + 20, 330, 42, title, size=24, bold=True)
    canvas.text(
        x + 390,
        y + 23,
        302,
        24,
        f"MMIO {speedups['hw'][operation]:.3f}×  ·  ISE {speedups['ise'][operation]:.3f}×",
        size=13,
        color=COLORS["muted"],
        align="right",
    )
    canvas.text(
        x + 28,
        y + 69,
        540,
        24,
        "中位周期 · 相对 SW 加速比",
        size=12,
        color=COLORS["subtle"],
    )
    canvas.text(
        x + 28,
        y + 101,
        520,
        22,
        f"统一线性刻度：0—{fmt_int(max_cycles)} cycles",
        size=11,
        color=COLORS["subtle"],
    )

    row_specs = (
        ("sw", "SW", "软件", COLORS["slate"]),
        ("hw", "MMIO", "硬件卸载", COLORS["teal"]),
        ("ise", "ISE", "定制指令", COLORS["amber"]),
    )
    row_y = y + 150
    track_x = x + 148
    track_w = 400
    for index, (mode, label, description, color) in enumerate(row_specs):
        current_y = row_y + index * 92
        median = benchmark["modes"][mode][operation]["summary"]["median"]
        speedup = 1.0 if mode == "sw" else speedups[mode][operation]

        if index:
            canvas.rect(x + 28, current_y - 18, panel_w - 56, 1, fill="#343941")
        canvas.text(x + 28, current_y + 4, 90, 26, label, size=16, bold=True)
        canvas.text(
            x + 28,
            current_y + 29,
            104,
            20,
            description,
            size=11,
            color=COLORS["subtle"],
        )

        canvas.rect(
            track_x,
            current_y + 13,
            track_w,
            18,
            fill=COLORS["track"],
            radius=9,
        )
        bar_w = max(24.0, track_w * median / max_cycles)
        canvas.rect(track_x, current_y + 13, bar_w, 18, fill=color, radius=9)

        canvas.text(
            x + 568,
            current_y + 1,
            132,
            24,
            f"{fmt_int(median)} cycles",
            size=14,
            bold=True,
            align="right",
        )
        canvas.text(
            x + 568,
            current_y + 26,
            132,
            20,
            f"{speedup:.3f}×",
            size=11,
            color=color,
            bold=True,
            align="right",
        )

    canvas.text(
        x + 28,
        y + 424,
        680,
        22,
        "条长表示中位周期；加速比 = SW 中位周期 ÷ 对应模式中位周期。",
        size=11,
        color=COLORS["subtle"],
    )


def source_display_path(result_path: Path) -> str:
    script_dir = Path(__file__).resolve().parent
    repo_root = script_dir.parents[1]
    try:
        return result_path.resolve().relative_to(repo_root).as_posix()
    except ValueError:
        return result_path.name


def add_footer(canvas: Canvas, result_path: Path, benchmark: dict) -> None:
    canvas.rect(64, 716, 1472, 1, fill="#3B3D40")
    canvas.text(76, 737, 320, 22, "测试条件", size=12, color=COLORS["muted"], bold=True)
    canvas.text(
        76,
        768,
        370,
        48,
        f"KAT #{benchmark['kat']} · PT 16 B · AD 0 B\n"
        f"warmup {benchmark['warmup']} · repetitions {benchmark['repetitions']}",
        size=13,
        color=COLORS["white"],
    )

    canvas.rect(482, 737, 1, 82, fill="#3B3D40")
    canvas.text(508, 737, 380, 22, "指标范围", size=12, color=COLORS["muted"], bold=True)
    canvas.text(
        508,
        768,
        390,
        48,
        "RV32 固件 AEAD mcycle\n不含 PS / Python / AXI-Lite / UART 主机路径",
        size=13,
        color=COLORS["white"],
    )

    canvas.rect(938, 737, 1, 82, fill="#3B3D40")
    canvas.text(964, 737, 420, 22, "数据源", size=12, color=COLORS["muted"], bold=True)
    display_source = source_display_path(result_path)
    canvas.text(
        964,
        768,
        548,
        48,
        f"PUF3 result.json\n{display_source}",
        size=12,
        color=COLORS["white"],
    )

    canvas.text(
        64,
        865,
        900,
        22,
        "bar length = median cycles · speedup = SW median ÷ mode median",
        size=11,
        color=COLORS["subtle"],
    )
    canvas.text(
        1180,
        865,
        360,
        22,
        "xc7z020clg400-1 · same PUF3 overlay",
        size=11,
        color=COLORS["subtle"],
        align="right",
    )


def build_canvas(result_path: Path) -> tuple[Canvas, dict, dict]:
    result, benchmark, speedups = load_benchmark(result_path)
    global_max = max(
        benchmark["modes"][mode][operation]["summary"]["median"]
        for mode in ("sw", "hw", "ise")
        for operation in ("encrypt", "decrypt")
    )
    canvas = Canvas()
    add_header(canvas, result, benchmark)
    add_chart_panel(
        canvas,
        56,
        title="加密 Encrypt",
        operation="encrypt",
        benchmark=benchmark,
        speedups=speedups,
        max_cycles=global_max,
    )
    add_chart_panel(
        canvas,
        816,
        title="解密 Decrypt",
        operation="decrypt",
        benchmark=benchmark,
        speedups=speedups,
        max_cycles=global_max,
    )
    add_footer(canvas, result_path, benchmark)
    return canvas, result, benchmark


def drawio_style(shape: Shape) -> str:
    if shape.kind == "text":
        style = (
            "text;html=1;strokeColor=none;fillColor=none;"
            f"align={shape.align};verticalAlign={shape.valign};whiteSpace=wrap;"
            f"fontFamily={FONT_FAMILY};fontSize={shape.font_size:g};"
            f"fontColor={shape.font_color};"
        )
        if shape.bold:
            style += "fontStyle=1;"
        if shape.opacity < 1:
            style += f"opacity={round(shape.opacity * 100)};"
        return style

    style = (
        "rounded=1;whiteSpace=wrap;html=1;"
        f"fillColor={shape.fill};strokeColor={shape.stroke};"
        f"strokeWidth={shape.stroke_width:g};"
    )
    if shape.radius:
        style += f"arcSize={min(50, round(shape.radius / max(1, min(shape.w, shape.h)) * 100))};"
    if shape.shadow:
        style += "shadow=1;"
    if shape.opacity < 1:
        style += f"opacity={round(shape.opacity * 100)};"
    return style


def write_drawio(canvas: Canvas, output_path: Path) -> None:
    modified = datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
    mxfile = ET.Element(
        "mxfile",
        {
            "host": "app.diagrams.net",
            "modified": modified,
            "agent": "bench_chart_generator.py",
            "version": "24.7.17",
            "type": "device",
        },
    )
    diagram = ET.SubElement(mxfile, "diagram", {"id": "ascon-performance", "name": "Performance"})
    model = ET.SubElement(
        diagram,
        "mxGraphModel",
        {
            "dx": str(PAGE_WIDTH),
            "dy": str(PAGE_HEIGHT),
            "grid": "0",
            "gridSize": "10",
            "guides": "1",
            "tooltips": "1",
            "connect": "1",
            "arrows": "1",
            "fold": "1",
            "page": "1",
            "pageScale": "1",
            "pageWidth": str(PAGE_WIDTH),
            "pageHeight": str(PAGE_HEIGHT),
            "math": "0",
            "shadow": "0",
        },
    )
    root = ET.SubElement(model, "root")
    ET.SubElement(root, "mxCell", {"id": "0"})
    ET.SubElement(root, "mxCell", {"id": "1", "parent": "0"})

    for index, shape in enumerate(canvas.shapes, start=1):
        cell = ET.SubElement(
            root,
            "mxCell",
            {
                "id": f"cell-{index}",
                "value": shape.text,
                "style": drawio_style(shape),
                "vertex": "1",
                "parent": "1",
            },
        )
        ET.SubElement(
            cell,
            "mxGeometry",
            {
                "x": f"{shape.x:g}",
                "y": f"{shape.y:g}",
                "width": f"{shape.w:g}",
                "height": f"{shape.h:g}",
                "as": "geometry",
            },
        )

    ET.indent(mxfile, space="  ")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    ET.ElementTree(mxfile).write(output_path, encoding="utf-8", xml_declaration=True)


def svg_text(shape: Shape) -> str:
    lines = shape.text.splitlines() or [""]
    line_height = shape.font_size * 1.25
    total_height = (len(lines) - 1) * line_height
    if shape.valign == "top":
        first_y = shape.y + shape.font_size
    elif shape.valign == "bottom":
        first_y = shape.y + shape.h - total_height
    else:
        first_y = shape.y + shape.h / 2 - total_height / 2 + shape.font_size * 0.34

    if shape.align == "center":
        anchor = "middle"
        x = shape.x + shape.w / 2
    elif shape.align == "right":
        anchor = "end"
        x = shape.x + shape.w
    else:
        anchor = "start"
        x = shape.x

    weight = "700" if shape.bold else "400"
    spans = "".join(
        f'<tspan x="{x:g}" dy="{0 if i == 0 else line_height:g}">{escape(line)}</tspan>'
        for i, line in enumerate(lines)
    )
    return (
        f'<text x="{x:g}" y="{first_y:g}" fill="{shape.font_color}" '
        f'font-family="{FONT_FAMILY},Noto Sans CJK SC,sans-serif" '
        f'font-size="{shape.font_size:g}" font-weight="{weight}" '
        f'text-anchor="{anchor}" opacity="{shape.opacity:g}">{spans}</text>'
    )


def write_svg(canvas: Canvas, output_path: Path) -> None:
    body: list[str] = []
    for shape in canvas.shapes:
        if shape.kind == "rect":
            filter_attr = ' filter="url(#panel-shadow)"' if shape.shadow else ""
            body.append(
                f'<rect x="{shape.x:g}" y="{shape.y:g}" width="{shape.w:g}" height="{shape.h:g}" '
                f'rx="{shape.radius:g}" fill="{shape.fill}" stroke="{shape.stroke}" '
                f'stroke-width="{shape.stroke_width:g}" opacity="{shape.opacity:g}"{filter_attr}/>'
            )
        else:
            body.append(svg_text(shape))

    svg = (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{PAGE_WIDTH}" height="{PAGE_HEIGHT}" '
        f'viewBox="0 0 {PAGE_WIDTH} {PAGE_HEIGHT}">\n'
        "  <defs>\n"
        '    <filter id="panel-shadow" x="-20%" y="-20%" width="140%" height="140%">\n'
        '      <feDropShadow dx="0" dy="5" stdDeviation="8" flood-color="#1F2937" flood-opacity="0.08"/>\n'
        "    </filter>\n"
        "  </defs>\n  "
        + "\n  ".join(body)
        + "\n</svg>\n"
    )
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(svg, encoding="utf-8")


def default_paths() -> tuple[Path, Path, Path]:
    script_dir = Path(__file__).resolve().parent
    repo_root = script_dir.parents[1]
    result = repo_root / "data/pynq_puf3/notebook_20261031_114512/result.json"
    return result, script_dir / "bench_chart.drawio", script_dir / "bench_chart_preview.svg"


def main() -> int:
    result_default, drawio_default, svg_default = default_paths()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--result", type=Path, default=result_default, help="PUF3 result.json")
    parser.add_argument("--output", type=Path, default=drawio_default, help="draw.io XML output")
    parser.add_argument("--svg", type=Path, default=svg_default, help="SVG preview output")
    args = parser.parse_args()

    result_path = args.result.resolve()
    canvas, result, benchmark = build_canvas(result_path)
    write_drawio(canvas, args.output.resolve())
    write_svg(canvas, args.svg.resolve())

    print(f"result: {result_path}")
    print(f"drawio: {args.output.resolve()}")
    print(f"preview: {args.svg.resolve()}")
    print(f"run: {result.get('timestamp')} status={result.get('status')}")
    print(
        "encrypt cycles: "
        + ", ".join(
            f"{mode}={fmt_int(benchmark['modes'][mode]['encrypt']['summary']['median'])}"
            for mode in ("sw", "hw", "ise")
        )
    )
    print(
        "decrypt cycles: "
        + ", ".join(
            f"{mode}={fmt_int(benchmark['modes'][mode]['decrypt']['summary']['median'])}"
            for mode in ("sw", "hw", "ise")
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

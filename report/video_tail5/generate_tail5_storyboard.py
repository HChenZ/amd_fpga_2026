#!/usr/bin/env python3
"""Generate the final five 1920x1080 draw.io storyboard pages."""

from __future__ import annotations

import argparse
import base64
from dataclasses import dataclass
from datetime import datetime, timezone
from html import escape
import json
from pathlib import Path
import shutil
import struct
import subprocess
import xml.etree.ElementTree as ET


PAGE_WIDTH = 1920
PAGE_HEIGHT = 1080
FONT_FAMILY = "Microsoft YaHei"

C = {
    "background": "#000000",
    "panel": "#1C2636",
    "panel_2": "#202B3D",
    "border": "#5B7396",
    "border_soft": "#3D4C60",
    "text": "#F4F6F8",
    "muted": "#B8C0CC",
    "subtle": "#7E8794",
    "blue": "#7D91AB",
    "gold": "#B47B25",
    "green": "#5C8A52",
    "red": "#D26A63",
    "white": "#FFFFFF",
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
    font_size: float = 18.0
    font_color: str = C["text"]
    bold: bool = False
    align: str = "left"
    valign: str = "middle"
    image: str | None = None


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
    ) -> None:
        self.shapes.append(
            Shape("rect", x, y, w, h, fill=fill, stroke=stroke,
                  stroke_width=stroke_width, radius=radius)
        )

    def text(
        self,
        x: float,
        y: float,
        w: float,
        h: float,
        text: str,
        *,
        size: float = 18,
        color: str = C["text"],
        bold: bool = False,
        align: str = "left",
        valign: str = "middle",
    ) -> None:
        self.shapes.append(
            Shape("text", x, y, w, h, text=text, font_size=size,
                  font_color=color, bold=bold, align=align, valign=valign)
        )

    def image(self, x: float, y: float, w: float, h: float, data_uri: str) -> None:
        self.shapes.append(Shape("image", x, y, w, h, image=data_uri))


@dataclass
class Page:
    name: str
    canvas: Canvas
    source_note: str


def png_size(path: Path) -> tuple[int, int]:
    with path.open("rb") as handle:
        header = handle.read(24)
    if header[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"not a PNG: {path}")
    return struct.unpack(">II", header[16:24])


def image_data_uri(path: Path) -> str:
    return "data:image/png;base64," + base64.b64encode(path.read_bytes()).decode("ascii")


def add_image_fit(
    canvas: Canvas,
    image_path: Path,
    x: float,
    y: float,
    w: float,
    h: float,
    *,
    cache: dict[Path, str],
) -> None:
    image_w, image_h = png_size(image_path)
    scale = min(w / image_w, h / image_h)
    draw_w = image_w * scale
    draw_h = image_h * scale
    draw_x = x + (w - draw_w) / 2
    draw_y = y + (h - draw_h) / 2
    cached = cache.get(image_path)
    if cached is None:
        cached = image_data_uri(image_path)
        cache[image_path] = cached
    canvas.image(draw_x, draw_y, draw_w, draw_h, cached)


def add_page_header(
    canvas: Canvas,
    *,
    page_no: int,
    title: str,
    subtitle: str,
    right_label: str = "PUF3 · xc7z020clg400-1",
) -> None:
    canvas.rect(0, 0, PAGE_WIDTH, PAGE_HEIGHT, fill=C["background"])
    canvas.text(64, 42, 110, 36, f"{page_no:02d}", size=18, color=C["gold"], bold=True)
    canvas.text(128, 31, 1180, 54, title, size=34, bold=True)
    canvas.text(64, 91, 1320, 28, subtitle, size=16, color=C["muted"])

    canvas.rect(1540, 40, 316, 42, fill="#202020", stroke=C["border_soft"], stroke_width=1, radius=21)
    canvas.text(1540, 40, 316, 42, right_label, size=13, color=C["muted"], align="center")
    canvas.rect(64, 128, 1792, 1, fill=C["border_soft"])


def add_panel(
    canvas: Canvas,
    x: float,
    y: float,
    w: float,
    h: float,
    *,
    title: str | None = None,
    subtitle: str | None = None,
    accent: str | None = None,
    fill: str = C["panel"],
) -> None:
    canvas.rect(x, y, w, h, fill=fill, stroke=C["border"], stroke_width=1, radius=14)
    if accent:
        canvas.rect(x + 22, y + 22, 4, 24, fill=accent, radius=2)
        title_x = x + 38
    else:
        title_x = x + 24
    if title:
        canvas.text(title_x, y + 16, w - 72, 34, title, size=19, bold=True)
    if subtitle:
        canvas.text(x + 24, y + 51, w - 48, 22, subtitle, size=12, color=C["muted"])


def add_source_note(canvas: Canvas, text: str) -> None:
    canvas.text(64, 1030, 1792, 22, text, size=10, color=C["subtle"])


def add_metric(
    canvas: Canvas,
    x: float,
    y: float,
    label: str,
    value: str,
    *,
    color: str = C["text"],
    width: float = 260,
) -> None:
    canvas.text(x, y, width, 20, label, size=12, color=C["subtle"])
    canvas.text(x, y + 22, width, 42, value, size=27, color=color, bold=True)


def build_page_1(
    assets: dict[str, Path],
    result: dict,
    cache: dict[Path, str],
) -> Page:
    canvas = Canvas()
    add_page_header(
        canvas,
        page_no=5,
        title="PUF 注册、重建与 HWKEY",
        subtitle="同一 PUF3 overlay · 同一上电会话 · 从拒绝密钥到恢复标准 KAT",
        right_label="same overlay · same power session",
    )

    add_panel(canvas, 60, 174, 1050, 802, title="实板运行输出", accent=C["gold"])
    add_image_fit(canvas, assets["puf_output"], 82, 230, 1006, 718, cache=cache)

    add_panel(canvas, 1140, 174, 720, 374, title="结果字段", accent=C["green"])
    add_image_fit(canvas, assets["puf_fields"], 1162, 235, 676, 286, cache=cache)

    add_panel(canvas, 1140, 574, 720, 402, title="状态链", accent=C["blue"])
    canvas.text(
        1170,
        620,
        660,
        76,
        "STATUS  →  ENROLL  →  RECONSTRUCT ×5\n→  HWKEY ON  →  HWKEY OFF",
        size=20,
        bold=True,
    )
    add_metric(canvas, 1170, 714, "ENROLL QUALITY", "127", color=C["gold"], width=250)
    add_metric(canvas, 1450, 714, "RECONSTRUCT", "5 / 5", color=C["green"], width=250)
    canvas.text(
        1170,
        805,
        650,
        44,
        "写入后 HWKEY ON；调用方 key 被拒绝；HWKEY OFF 后官方 KAT 恢复。",
        size=14,
        color=C["muted"],
    )
    canvas.rect(1170, 868, 650, 66, fill="#2C2715", stroke="#7A6121", stroke_width=1, radius=10)
    canvas.text(
        1190,
        875,
        610,
        52,
        "边界：quality 是本次会话指标，不是熵；跨上电、温度、BER 未测。",
        size=13,
        color="#E4C875",
        bold=True,
    )
    add_source_note(canvas, "Source: PUF  输出.png · PUF 安全字段.png · result.json sections.puf")
    return Page("05 PUF", canvas, "PUF  输出.png · PUF 安全字段.png · result.json")


def build_page_2(
    assets: dict[str, Path],
    result: dict,
    cache: dict[Path, str],
) -> Page:
    canvas = Canvas()
    add_page_header(
        canvas,
        page_no=6,
        title="错误标签：三种实现都拒绝",
        subtitle="同一容量内 KAT 集 · 每次翻转认证标签 · 不发布未认证明文",
        right_label="SW · MMIO · ISE",
    )
    modes = (
        ("SW", "软件实现", assets["tag_sw"], C["blue"]),
        ("MMIO", "硬件卸载", assets["tag_hw"], C["gold"]),
        ("ISE", "定制指令", assets["tag_ise"], C["green"]),
    )
    for index, (mode, description, image_path, color) in enumerate(modes):
        x = 60 + index * 620
        add_panel(canvas, x, 178, 560, 414, title=mode, subtitle=description, accent=color)
        add_image_fit(canvas, image_path, x + 24, 255, 512, 216, cache=cache)
        add_metric(canvas, x + 24, 494, "KAT PASS", "289 / 289", color=C["text"], width=225)
        add_metric(canvas, x + 285, 494, "BAD TAG REJECT", "289 / 289", color=color, width=250)

    add_panel(canvas, 60, 632, 1800, 334, title="安全语义", accent=C["red"])
    canvas.text(88, 690, 430, 36, "Ciphertext + 篡改 Tag", size=22, bold=True)
    canvas.text(540, 690, 120, 36, "→", size=30, color=C["muted"], align="center")
    canvas.text(690, 690, 380, 36, "认证失败", size=22, color=C["red"], bold=True)
    canvas.text(1090, 690, 120, 36, "→", size=30, color=C["muted"], align="center")
    canvas.text(1235, 690, 560, 36, "Plaintext not released", size=22, color=C["green"], bold=True)
    canvas.text(
        88,
        776,
        1660,
        32,
        "板上解密路径返回 AuthenticationError；候选明文不会交给调用方。",
        size=16,
        color=C["muted"],
    )
    canvas.text(
        88,
        832,
        1660,
        34,
        "3 modes × 289 KAT PASS + 3 modes × 289 bad-tag REJECT",
        size=24,
        bold=True,
    )
    add_source_note(canvas, "Source: 错误标签 sw.png · 错误标签 hw.png · 错误标签 ise.png · result.json sections.kat")
    return Page("06 Error tags", canvas, "three bad-tag screenshots · result.json")


def build_page_3(
    assets: dict[str, Path],
    result: dict,
    cache: dict[Path, str],
) -> Page:
    canvas = Canvas()
    add_page_header(
        canvas,
        page_no=7,
        title="FPGA 实现与验证边界",
        subtitle="Vivado 2025.2 · xc7z020clg400-1 · Performance_ExtraTimingOpt · post-route reports",
        right_label="100 MHz constrained domains",
    )

    add_panel(canvas, 60, 174, 1800, 250, title="时序摘要", accent=C["blue"])
    add_image_fit(canvas, assets["timing"], 82, 220, 1756, 184, cache=cache)

    add_panel(canvas, 60, 448, 590, 520, title="DRC 检查", accent=C["green"])
    add_image_fit(canvas, assets["drc"], 82, 500, 546, 410, cache=cache)
    canvas.text(82, 920, 300, 22, "DRC Error 0 · Critical Warning 0", size=14, color=C["green"], bold=True)
    canvas.text(82, 946, 520, 20, "数值来自 candidate/reports/gate.txt", size=10, color=C["subtle"])

    add_panel(canvas, 680, 448, 500, 252, title="RO 边界", accent=C["gold"])
    add_image_fit(canvas, assets["ro_boundary"], 702, 500, 456, 174, cache=cache)

    add_panel(canvas, 680, 724, 500, 244, title="签核边界", accent=C["red"])
    canvas.text(704, 776, 452, 28, "CPU / Ascon / bus", size=18, bold=True)
    canvas.text(704, 808, 452, 30, "WNS +0.104 ns · WHS +0.041 ns", size=16, color=C["green"])
    canvas.text(704, 860, 452, 28, "RO oscillator counter domain", size=18, bold=True)
    canvas.text(704, 892, 452, 30, "NOT SIGNED OFF", size=18, color=C["red"], bold=True)

    add_panel(canvas, 1210, 448, 650, 520, title="资源利用率", accent=C["blue"])
    canvas.text(1234, 492, 600, 24, "LUT / Flip-Flop", size=14, color=C["muted"], bold=True)
    add_image_fit(canvas, assets["lut"], 1234, 520, 602, 200, cache=cache)
    canvas.text(1234, 735, 600, 24, "Block RAM / DSP", size=14, color=C["muted"], bold=True)
    add_image_fit(canvas, assets["ram"], 1234, 763, 602, 165, cache=cache)

    add_source_note(canvas, "Source: timing_summary.rpt · DRC.png · DRC 和 RO 边界.png · utilization.rpt · gate.txt")
    return Page("07 FPGA", canvas, "timing · DRC · RO · resources")


def build_page_4(
    assets: dict[str, Path],
    result: dict,
    cache: dict[Path, str],
) -> Page:
    canvas = Canvas()
    add_page_header(
        canvas,
        page_no=8,
        title="PYNQ Skill：可复用的验证流程",
        subtitle="从工件核验到黄金比对，再把检查步骤固化成门禁",
        right_label="pynq-overlay-workflow",
    )

    add_panel(canvas, 60, 174, 1120, 552, title="SKILL.md", accent=C["blue"])
    add_image_fit(canvas, assets["skill"], 82, 228, 1076, 472, cache=cache)

    add_panel(canvas, 1210, 174, 650, 278, title="L3 实板汇总", accent=C["green"])
    add_image_fit(canvas, assets["skill_pass"], 1232, 225, 606, 202, cache=cache)

    add_panel(canvas, 1210, 478, 650, 248, title="覆盖范围", accent=C["gold"])
    canvas.text(1234, 528, 600, 28, "00_preflight      PASS", size=17, bold=True)
    canvas.text(1234, 568, 600, 28, "10_ascon_release  PASS", size=17, bold=True)
    canvas.text(1234, 608, 600, 28, "20_non_ascon_gpio PASS", size=17, bold=True)
    canvas.text(1234, 648, 600, 28, "30_non_ascon_dma  PASS", size=17, bold=True)

    add_panel(canvas, 60, 756, 1800, 214, title="五段式流程", accent=C["green"])
    labels = ("工件核验", "加载 overlay", "寄存器访问", "黄金比对", "报告收集")
    for index, label in enumerate(labels):
        x = 92 + index * 344
        canvas.rect(x, 824, 250, 62, fill=C["panel_2"], stroke=C["border"], stroke_width=1, radius=10)
        canvas.text(x, 824, 250, 62, label, size=17, bold=True, align="center")
        if index < len(labels) - 1:
            canvas.text(x + 258, 824, 78, 62, "→", size=28, color=C["muted"], align="center")
    canvas.text(
        92,
        910,
        1700,
        24,
        "L3：hardware_measured · DMA 是非 Ascon 独立样例，不属于 PUF3 内部功能。",
        size=13,
        color=C["muted"],
    )
    add_source_note(canvas, "Source: Skill.png · Skill L3 PASS.png · data/skill/l3_20261031_063709/40_summary.json")
    return Page("08 Skill", canvas, "Skill overview and L3 PASS")


def build_page_5(
    assets: dict[str, Path],
    result: dict,
    cache: dict[Path, str],
) -> Page:
    canvas = Canvas()
    add_page_header(
        canvas,
        page_no=9,
        title="收束：从算法到真实硬件",
        subtitle="标准 KAT、三模式加速、PUF 功能与可复用验证流程",
        right_label="same hardware · traceable evidence",
    )

    add_panel(canvas, 60, 174, 1080, 604, title="性能结果", accent=C["gold"])
    add_image_fit(canvas, assets["bench_chart"], 82, 226, 1036, 530, cache=cache)

    add_panel(canvas, 1164, 174, 696, 396, title="实板", accent=C["blue"])
    add_image_fit(canvas, assets["puf_output"], 1186, 226, 652, 322, cache=cache)

    add_panel(canvas, 1164, 596, 696, 182, title="关键结果", accent=C["green"])
    add_metric(canvas, 1188, 634, "板端 KAT", "289 / 289", color=C["text"], width=190)
    add_metric(canvas, 1388, 634, "加密加速", "15.969×", color=C["gold"], width=200)
    add_metric(canvas, 1588, 634, "PUF 重建", "5 / 5", color=C["green"], width=180)

    add_panel(canvas, 60, 810, 1800, 160, title="验证边界", accent=C["red"])
    canvas.text(
        92,
        858,
        1690,
        42,
        "当前 PUF 为同次上电功能结果；跨上电、BER、温度、熵、唯一性及 RO 计数器域时序仍待验证。",
        size=18,
        color="#E4C875",
        bold=True,
    )
    canvas.text(
        92,
        912,
        1690,
        28,
        "所有性能数字仅表示 RV32 固件 AEAD mcycle，不包含 PS、Python、AXI-Lite/UART 主机路径。",
        size=13,
        color=C["muted"],
    )
    add_source_note(canvas, "Source: bench_chart.png · PUF  输出.png · result.json")
    return Page("09 Closing", canvas, "benchmark · PUF output · limits")


def run_command(command: list[str]) -> None:
    result = subprocess.run(command, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(
            "command failed (%d): %s\n%s\n%s"
            % (result.returncode, " ".join(command), result.stdout, result.stderr)
        )


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
        return style
    if shape.kind == "image":
        return (
            "shape=image;html=1;imageAspect=0;"
            f"image={shape.image};strokeColor=none;fillColor=none;"
        )
    style = (
        "rounded=1;whiteSpace=wrap;html=1;"
        f"fillColor={shape.fill};strokeColor={shape.stroke};"
        f"strokeWidth={shape.stroke_width:g};"
    )
    if shape.radius:
        style += f"arcSize={min(50, round(shape.radius / max(1, min(shape.w, shape.h)) * 100))};"
    return style


def write_drawio(pages: list[Page], output_path: Path) -> None:
    modified = datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
    mxfile = ET.Element(
        "mxfile",
        {
            "host": "app.diagrams.net",
            "modified": modified,
            "agent": "generate_tail5_storyboard.py",
            "version": "24.7.17",
            "type": "device",
            "pages": str(len(pages)),
        },
    )
    for page_index, page in enumerate(pages, start=1):
        diagram = ET.SubElement(
            mxfile,
            "diagram",
            {"id": f"tail5-page-{page_index}", "name": page.name},
        )
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
                "background": C["background"],
                "math": "0",
                "shadow": "0",
            },
        )
        root = ET.SubElement(model, "root")
        ET.SubElement(root, "mxCell", {"id": "0"})
        ET.SubElement(root, "mxCell", {"id": "1", "parent": "0"})
        for shape_index, shape in enumerate(page.canvas.shapes, start=1):
            cell = ET.SubElement(
                root,
                "mxCell",
                {
                    "id": f"p{page_index}-cell-{shape_index}",
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
    output_path.write_bytes(
        ET.tostring(mxfile, encoding="utf-8", xml_declaration=True)
    )


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
        f'text-anchor="{anchor}">{spans}</text>'
    )


def write_svg(canvas: Canvas, output_path: Path) -> None:
    body: list[str] = []
    for shape in canvas.shapes:
        if shape.kind == "rect":
            body.append(
                f'<rect x="{shape.x:g}" y="{shape.y:g}" width="{shape.w:g}" height="{shape.h:g}" '
                f'rx="{shape.radius:g}" fill="{shape.fill}" stroke="{shape.stroke}" '
                f'stroke-width="{shape.stroke_width:g}"/>'
            )
        elif shape.kind == "image":
            body.append(
                f'<image x="{shape.x:g}" y="{shape.y:g}" width="{shape.w:g}" height="{shape.h:g}" '
                f'href="{shape.image}" preserveAspectRatio="none"/>'
            )
        else:
            body.append(svg_text(shape))
    output = (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{PAGE_WIDTH}" height="{PAGE_HEIGHT}" '
        f'viewBox="0 0 {PAGE_WIDTH} {PAGE_HEIGHT}">\n  '
        + "\n  ".join(body)
        + "\n</svg>\n"
    )
    output_path.write_text(output, encoding="utf-8")


def render_previews(page_svgs: list[Path], output_dir: Path) -> list[Path]:
    rsvg = shutil.which("rsvg-convert")
    if not rsvg:
        return []
    rendered: list[Path] = []
    for index, svg in enumerate(page_svgs, start=1):
        png = output_dir / f"tail5_page_{index}.png"
        run_command([rsvg, "-w", str(PAGE_WIDTH), "-h", str(PAGE_HEIGHT), "-o", str(png), str(svg)])
        rendered.append(png)
    return rendered


def render_contact_sheet(page_pngs: list[Path], output_path: Path) -> Path | None:
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg or len(page_pngs) != 5:
        return None
    command = [ffmpeg, "-hide_banner", "-loglevel", "error", "-y"]
    for png in page_pngs:
        command.extend(["-i", str(png)])
    command.extend([
        "-filter_complex",
        (
            "[0:v]scale=960:540[v0];"
            "[1:v]scale=960:540[v1];"
            "[2:v]scale=960:540[v2];"
            "[3:v]scale=960:540[v3];"
            "[4:v]scale=960:540[v4];"
            "[v0][v1][v2][v3][v4]"
            "xstack=inputs=5:layout=0_0|960_0|0_540|960_540|0_1080:fill=black[out]"
        ),
        "-map", "[out]", "-frames:v", "1", str(output_path),
    ])
    run_command(command)
    return output_path


def main() -> int:
    script_dir = Path(__file__).resolve().parent
    repo_root = script_dir.parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--asset-dir",
        type=Path,
        default=Path(r"C:\Nebula\HChenZ\2026 FPGA 创新设计赛道\视频素材"),
        help="directory containing the supplied video-evidence screenshots",
    )
    parser.add_argument(
        "--result",
        type=Path,
        default=repo_root / "data/pynq_puf3/notebook_20261031_114512/result.json",
        help="PUF3 result.json used to validate the storyboard data",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=script_dir / "tail5_storyboard.drawio",
        help="combined five-page draw.io output",
    )
    args = parser.parse_args()

    asset_dir = args.asset_dir.resolve()
    result_path = args.result.resolve()
    output_path = args.output.resolve()
    output_dir = output_path.parent
    output_dir.mkdir(parents=True, exist_ok=True)

    result = json.loads(result_path.read_text(encoding="utf-8"))
    if result.get("status") != "PASS":
        raise ValueError("result.json must have status=PASS")

    names = {
        "puf_output": "PUF  输出.png",
        "puf_fields": "PUF 安全字段.png",
        "tag_sw": "错误标签 sw.png",
        "tag_hw": "错误标签 hw.png",
        "tag_ise": "错误标签 ise.png",
        "timing": "时序摘要.png",
        "drc": "DRC.png",
        "ro_boundary": "DRC 和 RO 边界.png",
        "lut": "资源利用率 LUT FF.png",
        "ram": "资源利用率 RAM DSP.png",
        "skill": "Skill.png",
        "skill_pass": "Skill L3 PASS.png",
        "bench_chart": "bench_chart.png",
    }
    assets = {key: asset_dir / name for key, name in names.items()}
    missing = [str(path) for path in assets.values() if not path.is_file()]
    if missing:
        raise FileNotFoundError("missing assets:\n" + "\n".join(missing))

    cache: dict[Path, str] = {}
    pages = [
        build_page_1(assets, result, cache),
        build_page_2(assets, result, cache),
        build_page_3(assets, result, cache),
        build_page_4(assets, result, cache),
        build_page_5(assets, result, cache),
    ]

    write_drawio(pages, output_path)
    page_svgs = []
    for index, page in enumerate(pages, start=1):
        svg_path = output_dir / f"tail5_page_{index}.svg"
        write_svg(page.canvas, svg_path)
        page_svgs.append(svg_path)
    rendered = render_previews(page_svgs, output_dir)
    contact = render_contact_sheet(rendered, output_dir / "tail5_contact_sheet.png") if rendered else None

    print(f"drawio: {output_path}")
    print(f"pages: {len(pages)} at {PAGE_WIDTH}x{PAGE_HEIGHT}")
    print(f"embedded images: {len(cache)}")
    print(f"preview PNGs: {len(rendered)}")
    print(f"contact sheet: {contact}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

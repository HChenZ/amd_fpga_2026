#!/usr/bin/env python
"""把 src/*.md 拼成 report.md，再用 pandoc 渲染成 index.html（离线 KaTeX）。

用法：
    python build_site.py

依赖：pandoc（本机 /c/Users/HXZ/anaconda3/Library/bin/pandoc）。
设计说明：src 与模板补充稿为维护源，report.md 是生成物；
本脚本只做“拼接 + 渲染 + 目录/字数统计”，不在正文里写任何站点头。
"""

from __future__ import annotations

import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
_TPL = ROOT / "src_template"
SRC = _TPL if _TPL.is_dir() and list(_TPL.glob("*.md")) else ROOT / "src"   # 模板重排后的正文源
REPORT = ROOT / "report.md"
OUT = ROOT / "index.html"

PANDOC_CANDIDATES = [
    shutil.which("pandoc"),
    r"C:/Users/HXZ/anaconda3/Library/bin/pandoc",
]


def find_pandoc() -> str:
    for c in PANDOC_CANDIDATES:
        if c and Path(c).exists():
            return str(c)
    sys.exit("找不到 pandoc，请先确认安装路径")


def assemble() -> str:
    parts = sorted(SRC.glob("*.md"))
    if not parts:
        sys.exit("src/ 下没有 .md")
    chunks = []
    for p in parts:
        text = p.read_text(encoding="utf-8").strip()
        chunks.append(text)
    md = "\n\n".join(chunks) + "\n"
    # 中文正文里统一去掉行尾空白，避免 pandoc 产生硬换行
    md = re.sub(r"[ \t]+$", "", md, flags=re.M)
    REPORT.write_text(md, encoding="utf-8")
    return md


def build(md: str) -> None:
    pandoc = find_pandoc()
    frag = subprocess.run(
        [
            pandoc,
            "-f", "markdown-smart+east_asian_line_breaks+pipe_tables+tex_math_dollars",
            "-t", "html5",
            "--mathjax",
            str(REPORT),
        ],
        capture_output=True,
        text=True,
        encoding="utf-8",
    )
    if frag.returncode != 0:
        sys.exit("pandoc 失败：\n" + frag.stderr)
    title = "基于 RISC-V 与 Ascon 轻量密码加速的 FPGA SoC 技术报告"
    body = re.sub(r"<colgroup>.*?</colgroup>", "", frag.stdout, flags=re.S)
    page = (ROOT / "template.html").read_text(encoding="utf-8")
    page = page.replace("<!--TITLE-->", title).replace("<!--BODY-->", body)
    OUT.write_text(page, encoding="utf-8")


def stats(md: str) -> None:
    han = len(re.findall(r"[\u4e00-\u9fff]", md))
    chars = len(re.sub(r"\s", "", md))
    print(f"汉字 {han}，非空白字符 {chars}，行 {md.count(chr(10))}")


if __name__ == "__main__":
    text = assemble()
    build(text)
    stats(text)
    print(f"OK -> {OUT}")

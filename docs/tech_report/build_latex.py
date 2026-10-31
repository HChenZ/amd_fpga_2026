#!/usr/bin/env python
"""把 src/*.md（已核对的正文）转换成 LaTeX 工程，内容零改写。

用法：
    python build_latex.py

产出（docs/tech_report/latex/）：
    main.tex            主文件（ctexbook）
    preamble.tex        导言区
    chapters/chXX.tex   各章正文（由 pandoc 生成）
    README.md           编译说明（Overleaf 与本地）
    build.sh / build.ps1 一键编译

设计原则：
1. 正文只做"格式翻译"，不改写任何句子；图表占位、证据锚点等标记转成 LaTeX 宏；
2. 表格自行转换（pandoc 的 longtable 不控制列宽，长文本会出页）；
3. 符号（→ ≥ ① 等）统一替换为 LaTeX 命令，避免缺字；
4. 第 09_review.md 属内部清单，不进入成稿。
"""

from __future__ import annotations

import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
_TPL = ROOT / "src_template"
import os

_ENV_SRC = os.environ.get("REPORT_SRC")
_ENV_OUT = os.environ.get("REPORT_OUT")
SRC = (ROOT / _ENV_SRC) if _ENV_SRC else (
    _TPL if _TPL.is_dir() and list(_TPL.glob("*.md")) else ROOT / "src")   # 正文源
OUT = (ROOT / _ENV_OUT) if _ENV_OUT else ROOT / "latex"
CH = OUT / "chapters"
SKIP_FILES = {"09_review.md"}
PANDOC = [
    shutil.which("pandoc"),
    r"C:/Users/HXZ/anaconda3/Library/bin/pandoc",
]

# ---------------------------------------------------------------- 符号与转义

SYM = {
    "→": r"$\rightarrow$",
    "←": r"$\leftarrow$",
    "↔": r"$\leftrightarrow$",
    "≥": r"$\geq$",
    "≤": r"$\leq$",
    "≠": r"$\neq$",
    "≈": r"$\approx$",
    "±": r"$\pm$",
    "×": r"$\times$",
    "÷": r"$\div$",
    "−": r"$-$",
    "·": r"$\cdot$",
    "…": r"$\ldots$",
    "§": "§",
    "①": "(1)", "②": "(2)", "③": "(3)", "④": "(4)", "⑤": "(5)",
    "⑥": "(6)", "⑦": "(7)", "⑧": "(8)", "⑨": "(9)", "⑩": "(10)",
    "—": "---",
    "–": "--",
    "µ": r"$\mu$",
    "°": r"$^{\circ}$",
    "✅": "已完成",
    "✍️": "待写",
    "✍": "待写",
    "✓": "通过",
    "✗": "不通过",
    "➖": "不适用",
    "📷": "待素材",
    "🚧": "进行中",
    "⬜": "未做",
    "\ufe0f": "",
    "\u200b": "",
}

ESC = {
    "\\": r"$\backslash$",
    "&": r"\&",
    "%": r"\%",
    "#": r"\#",
    "_": r"\_",
    "{": r"\{",
    "}": r"\}",
    "~": r"$\sim$",
    "^": r"$\wedge$",
    "$": r"\$",
}


def tex_escape(s: str) -> str:
    return "".join(ESC.get(c, SYM.get(c, c)) for c in s)


def find_pandoc() -> str:
    for c in PANDOC:
        if c and Path(c).exists():
            return str(c)
    sys.exit("找不到 pandoc")


# ---------------------------------------------------------------- 块级解析

def split_chapters(text: str):
    """按 '## ' 切章；返回 [(title, unnumbered, body_md), ...]"""
    lines = text.split("\n")
    chapters, cur_title, cur_body = [], None, []
    for ln in lines:
        if ln.startswith("## "):
            if cur_title is not None:
                chapters.append((cur_title, cur_body))
            cur_title = ln[3:].strip()
            cur_body = []
        elif cur_title is None:
            continue  # 丢弃 H1 标题与封面引用块
        else:
            cur_body.append(ln)
    if cur_title is not None:
        chapters.append((cur_title, cur_body))
    return chapters


def norm_title(raw: str):
    """返回 (标题, 是否不编号, 是否附录)；附录由 \\appendix 自动编号，故不再设 unnumbered。"""
    unnumbered = "{.unnumbered}" in raw
    t = raw.replace("{.unnumbered}", "").strip()
    m = re.match(r"^(\d+(?:\.\d+)*)\s+(.*)$", t)
    if m:
        return m.group(2).strip(), unnumbered, False
    m = re.match(r"^附录\s*([A-D])\s+(.*)$", t)
    if m:
        return m.group(2).strip(), False, True
    return t, unnumbered, False


def demote_headings(body: list[str]) -> list[str]:
    """### 1.1 标题 → ## 标题；#### → ### 标题"""
    out = []
    for ln in body:
        if ln.startswith("### "):
            t = ln[4:].strip().replace("{.unnumbered}", "")
            t = re.sub(r"^(\d+(?:\.\d+)*)\s+", "", t)
            t = re.sub(r"^([A-D]\.\d+)\s+", "", t)
            out.append("## " + t)
        elif ln.startswith("#### "):
            t = ln[5:].strip().replace("{.unnumbered}", "")
            t = re.sub(r"^(\d+(?:\.\d+)*)\s+", "", t)
            out.append("### " + t)
        else:
            out.append(ln)
    return out


SPAN_RE = re.compile(r'<span class="(\w+)">(.*?)</span>', re.S)
SPAN_MACRO = {"evid": "evid", "todo": "todoflag", "blocked": "blockedflag", "figslot": "figref"}


BREAK_TOKENS = ("\\_", "/", ".", "-")


def add_breaks(txt: str) -> str:
    for tok in BREAK_TOKENS:
        txt = txt.replace(tok, tok + r"\allowbreak{}")
    return txt


def spans_to_raw(md: str) -> str:
    def rep(m):
        cls, inner = m.group(1), re.sub(r"\s+", " ", m.group(2)).strip()
        macro = SPAN_MACRO.get(cls, "evid")
        return "`\\%s{%s}`{=latex}" % (macro, add_breaks(tex_escape(inner)))
    return SPAN_RE.sub(rep, md)


SYMBOL_SAFE = re.compile(r"\$[^$]*\$|`[^`]*`")


def normalize_symbols(md: str) -> str:
    """把正文中的特殊符号替换为 LaTeX 命令（raw inline）。

    数学公式（$…$、$$…$$）与行内代码先整体屏蔽，替换后再原样还原；
    围栏代码块内部与标题行同样跳过。
    """
    stash: list[str] = []

    def mask(m):
        stash.append(m.group(0))
        return "\x00M%d\x00" % (len(stash) - 1)

    tmp = re.sub(r"\$\$.*?\$\$", mask, md, flags=re.S)
    tmp = re.sub(r"(?<!\\)\$[^$\n]+\$", mask, tmp)
    tmp = re.sub(r"`[^`\n]+`(?:\{=[A-Za-z]+\})?", mask, tmp)   # 行内代码与 raw inline（含 {=latex} 属性）

    lines, in_fence = [], False
    for ln in tmp.split("\n"):
        if ln.lstrip().startswith("```"):
            in_fence = not in_fence
            lines.append(ln)
            continue
        if in_fence or ln.lstrip().startswith("#"):
            lines.append(ln)
            continue
        lines.append(_normalize_line(ln))
    out = "\n".join(lines)

    # 逆序还原：后屏蔽的片段可能包含先屏蔽片段的占位符（如“……X……”生成的相邻 $\ldots$），
    # 顺序还原会把内层占位符留下并在后面被清掉，导致整段文字丢失。
    for i in reversed(range(len(stash))):
        out = out.replace("\x00M%d\x00" % i, stash[i])
    return out


def _normalize_line(md: str) -> str:
    out = []
    for c in md:
        if c in SYM:
            out.append("`%s`{=latex}" % SYM[c])
        elif c in ESC and c != "\\":
            out.append("`%s`{=latex}" % ESC[c])
        else:
            out.append(c)
    return "".join(out)


def code_blocks_to_raw(md: str) -> str:
    """```lang … ``` → 原始 LaTeX codeblock 环境"""
    pat = re.compile(r"^```(?!\{=)[^\n]*\n(.*?)^```\s*$", re.S | re.M)

    def rep(m):
        content = m.group(1).rstrip("\n")
        # 短代码块整体不分页（长块仍允许跨页，否则会留下大片空白）
        opt = "[samepage=true]" if content.count("\n") + 1 <= SHORT_CODE_LINES else ""
        return ("```{=latex}\n"
                "\\begin{codeblock}" + opt + "\n" + content + "\n"
                "\\end{codeblock}\n```")
    return pat.sub(rep, md)


# data-src 为图件原编号（文件名），显示编号由 build_template_src 按出现顺序重排
FIG_RE = re.compile(r'^> <span class="figslot"(?: data-src="([0-9A-Z]+-[0-9]+)")?>(图 [0-9A-Z]+-[0-9]+)</span>\s*(.*)$', re.M)

LINE_PT = 17.0          # 正文行距约 17 pt（11pt 字号）
CODE_LINE_PT = 10.5     # \scriptsize 代码行
SHORT_CODE_LINES = 15   # 不超过此行数的代码块整体不分页（更长的原始日志摘录允许跨页，避免大片空白）


def _needspace(pt: float) -> list[str]:
    return ["```{=latex}", r"\Needspace{%.0fpt}" % pt, "```", ""]


def _code_lines(lines: list[str], j: int) -> int | None:
    """lines[j] 为 ```{=latex} 起始行且其后是 codeblock 时返回代码行数。"""
    if j + 1 < len(lines) and lines[j + 1].startswith(r"\begin{codeblock}"):
        k = j + 2
        while k < len(lines) and not lines[k].startswith(r"\end{codeblock}"):
            k += 1
        return k - (j + 2)
    return None


def keep_together(md: str) -> str:
    """避免标题、引导句与紧随的公式/短代码块被分页拆开：在其前插入 \\Needspace。

    - 每个标题至少带 5 行正文进入同一页（防止标题落在页底）；
    - 标题后 ≤300 字即接短代码块：标题、文字与整段代码同页；
    - 段落后紧跟 $$ 公式：段落与公式同页。
    图的位置由 \\figpdf 按剩余版面自动决定（见 PREAMBLE），这里不处理。
    """
    lines = md.split("\n")
    fence = [False] * len(lines)
    inside = False
    for i, ln in enumerate(lines):
        if ln.lstrip().startswith("```"):
            fence[i] = True
            inside = not inside
        else:
            fence[i] = inside
    insert: dict[int, float] = {}
    math_end = -1
    for i, ln in enumerate(lines):
        if fence[i] or i <= math_end:
            continue
        if re.match(r"^#{1,6} ", ln):
            need = 5 * LINE_PT
            chars, j = 0, i + 1
            while j < len(lines) and not re.match(r"^#{1,6} ", lines[j]):
                if fence[j]:
                    n = _code_lines(lines, j)
                    if n is not None and n <= SHORT_CODE_LINES and chars <= 300:
                        need = max(need, 2 * LINE_PT + chars / 40 * LINE_PT + n * CODE_LINE_PT + 20)
                    break
                if FIG_RE.match(lines[j]) or lines[j].strip().startswith("$$"):
                    break
                chars += len(lines[j].strip())
                j += 1
            insert[i] = need
        elif ln.strip() == "$$" or (ln.strip().startswith("$$") and not ln.strip().endswith("$$")):
            k = i + 1
            while k < len(lines) and not lines[k].strip().endswith("$$"):
                k += 1
            math_end = k
            p = i - 1
            while p >= 0 and not lines[p].strip():
                p -= 1
            start = p
            while start > 0 and lines[start - 1].strip() and not fence[start - 1]:
                start -= 1
            if p >= 0 and not fence[p] and not re.match(r"^#{1,6} ", lines[p]):
                para = sum(len(x) for x in lines[start:p + 1])
                insert[start] = max(insert.get(start, 0), (k - i) * 16 + para / 40 * LINE_PT + 30)
    out = []
    for i, ln in enumerate(lines):
        if i in insert:
            out += [""] + _needspace(insert[i])
        out.append(ln)
    return "\n".join(out)


def figures_to_raw(md: str) -> str:
    lines = md.split("\n")
    out, i = [], 0
    while i < len(lines):
        ln = lines[i]
        m = FIG_RE.match(ln)
        if not m:
            out.append(ln)
            i += 1
            continue
        src, label, rest = m.group(1), m.group(2), m.group(3)
        desc_lines = [rest]
        i += 1
        while i < len(lines) and lines[i].startswith(">"):
            desc_lines.append(lines[i][1:].strip())
            i += 1
        text = " ".join(x.strip() for x in desc_lines if x.strip())
        # 图注内的标记 span 直接展开为括号文字，避免在 raw LaTeX 里嵌套 raw inline
        text = SPAN_RE.sub(lambda mm: "（%s）" % mm.group(2).strip(), text)
        mb = re.match(r"\*\*(.+?)\*\*\s*[：:]\s*(.*)$", text, re.S)
        if mb:
            caption, desc = mb.group(1).strip(), mb.group(2).strip()
        elif re.fullmatch(r"\*\*(.+?)\*\*", text.strip()):   # 只有图题、无说明
            caption, desc = text.strip()[2:-2], ""
        else:
            caption, desc = "", text
        label = label.lstrip("图 ").strip()   # "图 2-1" -> "2-1"
        stem = "fig_" + (src or label).replace("-", "_").replace(".", "_")
        figfile = Path(__file__).parent / "figs" / (stem + ".tex")   # 源图与生成目录分离
        cap_t, desc_t = tex_escape(caption), tex_escape(desc)
        out.append("```{=latex}")
        pdf = Path(__file__).parent / "figs" / (stem + ".pdf")
        if pdf.exists():                     # 有预渲染矢量图就用图，不依赖 TikZ 源码是否在
            out.append("\\figpdf{%s}{%s}{%s}{%s}" % (
                tex_escape(label), stem, cap_t, desc_t))
        elif figfile.exists():
            out.append("\\figtex{%s}{%s}{%s}{%s}" % (
                tex_escape(label), stem, cap_t, desc_t))
        else:
            out.append("\\fignone{%s}{%s}{%s}" % (
                tex_escape(label), cap_t, desc_t))
        out.append("```")
    return "\n".join(out)


# ---------------------------------------------------------------- 表格

def is_table_row(ln: str) -> bool:
    s = ln.strip()
    return s.startswith("|") and s.count("|") >= 2


def split_cells(ln: str) -> list[str]:
    s = ln.strip()
    if s.startswith("|"):
        s = s[1:]
    if s.endswith("|"):
        s = s[:-1]
    return [c.strip() for c in s.split("|")]


def vis_len(s: str) -> int:
    s = SPAN_RE.sub(lambda m: m.group(2), s)
    s = re.sub(r"`([^`]*)`|\*\*([^*]*)\*\*|\$([^$]*)\$", lambda m: m.group(1) or m.group(2) or m.group(3) or "", s)
    n = 0
    for ch in s:
        n += 2 if ord(ch) > 0x2E80 else 1
    return n


def cell_to_tex(cell: str) -> str:
    def literal(value: str) -> str:
        # 非代码样式中的长路径也要能断行，避免表格文字越过页边。
        escaped = tex_escape(value)
        return re.sub(r'[A-Za-z0-9./_-]{16,}', lambda m: add_breaks(m.group(0)), escaped)

    parts, pos = [], 0
    for m in re.finditer(r"`([^`]*)`|\$([^$]*)\$|\*\*(.+?)\*\*|<span class=\"(\w+)\">(.*?)</span>", cell):
        parts.append(literal(cell[pos:m.start()]))
        if m.group(1) is not None:
            code = tex_escape(m.group(1))
            for ch in ("/", "\\_", ".", "-"):
                code = code.replace(ch, ch + r"\allowbreak{}")
            parts.append(r"\texttt{%s}" % code)
        elif m.group(2) is not None:
            parts.append("$%s$" % m.group(2))
        elif m.group(3) is not None:
            parts.append(r"\textbf{%s}" % tex_escape(m.group(3)))
        else:
            macro = SPAN_MACRO.get(m.group(4), "evid")
            inner = re.sub(r"\s+", " ", m.group(5)).strip()
            parts.append(r"\%s{%s}" % (macro, add_breaks(tex_escape(inner))))
        pos = m.end()
    parts.append(literal(cell[pos:]))
    # 下划线已被转义，按单个 TeX token 加断点。
    parts = [p.replace(r'\_', r'\_\allowbreak{}') for p in parts]
    return "".join(parts).replace(r"\textbackslash{}\textbackslash{}", r"\textbackslash{}")


TABCAP_RE = re.compile(r'^<span class="tabcap">表 ([0-9A-Z]+-[0-9]+)</span>\s*\*\*(.+?)\*\*\s*$')


def table_to_raw(rows: list[list[str]], cap: tuple[str, str] | None = None) -> str:
    header, body = rows[0], rows[2:]
    ncol = max(len(r) for r in rows)
    lens = [1] * ncol
    for r in rows:
        for j, c in enumerate(r[:ncol]):
            lens[j] = max(lens[j], min(vis_len(c), 60))
    # 开 0.7 次方：短列不至于被压成逐字竖排，长列仍分得更多宽度
    lens = [l ** 0.7 for l in lens]
    total = sum(lens)
    width = 1.0
    widths = [max(0.07, width * l / total) for l in lens]
    # 归一化到 0.96
    k = width / sum(widths)
    widths = [w * k for w in widths]
    size = r"\footnotesize" if ncol >= 6 else r"\small"
    # 所有列均有界；原 l 列的真实宽度未计入总宽，导致宽表溢出。
    spec = ''.join(r'>{\raggedright\arraybackslash}p{\dimexpr %.4f\linewidth-%d\tabcolsep\relax}' %
                   (widths[i], 2) for i in range(ncol))
    rows = []
    rows.append(" & ".join(r"\textbf{%s}" % cell_to_tex(c) for c in header) + r" \\")
    for r in body:
        cells = [cell_to_tex(c) for c in r[:ncol]]
        while len(cells) < ncol:
            cells.append("")
        rows.append(" & ".join(cells) + r" \\")
    out = ["```{=latex}", r"{%s" % size]
    if cap:
        # 编号由 build_template_src 给定（表 N-k），这里只固定显示并写入表格目录
        out.append(r"\renewcommand{\thetable}{%s}" % cap[0])
    out.append(r"\begin{longtable}{@{}%s@{}}" % spec)
    if cap:
        out.append(r"\caption{%s}\label{tab:%s}\\" % (cell_to_tex(cap[1]), cap[0]))
    out += [r"\toprule", rows[0], r"\midrule", r"\endfirsthead",
            r"\multicolumn{%d}{@{}l}{\footnotesize 续表 %s}\\" % (ncol, cap[0]) if cap else "",
            r"\toprule", rows[0], r"\midrule", r"\endhead"]
    out += rows[1:]
    out += [r"\bottomrule", r"\end{longtable}", "}"]
    out.append("```")
    return "\n".join(out)


def tables_to_raw(md: str) -> str:
    lines = md.split("\n")
    out, i = [], 0
    while i < len(lines):
        if is_table_row(lines[i]) and i + 1 < len(lines) and re.match(r"^\|[\s:\-|]+\|$", lines[i + 1].strip()):
            rows = [split_cells(lines[i])]
            i += 2
            rows.append(["-"] * len(rows[0]))  # 占位对齐行
            while i < len(lines) and is_table_row(lines[i]):
                rows.append(split_cells(lines[i]))
                i += 1
            # 取出表前的表头标记（build_template_src 生成）
            cap = None
            j = len(out) - 1
            while j >= 0 and not out[j].strip():
                j -= 1
            if j >= 0:
                cm = TABCAP_RE.match(out[j].strip())
                if cm:
                    cap = (cm.group(1), cm.group(2))
                    del out[j:]
            out.append(table_to_raw(rows, cap))
        else:
            out.append(lines[i])
            i += 1
    return "\n".join(out)


# ---------------------------------------------------------------- 章节转换

def chapter_to_tex(title: str, unnumbered: bool, body: list[str], pandoc: str,
                   is_appendix: bool = False) -> str:
    md = "\n".join(demote_headings(body)).strip()
    # 顺序要紧：先把表格/代码/图占位转成 raw LaTeX，再做符号替换与行内标记，
    # 否则 raw LaTeX 里的反斜杠与反引号会被再次转义。
    md = code_blocks_to_raw(md)
    md = tables_to_raw(md)
    md = keep_together(md)
    md = figures_to_raw(md)
    md = spans_to_raw(md)
    md = normalize_symbols(md)
    tmp = OUT / "_tmp.md"
    tmp.write_text(md + "\n", encoding="utf-8")
    r = subprocess.run([pandoc, "-f", "markdown+east_asian_line_breaks", "-t", "latex", "--wrap=none", "--shift-heading-level-by=-1", str(tmp)],
                       capture_output=True, text=True, encoding="utf-8")
    if r.returncode != 0:
        sys.exit("pandoc 失败（%s）：\n%s" % (title, r.stderr))
    body_tex = r.stdout.strip()
    if unnumbered:
        # 章节与节均不编号；仍写入目录，便于评审定位
        body_tex = re.sub(r"\\section\{([^{}]*)\}",
                          lambda m: r"\section*{%s}\addcontentsline{toc}{section}{%s}" % (m.group(1), m.group(1)),
                          body_tex)
        body_tex = re.sub(r"\\subsection\{([^{}]*)\}",
                          lambda m: r"\subsection*{%s}" % m.group(1), body_tex)
    body_tex = re.sub(r"\\?label\{ux[0-9a-fux]+\}", "", body_tex).strip()
    body_tex = re.sub(chr(0) + r"M\d+" + chr(0), "", body_tex)  # 占位符兜底清理
    body_tex = _breakable_tt(body_tex)
    m_part = re.match(r"^第([一二三四五])部分\s*(.*)$", title)
    if m_part:
        # 部分号写入 chapter 计数器，节号随之为 1.1、2.2.3…；中文间空格会被 xeCJK 吞掉，故用 \quad
        num = "一二三四五".index(m_part.group(1)) + 1
        head = r"\partchapter{%d}{第%s部分\quad %s}" % (num, m_part.group(1), tex_escape(m_part.group(2)))
    elif unnumbered:
        head = r"\chapter*{%s}" % tex_escape(title)
    else:
        head = r"\chapter{%s}" % tex_escape(title)
    if is_appendix:
        # 无节的附录（B、D）小节直接编为 B.1；有节的附录（C）为 C.2.1
        if "\\section{" in body_tex:
            head += "\n" + r"\renewcommand{\thesubsection}{\thesection.\arabic{subsection}}"
        else:
            head += "\n" + r"\renewcommand{\thesubsection}{\thechapter.\arabic{subsection}}"
    if unnumbered:
        head += "\n" + r"\addcontentsline{toc}{chapter}{%s}" % tex_escape(title)
        head += "\n" + r"\markboth{%s}{%s}" % (tex_escape(title), tex_escape(title))
    return head + "\n\n" + body_tex + "\n"


def _breakable_tt(tex: str) -> str:
    """让 \\texttt 中的长路径可在 / _ . - 之后断行，消除 overfull hbox。"""
    def rep(m):
        body = m.group(1)
        for tok in ("\\_", "/", ".", "-"):
            body = body.replace(tok, tok + r"\allowbreak{}")
        return r"\texttt{%s}" % body
    return re.sub(r"\\texttt\{([^{}]*)\}", rep, tex)


def main() -> None:
    pandoc = find_pandoc()
    OUT.mkdir(exist_ok=True)
    CH.mkdir(exist_ok=True)
    for old in CH.glob("*.tex"):      # 清掉上一轮的章节文件，避免残留
        old.unlink()
    files = sorted(p for p in SRC.glob("*.md") if p.name not in SKIP_FILES)
    text = "\n\n".join(p.read_text(encoding="utf-8") for p in files)
    text = re.sub(r"^# .*$", "", text, count=1, flags=re.M)
    text = re.sub(r"^> 全国大学生.*\n(>.*\n)*", "", text, count=1, flags=re.M)
    text = re.sub(r"^> 队伍编号.*$", "", text, count=1, flags=re.M)
    chapters = split_chapters(text)
    chapters = [(t, b) for (t, b) in chapters if "审阅须知" not in t]

    parts, idx, app = [], 0, 0
    for raw_title, body in chapters:
        title, unnum, is_app = norm_title(raw_title)
        tex = chapter_to_tex(title, unnum, body, pandoc, is_app)
        if is_app:
            app += 1
            name = "app%02d" % app
        else:
            idx += 1
            name = "ch%02d" % idx
        (CH / (name + ".tex")).write_text(tex, encoding="utf-8")
        parts.append((name, title, unnum, is_app))

    includes, in_appendix = [], False
    for name, title, unnum, is_app in parts:
        if is_app and not in_appendix:
            includes.append(r"\appendix")
            includes.append(r"\renewcommand{\thesection}{\thechapter.\arabic{section}}")   # 附录节号 C.1、C.2…
            in_appendix = True
        includes.append(r"\include{chapters/%s}" % name)

    main_tex = (r"""%% 由 docs/tech_report/build_latex.py 生成，正文来自 src/*.md（内容零改写）
% !TEX program = xelatex
% 本稿使用 ctex + fandol 字体，必须用 XeLaTeX 编译；若用 pdfLaTeX 会立即报错并给出提示。
\RequirePackage{iftex}
\ifPDFTeX\errmessage{编译器不对：请在 Overleaf 左侧齿轮 Settings -> Compiler 选择 XeLaTeX，然后重新编译}\fi
\documentclass[UTF8,a4paper,11pt,openany,oneside]{ctexbook}
\input{preamble}
\title{集成 Ascon-AEAD128 轻量密码加速的 RISC-V 处理器 SoC}
\author{队伍编号 41555 \quad 团队名称 芯尽自然亮\\[2mm]
  \small 全国大学生嵌入式芯片与系统设计竞赛 2026 · FPGA 创新设计赛道 · AMD 自主选题初级组}
\date{2026-10-29}

\begin{document}
\maketitle

\frontmatter
\renewcommand{\thechapter}{}
\renewcommand{\thetable}{\arabic{table}}
\renewcommand{\theequation}{\arabic{equation}}
\setcounter{tocdepth}{2}
\tableofcontents
\cleardoublepage
\mainmatter

""" + "\n".join(includes) + r"""

% 附录末尾：插图与表格目录
\ctexset{listfigurename={插图目录},listtablename={表格目录}}
\cleardoublepage\phantomsection\addcontentsline{toc}{chapter}{插图目录}
\listoffigures
\cleardoublepage\phantomsection\addcontentsline{toc}{chapter}{表格目录}
\listoftables

\end{document}
""")
    (OUT / "main.tex").write_text(main_tex, encoding="utf-8")

    # 只同步正文实际引用的图，避免将旧稿的未使用图打包成交付成果。
    used_figures = {
        "fig_" + m.group(1).replace("-", "_").replace(".", "_")
        for m in re.finditer(r'<span class="figslot" data-src="([0-9A-Z]+-[0-9]+)">', text)
    }
    src_figs = Path(__file__).parent / "figs"
    if src_figs.is_dir():
        dst_figs = OUT / "figs"
        dst_figs.mkdir(parents=True, exist_ok=True)
        for stale in dst_figs.glob("fig_*.*"):
            if stale.stem not in used_figures:
                stale.unlink()
        for f in sorted(src_figs.glob("*.tex")):
            if f.stem in used_figures:
                (dst_figs / f.name).write_text(f.read_text(encoding="utf-8"), encoding="utf-8")
        # 图片素材（实拍照片等）一并同步
        for f in sorted(src_figs.iterdir()):
            if f.suffix.lower() in (".jpg", ".jpeg", ".png", ".pdf") and (f.stem in used_figures or f.name == "board_photo.jpg"):
                (dst_figs / f.name).write_bytes(f.read_bytes())
        logo = src_figs / "header_logo.png"   # 页眉赛题标志，放在 main.tex 同级
        if logo.is_file():
            (OUT / logo.name).write_bytes(logo.read_bytes())
        print("已同步 %d 张 TikZ 图 + %d 个图片素材 -> %s"
              % (len(list(dst_figs.glob("*.tex"))),
                 len([x for x in dst_figs.iterdir() if x.suffix.lower() in (".jpg", ".jpeg", ".png", ".pdf")]),
                 dst_figs))
    # 只有确实要就地排版 TikZ 时才加载 tikz/pgfplots（全 PDF 打包时省掉这两个大包，Overleaf 明显更快）
    figs_dir = Path(__file__).parent / "figs"
    need_tikz = any(
        not (figs_dir / (p.stem + ".pdf")).exists()
        for p in figs_dir.glob("fig_*.tex")
        if p.stem in used_figures and r"\begin{tikzpicture}" in p.read_text(encoding="utf-8")
    )
    preamble_tex = PREAMBLE
    if not need_tikz:
        preamble_tex = re.sub(r"%<<TIKZ-START>>.*?%<<TIKZ-END>>\n", "", PREAMBLE, flags=re.S)
        print("图全部为 PDF：preamble 不加载 tikz/pgfplots")
    (OUT / "preamble.tex").write_text(preamble_tex, encoding="utf-8")
    (OUT / "latexmkrc").write_text(LATEXMKRC, encoding="utf-8")
    (OUT / "build.sh").write_text(BUILD_SH, encoding="utf-8")
    (OUT / "build.ps1").write_text(BUILD_PS1, encoding="utf-8")
    (OUT / "README.md").write_text(README, encoding="utf-8")
    tmp = OUT / "_tmp.md"
    if tmp.exists():
        tmp.unlink()
    print("生成完成：%d 个章节文件 -> %s" % (len(parts), OUT))


PREAMBLE = r"""% 导言区（由 build_latex.py 生成）
\usepackage{geometry}
\geometry{left=2.6cm,right=2.6cm,top=3.0cm,bottom=2.7cm,headheight=1.45cm,headsep=0.45cm}
\usepackage{amsmath,amssymb}
\usepackage{booktabs}
\usepackage{longtable}
\usepackage{array}
\usepackage{graphicx}
\usepackage{xcolor}
\usepackage{fvextra}
%<<TIKZ-START>>
\usepackage{tikz}
\usetikzlibrary{arrows.meta,positioning,calc,decorations.pathreplacing,shapes.geometric,fit,backgrounds}
\usepackage{pgfplots}
\pgfplotsset{compat=1.18}
%<<TIKZ-END>>
\definecolor{macblue}{HTML}{DCE7F3}
\definecolor{macgreen}{HTML}{DCF0E3}
\definecolor{macamber}{HTML}{FBF0D5}
\definecolor{macrose}{HTML}{F8DFE2}
\definecolor{maclav}{HTML}{E8E3F3}
\definecolor{macgray}{HTML}{F2F4F7}
\definecolor{macpeach}{HTML}{FCE4D2}
\definecolor{macline}{HTML}{8FA2B8}
\definecolor{baryellow}{HTML}{FBE7A8}
\definecolor{baryedge}{HTML}{C9B57E}
\definecolor{softline}{HTML}{5F6B7A}
\usepackage{caption}
\usepackage{enumitem}
\usepackage{fancyhdr}
\usepackage{needspace}
\usepackage{textcomp}
% 浮动体：不单独成页（除非图几乎占满一页），允许页顶/页底放大图
\renewcommand{\topfraction}{0.9}
\renewcommand{\bottomfraction}{0.7}
\renewcommand{\textfraction}{0.07}
\renewcommand{\floatpagefraction}{0.85}
\setcounter{topnumber}{3}
\setcounter{totalnumber}{4}
\usepackage[hidelinks,hypertexnames=false]{hyperref}

% 等宽字体：优先 DejaVu Sans Mono（覆盖框线字符），否则退回默认
\IfFontExistsTF{DejaVu Sans Mono}{\setmonofont{DejaVu Sans Mono}[Scale=0.92]}{}

\ctexset{chapter={name={},number=\arabic{chapter},format=\Large\bfseries\raggedright},section={format=\large\bfseries\raggedright}}
\sloppy
\setlength{\emergencystretch}{2em}
\definecolor{evidc}{HTML}{0B6B53}
\definecolor{todoc}{HTML}{A2521B}
\definecolor{blockc}{HTML}{9B2C2C}
\definecolor{figc}{HTML}{4B5A8A}
\definecolor{codebg}{HTML}{F7F7F4}

% 标记宏：证据锚点 / 待补 / 未验证 / 图引用
\newcommand{\evid}[1]{{\footnotesize\color{evidc}\texttt{#1}}}
\newcommand{\todoflag}[1]{{\footnotesize\color{todoc}[#1]}}
\newcommand{\blockedflag}[1]{{\footnotesize\color{blockc}[#1]}}
\newcommand{\figref}[1]{{\footnotesize\color{figc}[#1]}}

% 图占位：{编号}{标题}{说明}
\newcommand{\partchapter}[2]{%
  \chapter*{#2}%
  \setcounter{chapter}{#1}%
  \addcontentsline{toc}{chapter}{#2}%
  \markboth{#2}{}%
  \setcounter{section}{0}\setcounter{subsection}{0}%
  \setcounter{subsubsection}{0}\setcounter{table}{0}%
}
\newsavebox{\figbox}
\newcommand{\figbody}[1]{%
  \IfFileExists{figs/#1.pdf}{%
    \sbox{\figbox}{\includegraphics{figs/#1.pdf}}%
    \ifdim\wd\figbox>\linewidth
      \resizebox{\linewidth}{!}{\usebox{\figbox}}%
    \else\usebox{\figbox}\fi
  }{\input{figs/#1}}}
\newcommand{\figpdf}[4]{%
  \begin{figure}[!htb]\centering
  \sbox{\figbox}{\includegraphics{figs/#2.pdf}}%
  \ifdim\wd\figbox>\linewidth
    \resizebox{\linewidth}{!}{\usebox{\figbox}}%
  \else\usebox{\figbox}\fi\par\vspace{1mm}
  \renewcommand{\thefigure}{#1}%
  \caption{#3}\label{fig:#1}\par\vspace{0.5mm}
  \begin{minipage}{0.96\textwidth}{\footnotesize\color{black!70}#4}\end{minipage}
  \end{figure}}
\newcommand{\figtex}[4]{%
  \begin{figure}[!htb]\centering
  \figbody{#2}\par\vspace{1mm}
  \renewcommand{\thefigure}{#1}%
  \caption{#3}\label{fig:#1}\par\vspace{0.5mm}
  \begin{minipage}{0.96\textwidth}{\footnotesize\color{black!70}#4}\end{minipage}
  \end{figure}}
\newcommand{\fignone}[3]{%
  \begin{figure}[!htb]\centering
  \fbox{\parbox[c][26mm][c]{\textwidth}{\centering\color{black!45}\small 图 #1 待补：需实拍照片或工程截图}}%\par\vspace{1mm}
  \renewcommand{\thefigure}{#1}%
  \caption{#2}\label{fig:#1}\par\vspace{0.5mm}
  \begin{minipage}{0.96\textwidth}{\footnotesize\color{black!70}#3}\end{minipage}
  \end{figure}}
\newcommand{\figplaceholder}[3]{%
  \begin{figure}[!htb]\centering
    \fbox{\parbox[c][3.4cm][c]{0.88\textwidth}{\centering\color{figc}%
      \textbf{图 #1 占位}\\[1mm]\footnotesize 待绘制（TikZ / pgfplots 或实拍）}}
    \caption{#2}\label{fig:#1}
  \end{figure}
  \vspace{-2mm}
  {\footnotesize\noindent\color{black!70}#3\par}\vspace{2mm}}

% 代码块（保留原始空白与中文）
\DefineVerbatimEnvironment{codeblock}{Verbatim}%
   {fontsize=\scriptsize,breaklines=true,breakanywhere=true,frame=single,framesep=1.2mm,rulecolor=\color{black!30},%
   framerule=0.4pt, xleftmargin=2mm,xrightmargin=2mm}

% ---- 图：PDF 与 TikZ 源码互为备份，缺哪个都能编（避免"删了 tex 就报错"）----
% 图按当前页剩余版面就地排放：放得下则原位；差一点则等比缩小（不小于 58%）塞进本页；
% 都不行才作为浮动体放到下一页顶部，让后文补满本页，避免大片空白。
\newsavebox{\figdescbox}
\newlength{\figrem}\newlength{\fignat}\newlength{\figcap}\newlength{\figfit}
\newcommand{\figload}[1]{%
  \IfFileExists{figs/#1.pdf}{\sbox{\figbox}{\includegraphics{figs/#1.pdf}}}{%
    \IfFileExists{figs/#1.tex}{\sbox{\figbox}{\input{figs/#1}}}{\sbox{\figbox}{\fbox{\color{black!45}缺少图 #1}}}}%
  \ifdim\wd\figbox>\linewidth \sbox{\figbox}{\resizebox{\linewidth}{!}{\usebox{\figbox}}}\fi}
\newcommand{\figcaptionpart}[3]{%
  \par\vspace{1mm}%
  \renewcommand{\thefigure}{#1}%
  \captionof{figure}{#2}\label{fig:#1}\par\vspace{0.5mm}%
  \usebox{\figdescbox}}
\renewcommand{\figpdf}[4]{%
  \par
  \figload{#2}%
  \sbox{\figdescbox}{\begin{minipage}{0.96\textwidth}{\footnotesize\color{black!70}#4}\end{minipage}}%
  \setlength{\fignat}{\dimexpr\ht\figbox+\dp\figbox\relax}%
  \setlength{\figcap}{\dimexpr\ht\figdescbox+\dp\figdescbox+3.2\baselineskip\relax}%
  \ifdim\pagegoal=\maxdimen \setlength{\figrem}{\textheight}%
  \else \setlength{\figrem}{\dimexpr\pagegoal-\pagetotal-\baselineskip\relax}\fi
  \setlength{\figfit}{\dimexpr\figrem-\figcap\relax}%
  \typeout{FIGPLACE #1: rem=\the\figrem\space nat=\the\fignat\space cap=\the\figcap}%
  \ifdim\dimexpr\fignat+\figcap\relax<\figrem
    \fighere{#1}{#3}%
  \else\ifdim\figfit>0.58\fignat
    \sbox{\figbox}{\resizebox*{!}{\figfit}{\usebox{\figbox}}}\fighere{#1}{#3}%
  \else
    \begin{figure}[!tbp]\centering\usebox{\figbox}\figcaptionpart{#1}{#3}{}\end{figure}%
  \fi\fi}
\newcommand{\fighere}[2]{%
  \par\addvspace{\intextsep}\noindent
  \begin{minipage}{\linewidth}\centering\usebox{\figbox}\figcaptionpart{#1}{#2}{}\end{minipage}%
  \par\addvspace{\intextsep}}
\renewcommand{\figbody}[1]{%
  \IfFileExists{figs/#1.tex}{\input{figs/#1}}{%
    \IfFileExists{figs/#1.pdf}{%
      \sbox{\figbox}{\includegraphics{figs/#1.pdf}}%
      \ifdim\wd\figbox>\linewidth \resizebox{\linewidth}{!}{\usebox{\figbox}}\else\usebox{\figbox}\fi
    }{\fbox{\color{black!45}缺少图 #1}}}}

\providecommand{\tightlist}{\setlength{\itemsep}{0pt}\setlength{\parskip}{0pt}}
\captionsetup{font=small,labelsep=quad}
\renewcommand{\arraystretch}{1.15}
\setlist{itemsep=2pt,topsep=3pt}
% 页眉按《技术报告模板》：居中赛题标志 + 下划线；页脚居中页码；章首页同样处理
\newcommand{\reportheadfoot}{%
  \fancyhf{}%
  \fancyhead[C]{\IfFileExists{header_logo.png}{\includegraphics[width=6.5cm]{header_logo.png}}{}}%
  \fancyfoot[C]{\small\thepage}%
  \renewcommand{\headrulewidth}{0.4pt}}
\pagestyle{fancy}
\reportheadfoot
\fancypagestyle{plain}{\reportheadfoot}
\renewcommand{\chaptermark}[1]{\markboth{#1}{}}
\renewcommand{\sectionmark}[1]{}
\renewcommand{\thesection}{\arabic{chapter}.\arabic{section}}
\renewcommand{\thesubsection}{\thesection.\arabic{subsection}}
\renewcommand{\thesubsubsection}{\thesubsection.\arabic{subsubsection}}
\renewcommand{\headrulewidth}{0.4pt}
"""

LATEXMKRC = "$pdf_mode = 5;\n$max_repeat = 2;\n$silent = 1;\n"

BUILD_SH = """#!/usr/bin/env bash
# 本地编译（需 TeX Live / MiKTeX，含 ctex 与 xelatex）
set -e
cd "$(dirname "$0")"
xelatex -interaction=nonstopmode main.tex
xelatex -interaction=nonstopmode main.tex
xelatex -interaction=nonstopmode main.tex
echo "OK -> main.pdf"
"""

BUILD_PS1 = """# 本地编译（Windows，PowerShell）：需安装 TeX Live 或 MiKTeX
Set-Location $PSScriptRoot
xelatex -interaction=nonstopmode main.tex
xelatex -interaction=nonstopmode main.tex
xelatex -interaction=nonstopmode main.tex
if ($LASTEXITCODE -eq 0) { "OK -> main.pdf" }
"""

README = """# LaTeX 工程（由 build_latex.py 生成）

正文来自 `src/*.md` 和 `src_template/new/*.md`，重排后由 `src_template/*.md` 生成。
**不要直接改 `chapters/*.tex`**。从仓库根运行完整入口：

```bash
python -X utf8 docs/tech_report/build_report.py
```

## 编译

- **Overleaf**：新建项目，上传本目录全部文件（含 chapters/），主文件设为 `main.tex`，
  编译器选 **XeLaTeX**。中文字体使用 TeX Live 自带 fandol，无需本地字体。
- **本地**：需 XeLaTeX（TeX Live / MiKTeX，含 ctex 宏包）。

```bash
bash build.sh          # 或 PowerShell: ./build.ps1
```

## 结构

| 文件 | 说明 |
|---|---|
| `main.tex` | 主文件：封面、目录、章节 include |
| `preamble.tex` | 导言区：宏包、字体、标记宏、图占位宏、代码块环境 |
| `chapters/ch01..ch09` | 摘要、作品概要、正文第 1–9 章 |
| `chapters/app01..app04` | 附录 A（术语）、B（地址与编码）、C（证据索引）、D（参考文献） |

## 已编译验证

本工程已用 XeLaTeX（Tectonic 0.15 便携版，TeX Live 2025 包集）实际编译通过：
**62 页、0 error、0 缺字（Missing character）**，仅余少量 1–5 pt 的 overfull 提示（表格单元格边界）。
编译产物 `main.pdf` 随工程提供，可用于对照。

Overleaf 编译注意：主文件 `main.tex`、编译器选 **XeLaTeX**；中文字体走 `ctex` 自带的 fandol，
无需上传字体。若本地装了 TeX Live/MiKTeX，直接 `bash build.sh`。

## 未做的事（下一版）

1. 图仍为占位框：`\\figplaceholder` 共 14 处，待替换为 TikZ / pgfplots / 实拍；
2. 尚未按《技术报告模板》五部分重排（当前按 9 章正文，映射见"作品概要"一节）；
3. 页眉已按模板放置赛题标志（`header_logo.png`，居中，宽 6.5 cm），页码居中于页脚；图表编号格式待按模板微调。
"""

if __name__ == "__main__":
    main()

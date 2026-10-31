r"""把 TikZ 图预渲染成 PDF，供 Overleaf 上传包快速编译。

- 对 figs/*.tex 中确实是 TikZ 的图，套一个 preview 包装、用 tectonic 编成 figs/同名.pdf；
- `\figtex` 宏已改为：若存在同名 PDF 就直接 \includegraphics，否则回退到 \input TikZ 源码。
  因此本机（无 PDF）编译仍走源码，Overleaf（带 PDF）编译走图片，两边源码只有一份。
"""
from __future__ import annotations

import subprocess
import sys
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parent
FIGS = ROOT / "figs"
BUILD = ROOT / "figbuild"
TECTONIC = Path(os.environ.get('TECTONIC', r"C:/Users/HXZ/AppData/Local/hermes/cache/scratch/tectonic.exe"))

WRAP = r"""\documentclass[UTF8,11pt]{ctexart}
\usepackage[paperwidth=26cm,paperheight=26cm,margin=0pt]{geometry}
\usepackage{amsmath,amssymb,booktabs,array,longtable}
\usepackage{preview}
\usepackage{tikz}
\usetikzlibrary{arrows.meta,positioning,calc,decorations.pathreplacing,shapes.geometric,fit,backgrounds}
\usepackage{pgfplots}
\pgfplotsset{compat=1.18}
\usepackage{xcolor}
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
\PreviewEnvironment{tikzpicture}
\pagestyle{empty}
\begin{document}
\input{@FIG@}
\end{document}
"""


def _image_to_pdf(src: Path, dst: Path, width_cm: float = 12.4) -> None:
    """把位图（实拍照片）转成同比例 PDF，供 \figpdf 统一引用，避免再依赖 .tex 包装。"""
    import fitz

    pix = fitz.Pixmap(str(src))
    w_pt = width_cm * 28.3465                      # 目标版宽：12.4 cm（约 0.78\textwidth）
    h_pt = w_pt * pix.height / pix.width
    out = fitz.open()
    page = out.new_page(width=w_pt, height=h_pt)
    page.insert_image(page.rect, filename=str(src))
    out.save(dst, garbage=3, deflate=True)
    out.close()


def _placeholder_pdf(name: str, dst: Path, width_cm: float) -> None:
    """截图占位：浅灰虚线框 + 待放入的文件名，比例 16:9。"""
    import fitz

    w = width_cm * 28.3465
    h = w * 9 / 16
    out = fitz.open()
    page = out.new_page(width=w, height=h)
    r = fitz.Rect(4, 4, w - 4, h - 4)
    page.draw_rect(r, color=(0.62, 0.66, 0.72), fill=(0.96, 0.97, 0.98), width=1.2, dashes="[6 4] 0")
    # insert_htmlbox 自动处理中英文混排字体
    page.insert_htmlbox(
        fitz.Rect(20, h / 2 - 40, w - 20, h / 2 + 50),
        '<div style="text-align:center;color:#738094;font-family:sans-serif">'
        '<div style="font-size:18px">Vivado 截图待补</div>'
        '<div style="font-size:10px;margin-top:8px">放入 docs/tech_report/figs/%s<br>后重新构建即自动替换此占位框</div>'
        '</div>' % name)
    out.save(dst, garbage=3, deflate=True)
    out.close()


def _crop(src: Path, dst: Path) -> None:
    """裁到内容边界（preview 在 ctexart 下不生效，故用 PyMuPDF 重设页面）。"""
    import fitz

    doc = fitz.open(src)
    page = doc[0]
    rects = [d["rect"] for d in page.get_drawings()]
    for b in page.get_text("dict")["blocks"]:
        if b.get("bbox"):
            rects.append(fitz.Rect(b["bbox"]))
    if not rects:
        dst.write_bytes(src.read_bytes())
        return
    box = rects[0]
    for r in rects[1:]:
        box |= r
    box = fitz.Rect(box.x0 - 2, box.y0 - 2, box.x1 + 2, box.y1 + 2)
    out = fitz.open()
    newpage = out.new_page(width=box.width, height=box.height)
    newpage.show_pdf_page(newpage.rect, doc, 0, clip=box)
    out.save(dst, garbage=3, deflate=True)
    doc.close()
    out.close()


def main() -> None:
    if not TECTONIC.exists():
        sys.exit("找不到 tectonic：%s" % TECTONIC)
    BUILD.mkdir(exist_ok=True)
    for p in BUILD.glob("*"):
        if p.is_file():
            p.unlink()
    done, skipped, failed = 0, [], []
    for fig in sorted(FIGS.glob("fig_*.tex")):
        src = fig.read_text(encoding="utf-8")
        if r"\begin{tikzpicture}" not in src:
            import re as _re
            m = _re.search(r"includegraphics(?:\[[^\]]*\])?\{([^}]+)\}", src)
            if m:
                img = FIGS / Path(m.group(1)).name
                width = 15.0 if img.name.startswith("vivado_") else 12.4   # 工具截图按满版宽
                if img.exists():
                    _image_to_pdf(img, FIGS / (fig.stem + ".pdf"), width)
                    done += 1
                    print("ok  %-16s (图片转 PDF)" % (fig.stem + ".pdf"))
                    continue
                if img.name.startswith("vivado_"):
                    # 截图尚未放入：生成占位框，放入同名图片后重跑即替换
                    _placeholder_pdf(img.name, FIGS / (fig.stem + ".pdf"), width)
                    done += 1
                    print("ok  %-16s (截图占位：待放入 figs/%s)" % (fig.stem + ".pdf", img.name))
                    continue
            skipped.append(fig.name)          # 既非 TikZ、也找不到图片
            continue
        wrapper = BUILD / (fig.stem + ".tex")
        wrapper.write_text(WRAP.replace("@FIG@", str(fig).replace("\\", "/")), encoding="utf-8")
        r = subprocess.run([str(TECTONIC), "-X", "compile", wrapper.name],
                           cwd=BUILD, capture_output=True, text=True, encoding="utf-8", errors="replace")
        pdf = BUILD / (fig.stem + ".pdf")
        if r.returncode != 0 or not pdf.exists():
            print("!! 失败：%s\n%s" % (fig.name, (r.stderr or r.stdout)[-600:]))
            failed.append(fig.name)
            continue
        _crop(pdf, FIGS / pdf.name)
        done += 1
        print("ok  %-16s %6.1f KB" % (pdf.name, pdf.stat().st_size / 1024))
    print("\n完成 %d 张，跳过 %d 张（非 TikZ）：%s" % (done, len(skipped), ", ".join(skipped) or "无"))
    if failed or skipped:
        raise SystemExit('Figure build incomplete: ' + ', '.join(failed + skipped))


if __name__ == "__main__":
    main()

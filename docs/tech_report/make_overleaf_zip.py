"""打包 Overleaf 上传包：只收录编译必需的源文件与素材。

用法：python make_overleaf_zip.py
产物：latex_project.zip（根目录即 main.tex，可直接 New Project → Upload Project）
"""
from __future__ import annotations

import zipfile
from pathlib import Path

ROOT = Path(__file__).parent
import os
LATEX = ROOT / os.environ.get("LATEX_DIR", "latex")
OUT = ROOT / os.environ.get("ZIP_NAME", "latex_project.zip")

# 不上传：编译产物、单图测试稿、原始大图（figs/board_photo.jpg 才是正文用的）
SKIP_NAMES = {"figtest.tex", "实物图.jpg", "main.pdf", "report_v3.pdf",
              "report_v4.pdf", "report_v5.pdf", "report_v6.pdf", "report_v7.pdf",
              "figtest.pdf", "main_v2.pdf"}
SUFFIX = (".tex", ".md", ".sh", ".ps1", ".pdf")   # .pdf 仅限 figs/ 下的预渲染图


def main() -> None:
    n = 0
    with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED) as z:
        for p in sorted(LATEX.rglob("*")):
            if not p.is_file():
                continue
            if any(part.startswith("_") for part in p.parts):
                continue
            if p.name in SKIP_NAMES:
                continue
            # figs/ 下只带预渲染 PDF 与图 3-1 的图片包装；TikZ 源码留仓库，避免"tex/PDF 谁优先"的歧义
            if p.parent.name == "figs" and p.suffix.lower() in (".tex", ".jpg", ".png"):
                continue   # 图一律以预渲染 PDF 交付
            if p.suffix.lower() not in SUFFIX and p.name not in ("latexmkrc", "header_logo.png"):
                continue
            z.write(p, p.relative_to(LATEX))
            n += 1
    size = OUT.stat().st_size / 1024 / 1024
    with zipfile.ZipFile(OUT) as z:
        names = z.namelist()
    print("已打包 %d 个文件 -> %s（%.2f MB）" % (n, OUT.name, size))
    print("根目录：", [x for x in names if "/" not in x])
    print("图片：", [x for x in names if x.endswith((".jpg", ".png"))])
    print("章节：%d 个 .tex" % len([x for x in names if x.startswith("chapters/")]))


if __name__ == "__main__":
    main()

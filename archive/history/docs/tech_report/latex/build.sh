#!/usr/bin/env bash
# 本地编译（需 TeX Live / MiKTeX，含 ctex 与 xelatex）
set -e
cd "$(dirname "$0")"
xelatex -interaction=nonstopmode main.tex
xelatex -interaction=nonstopmode main.tex
xelatex -interaction=nonstopmode main.tex
echo "OK -> main.pdf"

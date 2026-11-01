#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p output/pdf/chapters
latexmk -xelatex -interaction=nonstopmode -halt-on-error -file-line-error -recorder -outdir=output/pdf -jobname=final_report main.tex 2>&1 | tee output/pdf/build_console.log

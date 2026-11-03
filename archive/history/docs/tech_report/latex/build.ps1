# 本地编译（Windows，PowerShell）：需安装 TeX Live 或 MiKTeX
Set-Location $PSScriptRoot
xelatex -interaction=nonstopmode main.tex
xelatex -interaction=nonstopmode main.tex
xelatex -interaction=nonstopmode main.tex
if ($LASTEXITCODE -eq 0) { "OK -> main.pdf" }

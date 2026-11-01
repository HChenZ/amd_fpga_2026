param()
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
New-Item -ItemType Directory -Force 'output/pdf/chapters' | Out-Null
& latexmk -xelatex -interaction=nonstopmode -halt-on-error -file-line-error -recorder -outdir=output/pdf -jobname=final_report main.tex 2>&1 | Tee-Object -FilePath 'output/pdf/build_console.log'
if ($LASTEXITCODE -ne 0) { throw "XeLaTeX build failed ($LASTEXITCODE); see output/pdf/build_console.log" }
Write-Output 'OK -> output/pdf/final_report.pdf'

@echo off
rem Regenerate from maintained sources, compile, package and verify.
setlocal
cd /d "%~dp0"
python -X utf8 build_report.py %*
if errorlevel 1 exit /b 1
echo Report ready: %~dp0latex\main.pdf
endlocal

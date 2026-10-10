@echo off
setlocal
cd /d "%~dp0"
if not exist ".venv\Scripts\python.exe" (
    echo Run setup.bat once first.
    exit /b 1
)
".venv\Scripts\python.exe" "scripts\check.py"
exit /b %errorlevel%

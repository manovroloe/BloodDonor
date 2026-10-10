@echo off
setlocal
cd /d "%~dp0"
if not exist ".venv\Scripts\python.exe" (
    echo Run setup.bat once before starting BloodCare.
    exit /b 1
)
".venv\Scripts\python.exe" "scripts\start.py"
exit /b %errorlevel%

@echo off
setlocal
cd /d "%~dp0"
if exist ".venv\Scripts\python.exe" (
    ".venv\Scripts\python.exe" "scripts\setup.py" %*
    exit /b
)
py -3.13 -c "import sys" >nul 2>&1
if not errorlevel 1 (
    py -3.13 "scripts\setup.py" %*
    exit /b
)
py -3.12 -c "import sys" >nul 2>&1
if not errorlevel 1 (
    py -3.12 "scripts\setup.py" %*
    exit /b
)
python "scripts\setup.py" %*
exit /b %errorlevel%

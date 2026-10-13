"""Standard-library helpers shared by setup/start; never install on startup."""
from __future__ import annotations
from importlib.metadata import version, PackageNotFoundError
from pathlib import Path
import hashlib
import json
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
VENV = ROOT / ".venv"
PYTHON = VENV / ("Scripts/python.exe" if sys.platform == "win32" else "bin/python")
STAMP = VENV / ".bloodcare-setup.json"
LOCK = ROOT / "requirements.txt"

def lock_hash() -> str:
    return hashlib.sha256(LOCK.read_bytes().replace(b"\r\n", b"\n")).hexdigest()

def expected_packages() -> dict[str, str]:
    packages = {}
    for raw in LOCK.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if ";" in line:
            line, marker = line.split(";", 1)
            if 'sys_platform == "win32"' in marker and sys.platform != "win32":
                continue
        match = re.fullmatch(r"([A-Za-z0-9_.-]+)==([^\s;]+)", line.strip())
        if not match:
            raise ValueError("The production lock contains an unsupported requirement format.")
        packages[match.group(1)] = match.group(2)
    return packages

def dependency_problems() -> list[str]:
    problems = []
    for name, expected in expected_packages().items():
        try:
            actual = version(name)
        except PackageNotFoundError:
            problems.append(f"{name} is missing")
            continue
        if actual != expected:
            problems.append(f"{name}: expected {expected}, found {actual}")
    return problems

def supported_python() -> bool:
    return sys.version_info[:2] in {(3, 12), (3, 13)}

if __name__ == "__main__":
    problems = dependency_problems()
    if problems:
        print("\n".join(problems))
        raise SystemExit(1)
    print("All locked runtime dependencies are installed.")

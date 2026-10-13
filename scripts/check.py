"""Offline validation: Python syntax, assets, API behavior and baseline preservation."""
from pathlib import Path
import ast
import shutil
import subprocess
import sys
ROOT = Path(__file__).resolve().parents[1]

def main() -> int:
    for folder in [ROOT / "server", ROOT / "scripts", ROOT / "tests"]:
        for file in folder.rglob("*.py"):
            ast.parse(file.read_text(encoding="utf-8"), filename=str(file))
    ast.parse((ROOT / "run.py").read_text(encoding="utf-8"))
    print("Python syntax: passed", flush=True)
    node = shutil.which("node")
    if node:
        for file in (ROOT / "client/js").rglob("*.js"):
            mode = "module" if file.name not in {"api.js", "ui.js"} else "commonjs"
            subprocess.run([node, "--input-type=" + mode, "--check"], input=file.read_text(encoding="utf-8"), text=True, check=True)
        print("JavaScript syntax: passed", flush=True)
    else:
        print("JavaScript syntax: skipped (Node is an optional development checker, not a website requirement).", flush=True)
    return subprocess.call([sys.executable, "-m", "unittest", "discover", "-s", "tests", "-p", "test_*.py", "-v"], cwd=ROOT)

if __name__ == "__main__":
    raise SystemExit(main())

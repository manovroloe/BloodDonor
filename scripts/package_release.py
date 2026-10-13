"""Create a clean SOURCE ZIP; never include local secrets or installed environments."""
from __future__ import annotations
import argparse
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

ROOT = Path(__file__).resolve().parents[1]
EXCLUDED_DIRS = {".venv", "venv", "__pycache__", ".git", "node_modules", ".pytest_cache", "logs", "dist", "browser-artifacts"}

def included(path: Path) -> bool:
    relative = path.relative_to(ROOT)
    if any(part in EXCLUDED_DIRS for part in relative.parts):
        return False
    if path.name == ".env.example":
        return True
    if path.name == ".env" or path.name.startswith(".env."):
        return False
    return path.suffix.lower() not in {".pyc", ".pyo", ".log", ".zip"}

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "dist/BloodCareSystem_CleanArchitecture_v23.zip")
    args = parser.parse_args()
    output = args.output.expanduser().resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    files = [p for p in sorted(ROOT.rglob("*")) if p.is_file() and not p.is_symlink() and included(p) and p.resolve() != output]
    with ZipFile(output, "w", compression=ZIP_DEFLATED, compresslevel=9) as archive:
        for path in files:
            archive.write(path, "BloodCareSystem/" + path.relative_to(ROOT).as_posix())
    with ZipFile(output) as archive:
        failure = archive.testzip()
        if failure:
            raise RuntimeError("Archive integrity check failed.")
    print(f"Created {output.name}: {len(files)} files; private .env and installed environments excluded.")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())

"""One-time developer/server setup. Existing configuration is never overwritten."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys
import venv
from environment import ROOT, VENV, PYTHON, STAMP, lock_hash, supported_python

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--refresh", action="store_true", help="Explicitly reinstall/check the pinned dependency set.")
    args = parser.parse_args()
    if not supported_python():
        print("Use Python 3.12 or 3.13 for this release. Website visitors do not need Python.", file=sys.stderr)
        return 1
    if not PYTHON.is_file():
        if VENV.exists() and any(VENV.iterdir()):
            print("The .venv folder is incomplete or belongs to another OS. Remove only .venv and run setup again.", file=sys.stderr)
            return 1
        print("Creating this computer's isolated Python environment...")
        venv.EnvBuilder(with_pip=True).create(VENV)
    fingerprint = lock_hash()
    try:
        previous = json.loads(STAMP.read_text())
    except (OSError, ValueError):
        previous = {}
    check = subprocess.run([str(PYTHON), str(ROOT / "scripts/environment.py")], cwd=ROOT, capture_output=True, text=True)
    unchanged = previous.get("requirements_sha256") == fingerprint and check.returncode == 0
    if unchanged and not args.refresh:
        print("Setup is already complete. No packages were downloaded or installed.")
    else:
        print("Installing the pinned dependencies for this release...")
        subprocess.run([str(PYTHON), "-m", "pip", "install", "--disable-pip-version-check", "--no-input", "--no-deps", "-r", str(ROOT / "requirements.txt")], cwd=ROOT, check=True)
        subprocess.run([str(PYTHON), "-m", "pip", "check"], cwd=ROOT, check=True)
        subprocess.run([str(PYTHON), str(ROOT / "scripts/environment.py")], cwd=ROOT, check=True)
        STAMP.write_text(json.dumps({"requirements_sha256": fingerprint, "python": list(sys.version_info[:3])}, indent=2) + "\n")
    config = ROOT / ".env"
    if not config.exists():
        shutil.copyfile(ROOT / ".env.example", config)
        try:
            config.chmod(0o600)
        except OSError:
            pass
        print("Created .env. Fill in your existing Supabase settings before using data features.")
    else:
        print("Your existing .env was kept unchanged.")
    print("Next: run start.bat (Windows) or ./start.sh (macOS/Linux).")
    return 0

if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, subprocess.CalledProcessError) as exc:
        print(f"Setup did not finish ({type(exc).__name__}). Check Python/internet access, then rerun setup. Your .env was not reset.", file=sys.stderr)
        raise SystemExit(1)

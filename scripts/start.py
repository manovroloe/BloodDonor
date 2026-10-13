"""Run the website with an existing environment; do not install anything."""
from __future__ import annotations
import os
import sys
from environment import ROOT, dependency_problems, supported_python

def main() -> int:
    if not supported_python():
        print("This release is configured for Python 3.12 or 3.13.", file=sys.stderr)
        return 1
    problems = dependency_problems()
    if problems:
        print("Environment setup/update is required. Run setup.bat or ./setup.sh once.", file=sys.stderr)
        print("\n".join(problems), file=sys.stderr)
        return 1
    if not (ROOT / ".env").is_file() and not (os.getenv("SUPABASE_URL") or os.getenv("BLOODCARE_ENV_FILE")):
        print("No .env found. Public pages can open, but data features need server configuration.")
    os.chdir(ROOT)
    # Same interpreter and foreground process; Ctrl+C shuts the server down normally.
    os.execv(sys.executable, [sys.executable, str(ROOT / "run.py")])
    return 0

if __name__ == "__main__":
    raise SystemExit(main())

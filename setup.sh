#!/bin/sh
set -eu
cd "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
if [ -x .venv/bin/python ]; then
    exec .venv/bin/python scripts/setup.py "$@"
fi
if [ -n "${PYTHON:-}" ]; then
    exec "$PYTHON" scripts/setup.py "$@"
fi
for executable in python3.13 python3.12 python3; do
    if command -v "$executable" >/dev/null 2>&1; then
        exec "$executable" scripts/setup.py "$@"
    fi
done
printf '%s\n' 'Install Python 3.12 or 3.13 on this developer/server computer first.' >&2
exit 1

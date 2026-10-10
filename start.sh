#!/bin/sh
set -eu
cd "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
if [ ! -x .venv/bin/python ]; then
    printf '%s\n' 'Run ./setup.sh once before starting BloodCare.' >&2
    exit 1
fi
exec .venv/bin/python scripts/start.py

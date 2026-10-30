#!/usr/bin/env bash
# Runs every check that exists. Grows over time; exits non-zero on any failure.
set -u
cd "$(dirname "$0")/.."
export PATH="$PWD/tools/bin:$PATH"
fail=0
run() { echo "== $*"; "$@" || { echo "FAILED: $*"; fail=1; }; }
[ -x tools/test.sh ] && run tools/test.sh
[ -f tools/content/validate.py ] && run .venv/bin/python tools/content/validate.py
[ -f tools/content/test_validate.py ] && run .venv/bin/python -m pytest -q tools/content
[ -f tools/terrain/check_region.py ] && run .venv/bin/python tools/terrain/check_region.py
[ -f tools/terrain/test_check_region.py ] && run .venv/bin/python -m pytest -q tools/terrain
[ -f tools/terrain/test_heightfield.py ] && run .venv/bin/python -m pytest -q tools/terrain/test_heightfield.py
[ -f tools/audio/test_audio_assets.py ] && run .venv/bin/python -m pytest -q tools/audio
run bash -c 'godot --headless --path game --quit-after 300 2>&1 | grep -q BOOT_OK'
[ -f tools/blender/check_budget.py ] && run .venv/bin/python tools/blender/check_budget.py
exit $fail

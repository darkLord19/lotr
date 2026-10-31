#!/usr/bin/env bash
# Runs GUT headless. Exits non-zero on any failing test.
cd "$(dirname "$0")/.."
export PATH="$PWD/tools/bin:$PATH"
exec godot --headless --path game -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/unit -ginclude_subdirs -gexit "$@"

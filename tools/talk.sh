#!/usr/bin/env bash
# usage: tools/talk.sh --npc=<id> --date=<date> --say="..." [--say="..."] [--interactive] [--mock] [--keep-memory]
# Without OPENROUTER_API_KEY it runs on the authored fallback lines (and says so).
cd "$(dirname "$0")/.."
export PATH="$PWD/tools/bin:$PATH"
exec godot --headless --path game res://tools/talk_cli.tscn -- "$@"

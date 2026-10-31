#!/usr/bin/env bash
# usage: tools/bench.sh <route> [--max-seconds=N] [--weather=<state>] [--date=<iso>]
# Routes live in game/config/bench.json. Writes build/bench/<route>.csv and prints BENCH_RESULT
# plus the process's peak resident memory (sampled with ps). Windowed at 2560x1440.
# BENCH_UNCAPPED=1 disables vsync to show headroom above the display rate.
# Exit 0 = targets met, 3 = missed.
cd "$(dirname "$0")/.."
export PATH="$PWD/tools/bin:$PATH"
route="$1"; shift
mkdir -p build/bench
extra=(); [ -n "${BENCH_UNCAPPED:-}" ] && extra=(--disable-vsync)
log="build/bench/$route.log"
godot --path game --resolution 2560x1440 "${extra[@]}" res://tools/bench_runner.tscn -- --route="$route" --out="$PWD/build/bench/$route.csv" "$@" 2>&1 | tee "$log" &
pipe=$!
peak=0
while kill -0 "$pipe" 2>/dev/null; do
  rss=$(ps -axo rss=,comm= | awk '/[Gg]odot/ {if ($1>m) m=$1} END {print m+0}')
  [ "$rss" -gt "$peak" ] && peak=$rss
  sleep 2
done
wait "$pipe"
printf 'PEAK_RSS_GB=%.2f\n' "$(echo "$peak / 1048576" | bc -l)" | tee -a "$log"
grep -q "verdict=PASS" "$log" && [ "$peak" -lt 6291456 ]

#!/usr/bin/env bash
# usage: tools/capture.sh <scene_res_path|-> <out.png> [--date=...] [--pos=x,y,z] [--look=yaw,pitch] [--after=sec] [--preset=<name>]
# Use '-' as the scene to take the scene from --preset (config/capture_presets.json).
# Windowed (headless cannot render). On a machine with no display (Linux cloud) it runs under xvfb with software Vulkan.
cd "$(dirname "$0")/.."
export PATH="$PWD/tools/bin:$PATH"
scene="$1"; out="$2"; shift 2
mkdir -p "$(dirname "$out")"
case "$out" in /*) abs="$out";; *) abs="$PWD/$out";; esac
scene_arg=(--scene="$scene"); [ "$scene" = "-" ] && scene_arg=()
cmd=(godot --path game --resolution 2560x1440 -- "${scene_arg[@]}" --capture="$abs" "$@")
if [ -z "${DISPLAY:-}" ] && [ "$(uname)" = "Linux" ]; then
  exec xvfb-run -a -s "-screen 0 2560x1440x24" "${cmd[@]}"
fi
exec "${cmd[@]}"

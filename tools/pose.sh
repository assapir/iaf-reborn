#!/usr/bin/env bash
# Capture a posed external view of the player's jet for checking animations.
# usage: tools/pose.sh out.png orbit_yaw orbit_pitch dist [extra godot args...]
set -euo pipefail
cd "$(dirname "$0")/.."
out=$1 yaw=$2 pitch=$3 dist=$4; shift 4
timeout 150 godot --path game res://terrain/terrain_view.tscn -- --screenshot "$out" \
  --at 357742 482603 1500 90 0 0 --external --freeze --orbit "$yaw" "$pitch" "$dist" "$@" >/dev/null 2>&1

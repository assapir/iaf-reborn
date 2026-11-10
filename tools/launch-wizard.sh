#!/usr/bin/env bash
# Opens a setup wizard: ./setup (the original game, docs/setup.md) and ./modern-iaf-setup (Modern IAF,
# modern-iaf/docs/setup.md) call it. Checks for Rust (cargo) and Godot 4.7 (tools/launch-checks.sh), builds the
# extension, imports the project when it needs it (tools/godot_import.sh), then starts the project's
# res://setup/wizard.tscn.
#   tools/launch-wizard.sh <project folder> <window title> <resolution, e.g. 1200x820>
set -euo pipefail
cd "$(dirname "$0")/.."
project=${1:?usage: tools/launch-wizard.sh <project> <title> <resolution>}
title=${2:?title}
resolution=${3:?resolution}

who=Setup
# shellcheck source=tools/launch-checks.sh
source tools/launch-checks.sh

echo "building the game's extension (the first time takes a few minutes)…"
cargo build --release -p iaf-godot
# Godot's import on a fresh clone and after a pull with new shaders or textures (tools/godot_import.sh).
tools/godot_import.sh "$godot" "$project"
# As ./start-modern-iaf and ./iafjets: the wizard's Start the game opens the front end in this process (controls.md §5.2).
[[ $(uname) == Darwin ]] && export SDL_JOYSTICK_MFI=${SDL_JOYSTICK_MFI:-0}
exec "$godot" --path "$project" --resolution "$resolution" res://setup/wizard.tscn

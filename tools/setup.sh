#!/usr/bin/env bash
# One-shot setup: build everything the game needs from your own copy of Jane's IAF.
#
#   tools/setup.sh "/path/to/Jane's IAF.iso" [/path/to/Brief.zip]
#
# Brief.zip is the optional Hebrew briefings pack (see docs/packs.md).
# Safe to re-run: each step overwrites its own output under assets/.
set -euo pipefail
cd "$(dirname "$0")/.."

iso=${1:?usage: tools/setup.sh "/path/to/Jane's IAF.iso" [Brief.zip]}
hebrew_zip=${2:-}

step() { printf '\n==> %s\n' "$*"; }

step "building tools"
cargo build --release -p iaf-tools

step "extracting the original install from the CD image"
./target/release/iaf-extract "$iso" assets/install

step "aircraft models (glTF, Lanczos-upscaled textures, smoothed geometry)"
./target/release/iaf-convert --upscale --smooth planes assets/install assets/converted/planes

step "F-16 cockpit art and layout"
./target/release/iaf-convert --upscale cockpit assets/install f16 assets/converted/cockpits/f16

step "front-end menus (screens, strings, art, fonts)"
./target/release/iaf-convert --upscale menu assets/install assets/converted/menu

step "terrain around Israel (colour: level-4 inset, heights: level 6)"
./target/release/iaf-terrain export assets/install/resource/terrain/map.ptt 7 assets/converted/terrain/israel_l4

if [[ -n "$hebrew_zip" ]]; then
	step "Hebrew briefings pack"
	./target/release/iaf-import-pack "$hebrew_zip" he assets/install assets/packs
fi

step "Godot extension (flight model)"
cargo build -p iaf-godot

step "done — run: godot --path game"

#!/usr/bin/env bash
# One-shot setup: build everything the game needs from your own copy of Jane's IAF.
#
#   tools/setup.sh "/path/to/Jane's IAF.iso" [/path/to/Brief.zip /path/to/Menu.zip]
#
# Brief.zip / Menu.zip are the optional Hebrew briefings and menus packs (see docs/packs.md).
# Safe to re-run: each step overwrites its own output under assets/.
set -euo pipefail
cd "$(dirname "$0")/.."

iso=${1:?usage: tools/setup.sh "/path/to/Jane's IAF.iso" [Brief.zip]}
hebrew_zip=${2:-}
hebrew_menu_zip=${3:-}

step() { printf '\n==> %s\n' "$*"; }

step "building tools"
cargo build --release -p iaf-tools

step "extracting the original install from the CD image"
./target/release/iaf-extract "$iso" assets/install

step "aircraft models (glTF, Lanczos-upscaled textures, smoothed geometry)"
./target/release/iaf-convert --upscale --smooth planes assets/install assets/converted/planes

step "F-16 cockpit art and layout"
./target/release/iaf-convert --upscale cockpit assets/install f16 assets/converted/cockpits/f16

if [[ -n "$hebrew_zip" ]]; then
	step "Hebrew briefings pack"
	./target/release/iaf-import-pack "$hebrew_zip" he assets/install assets/packs
fi
if [[ -n "$hebrew_menu_zip" ]]; then
	step "Hebrew menus pack"
	./target/release/iaf-import-pack "$hebrew_menu_zip" he assets/install assets/packs
fi

step "briefings (English + Hebrew pack when imported)"
./target/release/iaf-convert --upscale briefings assets/install assets/packs assets/converted/briefings

step "front-end menus (screens, strings, art, fonts)"
./target/release/iaf-convert --upscale menu assets/install assets/converted/menu
if [[ -d assets/packs/he/resource/menu ]]; then
	./target/release/iaf-convert --upscale menu assets/install assets/converted/menu_he --pack assets/packs/he
fi

step "terrain around Israel (colour: level-4 inset, heights: level 6)"
./target/release/iaf-terrain export assets/install/resource/terrain/map.ptt 7 assets/converted/terrain/israel_l4

step "Godot extension (flight model)"
cargo build -p iaf-godot

step "done — run: godot --path game"

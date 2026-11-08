#!/usr/bin/env bash
# Opens a setup wizard: ./setup (the original game, docs/setup.md) and ./iaf2026-setup (Modern IAF,
# iaf-2026/docs/setup.md) call it. Checks for Rust (cargo) and Godot 4.7, builds the extension, imports the project
# when it needs it (tools/godot_import.sh), then starts the project's res://setup/wizard.tscn.
#   tools/launch-wizard.sh <project folder> <window title> <resolution, e.g. 1200x820>
set -euo pipefail
cd "$(dirname "$0")/.."
project=${1:?usage: tools/launch-wizard.sh <project> <title> <resolution>}
title=${2:?title}
resolution=${3:?resolution}

# A missing tool: a native dialog when there is one (zenity / kdialog / osascript), else the terminal.
tell() {
	if [[ $(uname) == Darwin ]]; then
		osascript -e "display dialog \"$1\" with title \"$title\" buttons {\"OK\"} with icon caution" >/dev/null 2>&1 || true
	elif [[ -n ${DISPLAY:-}${WAYLAND_DISPLAY:-} ]] && command -v zenity >/dev/null; then
		zenity --error --title="$title" --text="$1" 2>/dev/null || true
	elif [[ -n ${DISPLAY:-}${WAYLAND_DISPLAY:-} ]] && command -v kdialog >/dev/null; then
		kdialog --title "$title" --error "$1" 2>/dev/null || true
	fi
	echo "$1" >&2
}
if [[ $(uname) == Darwin ]]; then
	install='brew install rustup godot, then: rustup default stable'
	export PATH="$HOME/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
else
	install='sudo pacman -S rustup godot, then: rustup default stable (other systems: rustup.rs and godotengine.org, Godot 4.7)'
fi
command -v cargo >/dev/null || { tell "Setup needs Rust (cargo) to build the game. Install it: $install"; exit 1; }
godot=${GODOT:-godot}
if ! command -v "$godot" >/dev/null && [[ -x /Applications/Godot.app/Contents/MacOS/Godot ]]; then
	godot=/Applications/Godot.app/Contents/MacOS/Godot
	export PATH="/Applications/Godot.app/Contents/MacOS:$PATH"  # the guides' scripts call `godot` (APFS: any case)
fi
command -v "$godot" >/dev/null || { tell "Setup needs Godot 4.7. Install it: $install"; exit 1; }
[[ $("$godot" --version 2>/dev/null) == 4.7* ]] || { tell "Setup needs Godot 4.7 (this one is $("$godot" --version 2>/dev/null))."; exit 1; }

echo "building the game's extension (the first time takes a few minutes)…"
cargo build --release -p iaf-godot
# Godot's import on a fresh clone and after a pull with new shaders or textures (tools/godot_import.sh).
tools/godot_import.sh "$godot" "$project"
exec "$godot" --path "$project" --resolution "$resolution" res://setup/wizard.tscn

# Sourced by the launchers that build and start a Godot project (tools/launch-wizard.sh, ./start-modern-iaf): finds Rust (cargo)
# and Godot 4.7, says how to install a missing one, and sets $godot. The caller sets $title (the dialog's title) and
# $who (the sentence's subject, e.g. "Setup").
# shellcheck shell=bash
: "${title:?}" "${who:?}"

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

godot=${GODOT:-godot}
if [[ $(uname) == Darwin ]]; then
	install="brew install rustup godot, then: \$(brew --prefix rustup)/bin/rustup default stable"
	# A start from Finder or a shell without Homebrew's setup: its paths (its rustup is keg-only: cargo is in
	# opt/rustup/bin; rustup.rs puts it in ~/.cargo/bin).
	if ! command -v cargo >/dev/null || ! command -v "$godot" >/dev/null; then
		export PATH="$HOME/.cargo/bin:/opt/homebrew/opt/rustup/bin:/usr/local/opt/rustup/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
	fi
	if ! command -v "$godot" >/dev/null && [[ -x /Applications/Godot.app/Contents/MacOS/Godot ]]; then
		godot=/Applications/Godot.app/Contents/MacOS/Godot
		export PATH="/Applications/Godot.app/Contents/MacOS:$PATH" # the guides' scripts call `godot` (APFS: any case)
	fi
else
	install='sudo pacman -S rustup godot, then: rustup default stable (other systems: rustup.rs and godotengine.org, Godot 4.7)'
fi
command -v cargo >/dev/null || { tell "$who needs Rust (cargo) to build the game. Install it: $install"; exit 1; }
command -v "$godot" >/dev/null || { tell "$who needs Godot 4.7. Install it: $install"; exit 1; }
[[ $("$godot" --version 2>/dev/null) == 4.7* ]] || { tell "$who needs Godot 4.7 (this one is $("$godot" --version 2>/dev/null))."; exit 1; }

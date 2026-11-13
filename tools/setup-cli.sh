#!/usr/bin/env bash
# The scripted setup: the wizard's pipeline (crates/iaf-setup, docs/setup.md) from a terminal. Steps whose stamp holds
# are skipped, so re-running it only redoes what changed.
#
#   tools/setup-cli.sh [--patch P] [--hebrew-iso ISO] [--imagery sentinel2,mapi2015,mapi2015-bases] [--scenery[=buildings|trees]]
#                      ["/path/to/Jane's IAF.iso" [Brief.zip] [Menu.zip]]
#
# Every option of iaf-setup (crates/iaf-setup/src/bin/iaf-setup.rs) works too, e.g. --redo-all. Without the ISO the
# last run's inputs (assets/setup.json) are used, with the options given added. IAF_PATCH and IAF_HEBREW_ISO stand for
# --patch and --hebrew-iso. With a display the pilot guides are rendered too (--guides).
# IAF_IMAGERY_MIRROR=user@host:/path/to/repo restores a missing assets/converted/imagery (and the sheets) with rsync,
# then converts again what older rules made there (--refresh-imagery; docs/imagery.md §2).
set -euo pipefail
cd "$(dirname "$0")/.."

# assets/ must be a real folder (or a worktree's link to one): a link to itself (a committed worktree symlink merged
# into the main checkout wiped assets/ on 2026-10-16) would make every step write nowhere.
if [[ -L assets && ! -d assets/ ]]; then
	echo "assets is a broken symlink ($(readlink assets)): remove it (rm assets) and run setup again"; exit 1
fi
args=()
[[ -n ${IAF_PATCH:-} ]] && args+=(--patch "$IAF_PATCH")
[[ -n ${IAF_HEBREW_ISO:-} ]] && args+=(--hebrew-iso "$IAF_HEBREW_ISO")
if [[ $(uname) == Darwin && -z ${SSH_CONNECTION:-} ]] || [[ -n ${DISPLAY:-}${WAYLAND_DISPLAY:-} ]]; then
	# The guides' pictures are real renders: the game's extension and Godot's import first.
	cargo build --release -q -p iaf-godot && { tools/godot_import.sh godot || true; }
	args+=(--guides)
fi
if [[ -n ${IAF_IMAGERY_MIRROR:-} && ! -d assets/converted/imagery ]]; then
	mkdir -p assets/converted assets/source
	rsync -a "$IAF_IMAGERY_MIRROR/assets/converted/imagery" assets/converted/ &&
		rsync -a "$IAF_IMAGERY_MIRROR/assets/source/imagery" assets/source/ 2>/dev/null || true
	args+=(--refresh-imagery)
fi
for a in "$@"; do
	case $a in
		--scenery=*) args+=(--scenery --scenery-kinds "${a#*=}") ;;
		--*=*) args+=("${a%%=*}" "${a#*=}") ;;
		*) args+=("$a") ;;
	esac
done
exec cargo run --release -q -p iaf-setup --bin iaf-setup -- ${args[@]+"${args[@]}"}

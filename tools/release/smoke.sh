#!/usr/bin/env bash
# Starts a release bundle headless (docs/release.md "Checks"): unpacks it, runs the game on an empty data folder for
# 900 frames (no data: the game opens its setup wizard; with arguments, until the game quits) and fails on a SCRIPT ERROR,
# the game's crash page or a missing version line.
#   tools/release/smoke.sh <bundle (.tar.gz, .zip, .dmg)> [more game arguments, e.g. -s <script>]
# The game's log: $SMOKE_LOG (default a temp file). $IAF_ASSETS_DIR, when set, is the data folder used.
set -euo pipefail
bundle=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
shift
work=$(mktemp -d)
mnt=
cleanup() {
	[[ -n $mnt ]] && hdiutil detach -quiet "$mnt"
	rm -rf "$work"
}
trap cleanup EXIT
case $bundle in
*.tar.gz) tar -C "$work" -xzf "$bundle" && exe=$(ls "$work"/*/*.x86_64) ;;
*.zip) (cd "$work" && 7z x -bso0 "$bundle") && exe=$(ls "$work"/*/*.exe) ;;
*.dmg)
	mnt="$work/mnt"
	hdiutil attach -quiet -nobrowse -readonly -mountpoint "$mnt" "$bundle"
	exe=$(ls "$mnt"/*.app/Contents/MacOS/*)
	;;
*) echo "unknown bundle: $bundle" >&2; exit 2 ;;
esac
log=${SMOKE_LOG:-$work/game.log}
mkdir -p "$work/data"
export IAF_DEFAULT_SETTINGS=1 IAF_ASSETS_DIR=${IAF_ASSETS_DIR:-$work/data}
echo "smoke: $exe"
code=0
# With a script (-s …) the script decides when to quit.
quit=(--quit-after 900)
[[ $# -gt 0 ]] && quit=()
"$exe" --headless --audio-driver Dummy "${quit[@]}" --log-file "$log" "$@" || code=$?
grep -m1 "| version " "$log" || { echo "smoke: no version line in $log" >&2; exit 1; }
# A SCRIPT ERROR, or the game's own crash page (a "crash:" line: an engine error it caught).
if grep -qE "SCRIPT ERROR|^crash: " "$log"; then
	grep -E -A3 "SCRIPT ERROR|^crash: " "$log" | head -40 >&2
	exit 1
fi
[[ $code == 0 ]] || { echo "smoke: the game exited with $code" >&2; tail -20 "$log" >&2; exit 1; }
echo "smoke: OK"

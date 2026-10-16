#!/usr/bin/env bash
# The pilot guides' pictures (docs/guides/<jet>.shots.json, docs/front-end.md §14 "Pilot guide"): one real-render
# Godot process per entry (tests/godot/_guide_shots.gd) at 3840×2160 (sharp crops) into assets/converted/guides/shots/<jet>/.
# They hold the original cockpit art, so they stay under assets/ (never committed). Needs a display.
#   tools/guide_shots.sh [jet …] [--only name,name]
set -euo pipefail
cd "$(dirname "$0")/.."
# Godot logs go here, not into the player's user folder (whose rotation keeps only the newest logs).
logs=$(mktemp -d "${TMPDIR:-/tmp}/iaf-logs.XXXXXX")
only=""
jets=()
while (($#)); do
	case $1 in
		--only) only=$2; shift 2 ;;
		*) jets+=("$1"); shift ;;
	esac
done
if ((${#jets[@]} == 0)); then
	for f in docs/guides/*.shots.json; do jets+=("$(basename "$f" .shots.json)"); done
fi
for jet in "${jets[@]}"; do
	json="docs/guides/$jet.shots.json"
	out="assets/converted/guides/shots/$jet"
	for name in $(python3 -I -c 'import json, sys; print(" ".join(s["name"] for s in json.load(open(sys.argv[1]))))' "$json"); do
		[[ -n $only && ",$only," != *",$name,"* ]] && continue
		GUIDE_JSON="$PWD/$json" GUIDE_SHOT="$name" GUIDE_OUT="$PWD/$out" IAF_DEFAULT_SETTINGS=1 \
			godot --log-file "$logs/$name.log" --path game --resolution 3840x2160 --audio-driver Dummy -s ../tests/godot/_guide_shots.gd 2>&1 \
			| grep -E "^(PASS|FAIL) shot|SCRIPT ERROR" || true
	done
done

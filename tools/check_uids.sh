#!/usr/bin/env bash
# Fails when a tracked script or shader in a Godot project lacks a tracked .uid, or when an untracked .uid appears
# (run it after `godot --import`). tests/ and tools/ lie outside every project's res://, so Godot writes no .uid there.
set -euo pipefail
cd "$(dirname "$0")/.."
dirs=(iaf-reborn modern-iaf shared)
fail=0
tracked=$(git ls-files "${dirs[@]}")
while read -r f; do
	grep -qxF "$f.uid" <<<"$tracked" || { echo "missing tracked uid: $f.uid"; fail=1; }
done < <(grep -E '\.(gd|gdshader)$' <<<"$tracked")
while read -r f; do
	[[ -n $f ]] && { echo "untracked uid: $f"; fail=1; }
done < <(git ls-files --others --exclude-standard -- '*.uid')
[[ $fail == 0 ]] && echo "check_uids: ok" || { echo "commit the .uid files Godot writes beside scripts and shaders"; exit 1; }

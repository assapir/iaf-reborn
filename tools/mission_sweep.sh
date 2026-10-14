#!/usr/bin/env bash
# Runs tests/godot/_mission_sweep.gd once per mission, JOBS at a time, headless; one log per mission in OUT, then
# a summary: each mission's SWEEP line and its script errors / engine errors. Usage:
#   tools/mission_sweep.sh OUT_DIR [mission ids…]   (default: the playable missions of docs/mission-coverage.md)
# Env: SWEEP_SECONDS (mission time, default 240), JOBS (default 2).
set -uo pipefail
cd "$(dirname "$0")/.."
out=${1:?out dir}; shift
mkdir -p "$out"
ids=("$@")
[[ ${#ids[@]} -gt 0 ]] || read -ra ids <<<"$(grep -o '^\*\*Playable today: [0-9]* of [0-9]*\*\* ([0-9, ]*)' docs/mission-coverage.md | sed 's/.*(//; s/[,)]//g')"
printf '%s\n' "${ids[@]}" | xargs -P "${JOBS:-2}" -I{} sh -c \
	'MISSIONS={} IAF_DEFAULT_SETTINGS=1 timeout 900 godot --headless --audio-driver Dummy --path game -s ../tests/godot/_mission_sweep.gd >"$0/{}.log" 2>&1; echo "exit $?" >>"$0/{}.log"' "$out"
for id in "${ids[@]}"; do
	f="$out/$id.log"
	grep -h '^SWEEP' "$f" || echo "SWEEP $id: no result ($(tail -1 "$f"))"
	grep -h -E 'SCRIPT ERROR|^ERROR|^WARNING' "$f" | grep -v -E 'resources still in use|ObjectDB instances were leaked' | sort | uniq -c | sed 's/^/    /'
done

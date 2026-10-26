#!/usr/bin/env bash
# CI only (docs/ci.md): runs every tests/godot/test_*.gd headless without game data, four at a time, and writes
# a pass / fail / needs-data / timeout table to $GITHUB_STEP_SUMMARY (or stdout). Exit 1 unless all pass.
# "needs-data" is a guess: a failing run whose output names assets/.
set -uo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/godot-tests.XXXXXX")
command -v cygpath >/dev/null && out=$(cygpath -m "$out") # Godot on Windows wants D:/a/..., not /d/a/...
export out

one() {
	local t=$1 n
	n=$(basename "$t" .gd)
	local env=()
	[[ $n == test_setup_wizard ]] && env=(IAF_ASSETS_DIR="$out/$n-assets") && mkdir -p "$out/$n-assets"
	env "${env[@]}" IAF_DEFAULT_SETTINGS=1 timeout 300 godot --log-file "$out/$n.log" --headless \
		--audio-driver Dummy --path game -s "../$t" >"$out/$n.out" 2>&1
	echo $? >"$out/$n.rc"
}
export -f one
ls tests/godot/test_*.gd | xargs -P 4 -I{} bash -c 'one {}'

declare -A count
table="| test | result | first failure |"$'\n'"|---|---|---|"$'\n'
for t in tests/godot/test_*.gd; do
	n=$(basename "$t" .gd)
	f="$out/$n.out"
	rc=$(cat "$out/$n.rc")
	if [[ $rc == 124 ]]; then
		r=timeout
	elif grep -q "RESULT PASS" "$f" && ! grep -q "SCRIPT ERROR" "$f"; then
		r=pass
	elif grep -q "assets/" "$f"; then
		r=needs-data
	else
		r=fail
	fi
	count[$r]=$((${count[$r]:-0} + 1))
	why=""
	[[ $r != pass ]] && why=$(grep -m1 -E "^FAIL|SCRIPT ERROR|ERROR" "$f" | cut -c1-140 | tr '|' '/')
	table+="| $n | $r | ${why//$'\n'/ } |"$'\n'
done
{
	echo "### Godot tests without game data ($RUNNER_OS)"
	echo
	for r in pass fail needs-data timeout; do echo "- $r: ${count[$r]:-0}"; done
	echo
	echo "$table"
} >>"${GITHUB_STEP_SUMMARY:-/dev/stdout}"
[[ -z ${count[fail]:-}${count[needs-data]:-}${count[timeout]:-} ]]

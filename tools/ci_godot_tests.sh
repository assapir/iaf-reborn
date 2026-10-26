#!/usr/bin/env bash
# CI only (docs/ci.md): runs the given Godot tests (default: every tests/godot/test_*.gd) headless without game
# data, several at once, 60 s each,
# prints each result as it comes, and writes a pass / fail / needs-data / timeout table to $GITHUB_STEP_SUMMARY
# (or stdout). Exit 1 unless all pass.
# "needs-data" is a guess: a failing run whose errors name assets/ (the boot splash's missing image aside).
set -uo pipefail
cd "$(dirname "$0")/.."
tests=("$@")
[[ $# == 0 ]] && tests=(tests/godot/test_*.gd)
out=${GODOT_TESTS_OUT:-$(mktemp -d "${TMPDIR:-/tmp}/godot-tests.XXXXXX")}
command -v cygpath >/dev/null && out=$(cygpath -m "$out") # Godot on Windows wants D:/a/..., not /d/a/...
mkdir -p "$out"
export out
# macOS: coreutils' timeout is gtimeout (brew install coreutils); its bash is 3.2.
to=$(command -v timeout || command -v gtimeout)
export to

one() {
	local t=$1 n r s=$SECONDS
	n=$(basename "$t" .gd)
	local env=()
	[[ $n == test_setup_wizard ]] && env=(IAF_ASSETS_DIR="$out/$n-assets") && mkdir -p "$out/$n-assets"
	env ${env[@]+"${env[@]}"} IAF_DEFAULT_SETTINGS=1 "$to" -k 5 60 godot --log-file "$out/$n.log" --headless \
		--audio-driver Dummy --path game -s "../$t" >"$out/$n.out" 2>&1
	local rc=$? f="$out/$n.out"
	if [[ $rc == 124 || $rc == 137 ]]; then
		r=timeout
	elif grep -q "RESULT PASS" "$f" && ! grep -q "SCRIPT ERROR" "$f"; then
		r=pass
	elif grep -q "^NEEDS DATA" "$f" || grep -E "ERROR|FAIL" "$f" | grep -v "boot splash\|back0.png" | grep -q "assets/"; then
		r=needs-data
	else
		r=fail
	fi
	echo "$r" >"$out/$n.r"
	echo "$r $n ($((SECONDS - s)) s) $(grep -E "^NEEDS DATA|^FAIL|SCRIPT ERROR|ERROR" "$f" | grep -v "boot splash\|back0.png" | head -1 | cut -c1-160)"
}
export -f one
printf '%s\n' "${tests[@]}" | xargs -P "${JOBS:-6}" -I{} bash -c 'one {}'

table="| test | result | first error |"$'\n'"|---|---|---|"$'\n'
for t in "${tests[@]}"; do
	n=$(basename "$t" .gd)
	r=$(cat "$out/$n.r")
	why=""
	[[ $r != pass ]] && why=$(grep -E "^NEEDS DATA|^FAIL|SCRIPT ERROR|ERROR" "$out/$n.out" | grep -v "boot splash\|back0.png" |
		head -1 | cut -c1-140 | tr '|' '/')
	table+="| $n | $r | $why |"$'\n'
done
{
	echo "### Godot tests without game data ($RUNNER_OS)"
	echo
	for r in pass fail needs-data timeout; do echo "- $r: $(cat "$out"/*.r | grep -cx "$r")"; done
	echo
	echo "<details><summary>per test</summary>"
	echo
	echo "$table"
	echo "</details>"
} >>"${GITHUB_STEP_SUMMARY:-/dev/stdout}"
! cat "$out"/*.r | grep -qvx pass

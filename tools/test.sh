#!/usr/bin/env bash
# Runs every test: Rust unit/validation tests, the headless Godot tests in tests/godot (the original game) and
# modern-iaf/tests (Modern IAF), then gdparse on both projects.
# Needs the converted assets (tools/setup-cli.sh). Tests never touch the player's settings
# (IAF_DEFAULT_SETTINGS=1) and open no window.
set -uo pipefail
cd "$(dirname "$0")/.."
# Godot logs go here, not into the player's user folder (whose rotation keeps only the newest logs).
logs=$(mktemp -d "${TMPDIR:-/tmp}/iaf-logs.XXXXXX")
fail=0
echo "== tests/test_flight_timeline.py"
python3 -I tests/test_flight_timeline.py || fail=1
echo "== cargo test"
cargo test -q --workspace 2>&1 | grep -E "test result|FAILED|panicked" || fail=1
cargo build -q --release -p iaf-godot || fail=1
# test_sim_data.gd compiles Modern IAF's data with it.
cargo build -q --release -p iaf-setup --bin iaf-sim || fail=1
for t in tests/godot/test_*.gd; do
	echo "== $t"
	# The setup wizard's test builds its own data into an empty scratch folder, never into assets/.
	env=()
	[[ $t == */test_setup_wizard.gd ]] && env=(IAF_ASSETS_DIR="$(mktemp -d "$logs/wizard-assets.XXXXXX")")
	out=$(env "${env[@]}" IAF_DEFAULT_SETTINGS=1 timeout 300 godot --log-file "$logs/$(basename "$t" .gd).log" --headless --audio-driver Dummy --path iaf-reborn -s "../$t" 2>&1)
	rc=$?
	echo "$out" | grep -E "^(PASS|FAIL|RESULT)|SCRIPT ERROR"
	# A hang: say so and show where it stopped.
	[[ $rc == 124 ]] && { echo "FAIL timeout (300 s); last output:"; echo "$out" | tail -15; }
	echo "$out" | grep -q "RESULT PASS" || fail=1
	echo "$out" | grep -q "SCRIPT ERROR" && { echo "FAIL script errors"; fail=1; }
done
# Modern IAF's tests in its own project; NEEDS DATA (the sim's data not built yet, modern-iaf/docs/status.md) is no failure.
for t in modern-iaf/tests/test_*.gd; do
	echo "== $t"
	# Its setup wizard's test, as the original's: an empty scratch folder for assets/.
	env=()
	[[ $t == */test_setup_wizard.gd ]] && env=(IAF_ASSETS_DIR="$(mktemp -d "$logs/wizard-assets.XXXXXX")")
	out=$(env "${env[@]}" IAF_DEFAULT_SETTINGS=1 timeout 300 godot --log-file "$logs/2026-$(basename "$t" .gd).log" --headless --audio-driver Dummy --path modern-iaf -s "../$t" 2>&1)
	rc=$?
	echo "$out" | grep -E "^(PASS|FAIL|RESULT|NEEDS DATA)|SCRIPT ERROR"
	[[ $rc == 124 ]] && { echo "FAIL timeout (300 s); last output:"; echo "$out" | tail -15; }
	echo "$out" | grep -qE "RESULT PASS|^NEEDS DATA" || fail=1
	echo "$out" | grep -q "SCRIPT ERROR" && { echo "FAIL script errors"; fail=1; }
done
# Every script of both projects parses (tools/gdparse.gd).
for p in iaf-reborn modern-iaf; do
	echo "== gdparse $p"
	out=$(godot --headless --path "$p" -s ../tools/gdparse.gd --log-file "$logs/gdparse-$p.log" 2>&1)
	rc=$?
	echo "$out" | grep -E "^(BAD|gdparse)"
	[[ $rc == 0 ]] || fail=1
done
# Every script and shader has its tracked .uid, and the imports left no untracked one.
echo "== check_uids"
tools/check_uids.sh || fail=1
# The logs (and the wizard's scratch data) are kept only when something failed.
[[ $fail == 0 ]] && { rm -rf "$logs"; echo "ALL TESTS PASSED"; } || { echo "SOME TESTS FAILED (logs: $logs)"; exit 1; }

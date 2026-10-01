#!/usr/bin/env bash
# Runs every test: Rust unit/validation tests, then the headless Godot tests in tests/godot.
# Needs the converted assets (tools/setup.sh). Tests never touch the player's settings
# (IAF_DEFAULT_SETTINGS=1) and open no window.
set -uo pipefail
cd "$(dirname "$0")/.."
fail=0
echo "== cargo test"
cargo test -q --workspace 2>&1 | grep -E "test result|FAILED|panicked" || fail=1
cargo build -q --release -p iaf-godot || fail=1
for t in tests/godot/test_*.gd; do
	echo "== $t"
	out=$(IAF_DEFAULT_SETTINGS=1 timeout 300 godot --headless --audio-driver Dummy --path game -s "../$t" 2>&1)
	rc=$?
	echo "$out" | grep -E "^(PASS|FAIL|RESULT)|SCRIPT ERROR"
	# A hang: say so and show where it stopped.
	[[ $rc == 124 ]] && { echo "FAIL timeout (300 s); last output:"; echo "$out" | tail -15; }
	echo "$out" | grep -q "RESULT PASS" || fail=1
	echo "$out" | grep -q "SCRIPT ERROR" && { echo "FAIL script errors"; fail=1; }
done
[[ $fail == 0 ]] && echo "ALL TESTS PASSED" || { echo "SOME TESTS FAILED"; exit 1; }

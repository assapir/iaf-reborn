#!/usr/bin/env bash
# Runs Godot with a real renderer (screenshots, benches) out of the user's way: on macOS as a hidden app that never takes
# the focus (open -g -j: it renders, no window shows); on Linux under xvfb-run when it is installed, else plainly.
# VAR=value words before `--` are passed to Godot's environment; the rest are Godot's arguments. --log-file is required:
# Godot's output goes there (open has no stdout), and the script prints it when Godot exits.
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 GUIDE_SHOT=hud_nav -- --log-file /tmp/g.log --path game -s ../tests/godot/_guide_shots.gd
set -euo pipefail
envs=()
while (($#)) && [[ $1 != -- ]]; do envs+=("$1"); shift; done
[[ ${1:-} == -- ]] && shift
args=()
log=""
while (($#)); do
	case $1 in
		--path | --log-file)
			v=$(cd "$(dirname "$2")" && pwd)/$(basename "$2")  # open starts Godot elsewhere: absolute paths
			[[ $1 == --log-file ]] && log=$v
			args+=("$1" "$v"); shift 2 ;;
		*) args+=("$1"); shift ;;
	esac
done
[[ -n $log ]] || { echo "godot_window.sh: --log-file is required" >&2; exit 2; }
if [[ $(uname) == Darwin ]]; then
	app=$(python3 -I -c 'import os, sys; p = os.path.realpath(sys.argv[1]); print(p[:p.find(".app") + 4])' "$(command -v godot)")
	envargs=()
	for e in ${envs[@]+"${envs[@]}"}; do envargs+=(--env "$e"); done
	open -W -g -j -n -a "$app" ${envargs[@]+"${envargs[@]}"} --args "${args[@]}"
elif command -v xvfb-run >/dev/null; then
	env ${envs[@]+"${envs[@]}"} xvfb-run -a godot "${args[@]}" >/dev/null 2>&1 || true
else
	env ${envs[@]+"${envs[@]}"} godot "${args[@]}" >/dev/null 2>&1 || true
fi
cat "$log"

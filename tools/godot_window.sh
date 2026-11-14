#!/usr/bin/env bash
# Runs Godot with a real renderer (screenshots, benches) out of the user's way: on macOS as a hidden app that never takes
# the focus (open -g -j: it renders, no window shows); on Linux under xvfb-run when it is installed, else plainly (with
# Vulkan on Intel, Godot finds no present queue on Xvfb and opens on the desktop's Wayland: docs/rendering.md §1.5).
# VAR=value words before `--` are passed to Godot's environment; the rest are Godot's arguments. --log-file is required:
# Godot's output goes there (open has no stdout), and the script prints it when Godot exits.
# The hidden window renders at the size it is given (--resolution); --fullscreen does not resize it. On a Mac with a
# Retina screen attached, Godot counts every screen in the Retina scale's pixels: a 2,560 x 1,440 monitor beside it
# reads 5,120 x 2,880 (DisplayServer.screen_get_size; the user's Dell U2719DC, 2026-11-13). A 5,120 x 2,880 picture
# made there is what that monitor showed fullscreen before the game turned hiDPI off there (docs/real-hud.md "A 1×
# monitor beside a Retina screen"), not a 5K screen. A project's override.cfg with display/window/dpi/allow_hidpi=false
# makes the hidden window render as the game does on that monitor.
#   tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 GUIDE_SHOTS=hud_nav -- --log-file /tmp/g.log --path iaf-reborn -s ../tests/godot/_guide_shots.gd
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
else
	# Godot (and xvfb-run's Xvfb) must not outlive this script: a caller's `flock` lock fd is closed for them, so a
	# Godot hung at quit can't hold ~/.cache/iaf-gpu-bench.lock after a `timeout` killed this script (2026-10-29: an
	# orphaned Godot, then its Xvfb, stalled every session's renders), and they run in their own process group, which
	# is killed when this script ends or is told to stop.
	for fd in "/proc/$$/fd/"*; do
		fd=${fd##*/}
		((fd > 2 && fd != 255)) && eval "exec $fd>&-"
	done 2>/dev/null || true
	run=(godot)
	command -v xvfb-run >/dev/null && run=(xvfb-run -a godot)
	env ${envs[@]+"${envs[@]}"} setsid "${run[@]}" "${args[@]}" >/dev/null 2>&1 &
	pid=$!
	trap 'kill -TERM -- -$pid 2>/dev/null || true' EXIT
	trap 'exit 143' TERM INT
	wait $pid || true
fi
cat "$log"

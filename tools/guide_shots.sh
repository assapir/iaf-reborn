#!/usr/bin/env bash
# The pilot guides' pictures (docs/guides/<jet>.shots.json, docs/front-end.md §14 "Pilot guide"): real-render Godot
# processes (tests/godot/_guide_shots.gd, GUIDE_BATCH shots each, default 4) whose frame is GUIDE_SIZE (default
# 3840x2160, sharp crops, whatever the screen), GUIDE_JOBS at once (default: half the cores, at most one per 2 GB of
# free memory), into GUIDE_SHOTS_DIR/<jet>/ (default assets/converted/guides/shots). They hold the original cockpit art, so they stay under assets/ (never committed).
# Needs a display. A shot whose picture is up to date (its stamp, below) is skipped; --force or GUIDE_FORCE=1 renders
# every one. Each process's lines print together when it ends; a FAIL line or a crashed or stuck process makes the
# exit status 1, with the count at the end.
#   tools/guide_shots.sh [jet …] [--only name,name] [--force]
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ ${1:-} == --job ]]; then  # one process: --job <jet> <name,name,…> (xargs below; $logs / $shots_dir exported)
	jet=$2 names=$3 log="$logs/$2-${3%%,*}"
	tools/godot_window.sh GUIDE_JSON="$PWD/docs/guides/$jet.shots.json" GUIDE_SHOTS="$names" GUIDE_OUT="$shots_dir/$jet" \
		GUIDE_SIZE="${GUIDE_SIZE:-3840x2160}" IAF_DEFAULT_SETTINGS=1 -- --log-file "$log.log" --path game \
		--resolution 3840x2160 --audio-driver Dummy -s ../tests/godot/_guide_shots.gd >/dev/null 2>&1 &
	# A process that runs past GUIDE_TIMEOUT s per shot (default 600) is stopped; one that printed its RESULT and is
	# still there 30 s later (a hang on quit, seen once) is stopped too, its pictures kept.
	limit=$((${GUIDE_TIMEOUT:-600} * ($(tr -cd , <<<"$names" | wc -c) + 1))) s=0 done_at="" note=""
	while kill -0 $! 2>/dev/null; do
		sleep 2
		s=$((s + 2))
		if grep -q "^RESULT " "$log.log" 2>/dev/null; then
			done_at=${done_at:-$s}
			((s - done_at < 30)) || { note="NOTE $jet $names: still running 30 s after its RESULT, stopped"; pkill -KILL -f "odot --log-file $log.log" || true; }
		elif ((s > limit)); then
			note="FAIL $jet $names: no RESULT after $limit s, stopped"
			pkill -KILL -f "odot --log-file $log.log" || true
		fi
	done
	{
		grep -E "^(PASS|FAIL) shot|^GUIDE_INFO|SCRIPT ERROR" "$log.log" || true
		[[ -n $note ]] && echo "$note"
		grep -q "^RESULT " "$log.log" || [[ $note == FAIL* ]] || echo "FAIL $jet $names: Godot ended without a RESULT line ($log.log)"
	} >"$log.out"
	# Every failure line names its process's log.
	sed -i.bak -E "/^FAIL|SCRIPT ERROR/s|\$| [log: $log.log]|" "$log.out" && rm -f "$log.out.bak"
	# The stamp (up to date, see below) only for a shot that passed every check.
	for n in ${names//,/ }; do
		if [[ -f $shots_dir/$jet/$n.png ]] && grep -q "^PASS shot $n " "$log.out" && ! grep -q "^FAIL shot $n:" "$log.out"; then
			cp "$logs/$jet/$n.stamp" "$shots_dir/$jet/$n.stamp"
		else
			rm -f "$shots_dir/$jet/$n.stamp"
		fi
	done
	cat "$log.out"
	exit 0
fi
# Godot logs go here, not into the player's user folder (whose rotation keeps only the newest logs); kept only when
# something failed, and each failed process's log is named at the end.
logs=$PWD/assets/logs/guide-shots-$(date +%Y-%m-%d-%H%M%S)-$$
mkdir -p "$logs"
only=""
force=0
jets=()
while (($#)); do
	case $1 in
		--only) only=$2; shift 2 ;;
		--force) force=1; shift ;;
		*) jets+=("$1"); shift ;;
	esac
done
if ((${#jets[@]} == 0)); then
	for f in docs/guides/*.shots.json; do jets+=("$(basename "$f" .shots.json)"); done
fi
shots_dir=${GUIDE_SHOTS_DIR:-$PWD/assets/converted/guides/shots}
batch=${GUIDE_BATCH:-4}
jobs=${GUIDE_JOBS:-}
if [[ -z $jobs ]]; then
	# ponytail: 2 GB per process is the measured peak (≈1.1 GB RSS) plus room; set GUIDE_JOBS where the GPU is the limit.
	cores=$(getconf _NPROCESSORS_ONLN)
	if [[ -r /proc/meminfo ]]; then
		free_gb=$(awk '/^MemAvailable:/ { print int($2 / 1048576) }' /proc/meminfo)
	else
		free_gb=$(($(sysctl -n hw.memsize) / 2147483648))  # macOS: half the RAM
	fi
	jobs=$((cores / 2 < free_gb / 2 ? cores / 2 : free_gb / 2))
	((jobs >= 1)) || jobs=1
fi
# Which shots to render: a shot is up to date when its picture's stamp (<name>.stamp beside it) matches its inputs: its
# entry, the shot tools (this script, godot_window.sh, tests/godot/_guide_shots.gd), Godot's version, the frame size
# and the data (assets/install and assets/converted, every file's path and size; the guides' own output and hidden
# work folders left out). Game code changes do not re-render (so setup runs again without rendering): --force does.
# One line per process: <jet> <name,name,…>; each shot's new stamp waits in $logs/<jet>/<name>.stamp.
python3 -I - "$logs" "$shots_dir" "$only" "$batch" "${GUIDE_FORCE:-$force}" "${jets[@]}" <<'EOF' >"$logs/jobs"
import hashlib, json, os, subprocess, sys
logs, shots_dir, only, batch, force, *jets = sys.argv[1:]
h = hashlib.sha256()
for f in ["tools/guide_shots.sh", "tools/godot_window.sh", "tests/godot/_guide_shots.gd"]:
    h.update(f.encode() + open(f, "rb").read())
h.update(subprocess.run(["godot", "--version"], capture_output=True).stdout + (os.environ.get("GUIDE_SIZE") or "3840x2160").encode())
for top in ("assets/install", "assets/converted"):
    for d, dirs, files in os.walk(top, followlinks=True):
        dirs[:] = sorted(x for x in dirs if not x.startswith(".") and os.path.join(d, x) != "assets/converted/guides")
        for f in sorted(files):
            # ponytail: path and size, not the time, so identical regenerated data keeps the pictures; a same-size
            # change goes unseen (--force).
            h.update(f"{d}/{f} {os.path.getsize(os.path.join(d, f))}\n".encode())
build = h.hexdigest()
for jet in jets:
    names = []
    for e in json.load(open(f"docs/guides/{jet}.shots.json")):
        if only and e["name"] not in only.split(","):
            continue
        stamp = hashlib.sha256((build + json.dumps(e, sort_keys=True)).encode()).hexdigest()
        out = os.path.join(shots_dir, jet, e["name"])
        try:
            fresh = os.path.isfile(out + ".png") and open(out + ".stamp").read() == stamp
        except OSError:
            fresh = False
        if fresh and force != "1":
            print(f"up to date: {jet}/{e['name']}", file=sys.stderr)
            continue
        os.makedirs(os.path.join(logs, jet), exist_ok=True)
        open(os.path.join(logs, jet, e["name"] + ".stamp"), "w").write(stamp)
        names.append(e["name"])
    for i in range(0, len(names), int(batch)):
        print(jet, ",".join(names[i:i + int(batch)]))
EOF
echo "guide shots: $(wc -l <"$logs/jobs" | tr -d ' ') processes, $jobs at once, into $shots_dir"
export logs shots_dir
[[ ! -s $logs/jobs ]] || xargs -P "$jobs" -L 1 tools/guide_shots.sh --job <"$logs/jobs"
fails=$(cat "$logs"/*.out 2>/dev/null | grep -cE "^FAIL|SCRIPT ERROR" || true)
if ((fails > 0)); then
	echo "guide shots: $fails failures; the failed processes' Godot logs:"
	for o in "$logs"/*.out; do
		grep -qE "^FAIL|SCRIPT ERROR" "$o" && echo "  ${o%.out}.log"
	done
	exit 1
fi
rm -rf "$logs"  # kept above only when something failed
echo "guide shots: done"

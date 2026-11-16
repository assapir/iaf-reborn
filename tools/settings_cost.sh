#!/usr/bin/env bash
# The Settings' cost chips (modern-iaf/docs/front-end.md §14.1): the GPU time of each graphics choice on this computer,
# written to modern-iaf/data/settings/cost.json. One flight bench per run (modern-iaf/tests/_flight_bench.gd:
# ramon_takeoff held over Tel Aviv at 500 m for 12 s once the ground has streamed in, the cockpit view, VSync off, the
# random draws seeded so the cloud layer is the same). Each choice that differs from the preset High is run after a run
# of High. The High runs spread over a few ms (the integrated GPU shares its power with whatever else runs), so each
# choice's cost is its run's average GPU time minus the median of all the High runs, and the noise is half their
# spread (the largest minus the smallest). High's own choices cost 0, a cheaper choice is negative. Each row lists its
# plain choice first (Off, Native, MSAA 4x, Flat layer, the lowest terrain detail): the chip's reference. Each run
# waits for the GPU lock, so parallel sessions take turns.
#   tools/settings_cost.sh [log folder]      (about 20 minutes on the Iris Xe laptop)
set -euo pipefail
cd "$(dirname "$0")/.."
logs=${1:-$(mktemp -d)}
mkdir -p "$logs"
high="antialiasing=msaa4,upscaling=off,shadows=true,shadow_reach=far,terrain_detail=1.0,clouds=original,scenery=on"
choices=(antialiasing=msaa4_fxaa antialiasing=taa antialiasing=temporal upscaling=quality upscaling=balanced
	shadows=false shadow_reach=original terrain_detail=0.5 terrain_detail=0.75 clouds=volumetric scenery=off
	scenery=detailed)
i=0
## One bench run with High plus `$1` (nothing: High alone); prints its average GPU time (ms).
run() {
	local set_=$high log="$logs/cost_${2}.log"
	[[ -n $1 ]] && set_="$high,$1"
	flock ~/.cache/iaf-gpu-bench.lock timeout -k 10 600 tools/godot_window.sh IAF_DEFAULT_SETTINGS=1 \
		BENCH_SEED=7 BENCH_AT=668000,3550689 BENCH_LEGS=500:0:12 "BENCH_SET=blackbox=false,$set_" -- --log-file "$log" \
		--path modern-iaf --resolution 1920x1080 -s ../modern-iaf/tests/_flight_bench.gd >/dev/null 2>&1 || true
	local gpu
	gpu=$(grep FLIGHT "$log" | grep -o 'gpu *[0-9.]*' | head -1 | grep -o '[0-9.]*$' || true)
	[[ -n $gpu ]] || { echo "no result for '$1' (log $log)" >&2; exit 1; }
	echo "$gpu"
}
out=()
for c in "${choices[@]}"; do
	a=$(run "" "$i")
	b=$(run "$c" "$((i + 1))")
	i=$((i + 2))
	echo "$c: high $a ms, with it $b ms"
	out+=("$c=$a=$b")
done
python3 -I - "${out[@]}" <<'EOF'
import json, sys, datetime, statistics
pairs = []
for a in sys.argv[1:]:
    key, choice, high, ms = a.split("=")
    pairs.append((key, choice, float(high), float(ms)))
highs = [p[2] for p in pairs]
base = statistics.median(highs)
plain = {"antialiasing": "msaa4", "upscaling": "off", "shadows": False, "shadow_reach": "original", "clouds": "original",
         "scenery": "off", "terrain_detail": 0.5}
picks = {"antialiasing": "msaa4", "upscaling": "off", "shadows": True, "shadow_reach": "far", "terrain_detail": 1.0,
         "clouds": "original", "scenery": "on"}
rows = {k: [[v, 0.0]] for k, v in picks.items()}
for key, choice, high, ms in pairs:
    val = {"true": True, "false": False}.get(choice, choice)
    if key == "terrain_detail":
        val = float(choice)
    rows[key].append([val, round(ms - base, 2)])
# Each row's plain choice first (the chip's reference, front_end.gd chip_cost), terrain detail by its value.
for k in rows:
    rows[k].sort(key=lambda p: p[0] if k == "terrain_detail" else p[0] != plain[k])
out = {"measured": datetime.date.today().isoformat(), "computer": "Intel Iris Xe laptop (Linux), 1920 x 1080 window",
       "base_ms": round(base, 2), "noise_ms": round((max(highs) - min(highs)) / 2, 2), "rows": rows}
with open("modern-iaf/data/settings/cost.json", "w") as f:
    f.write(json.dumps(out, separators=(",", ":")) + "\n")
print(json.dumps(out))
EOF

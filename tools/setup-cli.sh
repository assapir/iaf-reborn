#!/usr/bin/env bash
# One-shot setup: build everything the game needs from your own copy of Jane's IAF.
#
#   tools/setup-cli.sh [--patch /path/to/v1.1-patch.exe] [--hebrew-iso IAF.Iso] "/path/to/Jane's IAF.iso" [Brief.zip] [Menu.zip]
#
# --patch (or the IAF_PATCH environment variable) is the official v1.1 update: the downloaded
# WinZip self-extractor, iafp1_1.exe or a bare patch file (docs/formats/rtpatch.md). It is applied to
# the extracted install before anything is converted, so every later step reads v1.1 data; without
# it the install stays v1.0, which the engine also plays (docs/v1.1.md "v1.0 data compatibility").
# Brief.zip / Menu.zip are the optional Hebrew briefings and menus packs (see docs/packs.md); they
# overlay the (patched) English files. --hebrew-iso (or IAF_HEBREW_ISO) is the Hebrew retail CD (v1.0): the
# three Hebrew images the packs lack (the startup splash and the Graphics page) are taken from it.
# --imagery <source>[,<source>…] (off by default) adds modern terrain imagery (docs/imagery.md, README
# "Terrain imagery data"): sentinel2 = ESA WorldCover 2021 Sentinel-2 outside Israel, fetched and
# converted (needs GDAL; ~28 GB of range reads, ~2.5 GB on disk); mapi2015 / mapi2015-bases = the Survey of
# Israel 2015 2 m sheets (all / around the airbases), downloaded with curl and Firefox's data.gov.il
# token, else through your browser (tools/imagery/fetch-mapi2015-curl.sh), then converted into the
# Israel layers (needs GDAL; re-run after adding sheets: only the 20 km units they touch are redone). Without the ISO argument only the imagery steps run
# (on an install set up before).
# --scenery (off by default) adds buildings and trees over the Survey 2 m layer (docs/scenery.md); --scenery=buildings
# or --scenery=trees makes only that kind. The sources the kinds need (pinned; both 520 MB, buildings 373 MB, trees
# 267 MB) are downloaded into assets/source/scenery, then the cells are made (needs GDAL and the mapi2015 layer).
# Without the ISO argument it runs on an install set up before.
# IAF_IMAGERY_MIRROR=user@host:/path/to/repo restores a missing assets/converted/imagery (and the sheets) with rsync;
# the parts of it that older rules wrote (e.g. the airbases' old rectangles) are then converted again.
# Safe to re-run: each step overwrites its own output under assets/.
set -euo pipefail
cd "$(dirname "$0")/.."

usage='usage: tools/setup-cli.sh [--patch <v1.1 patch>] [--hebrew-iso <Hebrew CD>] [--imagery sentinel2,mapi2015,mapi2015-bases] [--scenery[=buildings|trees]] ["/path/to/Jane'"'"'s IAF.iso" [Brief.zip] [Menu.zip]]'
patch=${IAF_PATCH:-}
imagery=
scenery=
hebrew_iso=${IAF_HEBREW_ISO:-}
args=()
while (($#)); do
	case $1 in
		--patch) patch=${2:?$usage}; shift 2 ;;
		--patch=*) patch=${1#--patch=}; shift ;;
		--hebrew-iso) hebrew_iso=${2:?$usage}; shift 2 ;;
		--hebrew-iso=*) hebrew_iso=${1#--hebrew-iso=}; shift ;;
		--imagery) imagery=${2:?$usage}; shift 2 ;;
		--imagery=*) imagery=${1#--imagery=}; shift ;;
		--scenery) scenery=both; shift ;;
		--scenery=*) scenery=${1#--scenery=}; [[ $scenery =~ ^(both|buildings|trees)$ ]] || { echo "$usage"; exit 1; }; shift ;;
		-h|--help) echo "$usage"; exit 0 ;;
		*) args+=("$1"); shift ;;
	esac
done
[[ ${#args[@]} -gt 0 || -n $imagery || -n $scenery ]] || { echo "$usage"; exit 1; }
iso=${args[0]:-}
hebrew_zip=${args[1]:-}
hebrew_menu_zip=${args[2]:-}
for src in ${imagery//,/ }; do
	[[ $src =~ ^(sentinel2|mapi2015|mapi2015-bases)$ ]] || { echo "unknown imagery source '$src' (sentinel2, mapi2015, mapi2015-bases)"; exit 1; }
done

step() { printf '\n==> %s\n' "$*"; }

# Guard: assets/ must be a real folder (or a worktree's link to one). A link to itself (a committed worktree symlink
# merged into the main checkout wiped assets/ on 2026-10-16) would make every step write nowhere.
if [[ -L assets && ! -d assets/ ]]; then
	echo "assets is a broken symlink ($(readlink assets)): remove it (rm assets) and run setup again"; exit 1
fi
# Imagery mirror (optional): IAF_IMAGERY_MIRROR=user@host:/path/to/repo copies a converted imagery set back (rsync)
# instead of re-downloading it, e.g. after assets/ was lost; then the --imagery steps only redo what is missing.
if [[ -n ${IAF_IMAGERY_MIRROR:-} && ! -d assets/converted/imagery ]]; then
	step "imagery: restore from $IAF_IMAGERY_MIRROR (rsync)"
	mkdir -p assets/converted assets/source
	rsync -a "$IAF_IMAGERY_MIRROR/assets/converted/imagery" assets/converted/ &&
		rsync -a "$IAF_IMAGERY_MIRROR/assets/source/imagery" assets/source/ 2>/dev/null || true
	restored=1
fi

# After a restore: the work units whose resume mark holds older rules (or no rules tag, on an airbase) are converted
# again (iaf-imagery --stale; docs/imagery.md §2, step 7). Needs the theatre, so after the base setup.
imagery_refresh() {
	[[ ${restored:-} == 1 && -f assets/converted/terrain/theatre/meta.json ]] || return 0
	command -v gdal_translate >/dev/null || { echo "GDAL is needed to bring the restored imagery up to date (README: prerequisites)"; return 0; }
	step "imagery: convert again what the restored copy holds from older rules"
	cargo build --release -p iaf-tools
	if [[ -d assets/converted/imagery/mapi2015 && -d assets/source/imagery/mapi2015 ]]; then
		./target/release/iaf-imagery mapi2015 assets/install assets/converted/terrain/theatre assets/converted/imagery --stale \
			--threads "$(( $(nproc) > 2 ? $(nproc) - 2 : 1 ))"
	elif [[ -d assets/converted/imagery/mapi2015 ]]; then
		echo "WARNING: the Survey sheets were not restored, so these mapi2015 units keep older rules (e.g. an airbase's old rectangle):"
		./target/release/iaf-imagery mapi2015 assets/install assets/converted/terrain/theatre assets/converted/imagery --dry-run | grep "convert again" || true
	fi
	if [[ -d assets/converted/imagery/sentinel2 ]]; then
		./target/release/iaf-imagery sentinel2 assets/install assets/converted/terrain/theatre assets/converted/imagery --stale ||
			echo "WARNING: sentinel2 units with older rules could not be converted again (it reads WorldCover over the network); re-run tools/setup-cli.sh --imagery sentinel2"
	fi
	restored=
}

# Modern terrain imagery (--imagery): after the base setup, or alone on an install set up before.
imagery_steps() {
	for src in ${imagery//,/ }; do
		case $src in
			sentinel2)
				step "imagery: Sentinel-2 outside Israel (ESA WorldCover 2021, CC BY 4.0; GDAL range reads, resumable)"
				command -v gdal_translate >/dev/null || { echo "GDAL is needed (README: prerequisites)"; exit 1; }
				[[ -f assets/converted/terrain/theatre/meta.json ]] || { echo "run the base setup (with the ISO) first"; exit 1; }
				cargo build --release -p iaf-tools
				./target/release/iaf-imagery sentinel2 assets/install assets/converted/terrain/theatre assets/converted/imagery --dry-run
				# A ~28 GB fetch: asked on a terminal; without one only with IAF_IMAGERY_YES=1.
				if [[ -t 0 ]]; then
					read -rp "fetch and convert now? [y/N] " a
					[[ $a == [yY]* ]] || { echo "skipped"; continue; }
				elif [[ ${IAF_IMAGERY_YES:-} != 1 ]]; then
					echo "not a terminal: skipped (set IAF_IMAGERY_YES=1 to fetch without asking)"; continue
				fi
				./target/release/iaf-imagery sentinel2 assets/install assets/converted/terrain/theatre assets/converted/imagery
				;;
			mapi2015|mapi2015-bases)
				step "imagery: Survey of Israel 2015 2 m sheets (data.gov.il)"
				tools/imagery/fetch-mapi2015-curl.sh $([[ $src == mapi2015-bases ]] && echo --bases)
				step "imagery: Survey of Israel 2015 2 m layer from the downloaded sheets (resumable, incremental)"
				command -v gdal_translate >/dev/null || { echo "GDAL is needed (README: prerequisites)"; exit 1; }
				[[ -f assets/converted/terrain/theatre/meta.json ]] || { echo "run the base setup (with the ISO) first"; exit 1; }
				cargo build --release -p iaf-tools
				./target/release/iaf-imagery mapi2015 assets/install assets/converted/terrain/theatre assets/converted/imagery --dry-run
				# About an hour of CPU for all of Israel: asked on a terminal; without one only with IAF_IMAGERY_YES=1.
				if [[ -t 0 ]]; then
					read -rp "convert now? [y/N] " a
					[[ $a == [yY]* ]] || { echo "skipped"; continue; }
				elif [[ ${IAF_IMAGERY_YES:-} != 1 ]]; then
					echo "not a terminal: skipped (set IAF_IMAGERY_YES=1 to convert without asking)"; continue
				fi
				./target/release/iaf-imagery mapi2015 assets/install assets/converted/terrain/theatre assets/converted/imagery \
					--threads "$(( $(nproc) > 2 ? $(nproc) - 2 : 1 ))"
				;;
		esac
	done
}

# Scenery (--scenery): after the imagery, or alone on an install set up before.
scenery_steps() {
	step "scenery: sources for $scenery (OpenStreetMap; Microsoft footprints and GHSL heights for buildings, ETH canopy for trees; pinned)"
	cargo build --release -p iaf-tools
	./target/release/iaf-scenery fetch assets --kinds "$scenery" ||
		{ echo "WARNING: the scenery's sources could not be fetched (offline?): Scenery stays off; run setup again online"; return 0; }
	step "scenery: cells ($scenery) over the Survey 2 m layer"
	command -v gdalwarp >/dev/null || { echo "GDAL is needed (README: prerequisites)"; return 0; }
	[[ -d assets/converted/imagery/mapi2015/L1 ]] || { echo "Scenery needs the Survey 2 m layer: run with --imagery mapi2015 first"; return 0; }
	./target/release/iaf-scenery build assets --kinds "$scenery"
}

if [[ -z $iso ]]; then
	imagery_refresh
	[[ -n $imagery ]] && imagery_steps
	[[ -n $scenery ]] && scenery_steps
	step "done"
	exit 0
fi

step "building tools"
cargo build --release -p iaf-tools

# Files a previous run overlaid from the v1.1 patch: removed first, so the extraction below brings back
# the v1.0 ones and files only v1.1 has do not linger in an unpatched install.
manifest=assets/install/.v1.1-files
if [[ -f $manifest ]]; then
	while IFS= read -r f; do rm -f "assets/install/$f"; done < "$manifest"
	rm -f "$manifest"
fi
rm -rf assets/v1.0

step "extracting the original install from the CD image"
./target/release/iaf-extract "$iso" assets/install

if [[ -n $patch ]]; then
	step "v1.1 patch (41 files; the v1.0 originals are kept in assets/v1.0)"
	./target/release/iaf-patch unwrap "$patch" assets/patch/iafp1_1.exe
	rm -rf assets/v1.1
	./target/release/iaf-patch apply assets/patch/iafp1_1.exe assets/install assets/v1.1
	(cd assets/v1.1 && find . -type f | sed 's|^\./||') | sort > "$manifest.new"
	while IFS= read -r f; do
		if [[ -f assets/install/$f ]]; then
			mkdir -p "assets/v1.0/$(dirname "$f")"
			cp "assets/install/$f" "assets/v1.0/$f"
		fi
	done < "$manifest.new"
	cp -r assets/v1.1/. assets/install/
	mv "$manifest.new" "$manifest"
fi

# The conversions below run as parallel jobs: each one only waits for the steps whose output it reads (`needs`).
# Each job writes its own log; the logs are printed in this order as the jobs end, and the first failure stops the
# setup with its log.
jobs_dir=$(mktemp -d "${TMPDIR:-/tmp}/iaf-setup.XXXXXX")
trap 'rm -rf "$jobs_dir" assets/hebrew-cd assets/hebrew-cd-pick' EXIT  # a failed job's log is printed before the exit
job_names=() job_pids=()
job() {  # job NAME FUNCTION: runs FUNCTION in the background (set -e), its output into its log
	local n=$1
	( trap 'echo $? >"$jobs_dir/$n.rc"' EXIT; set -e; "$2" ) >"$jobs_dir/$n.log" 2>&1 &
	job_names+=("$n") job_pids+=($!)
}
needs() {  # inside a job: waits for the other job NAME; fails if it failed
	while [[ ! -f $jobs_dir/$1.rc ]]; do sleep 0.5; done
	[[ $(<"$jobs_dir/$1.rc") == 0 ]] || { echo "needs '$1', which failed"; return 1; }
}
wait_jobs() {
	local i
	for i in "${!job_names[@]}"; do
		if wait "${job_pids[$i]}"; then
			cat "$jobs_dir/${job_names[$i]}.log"
		else
			cat "$jobs_dir/${job_names[$i]}.log"
			echo "SETUP FAILED in '${job_names[$i]}' (its log is above)"
			for p in "${job_pids[@]}"; do pkill -P "$p" 2>/dev/null || true; kill "$p" 2>/dev/null || true; done
			exit 1
		fi
	done
}

j_fonts() {
	step "original HUD / MFD fonts"
	./target/release/iaf-convert fonts assets/install assets/converted/fonts
}

j_cockpits() {
	step "cockpits (art and layout, every aircraft)"
	local c pids=()
	for c in f16 f15 f4-2000 phantom cfir lavi mirage mig23 mig29; do
		./target/release/iaf-convert --upscale cockpit assets/install "$c" "assets/converted/cockpits/$c" &
		pids+=($!)
	done
	for c in "${pids[@]}"; do wait "$c"; done
}

j_hebrew() {
	local pack f
	for pack in "$hebrew_zip" "$hebrew_menu_zip"; do
		[[ -n "$pack" ]] || continue
		step "Hebrew pack $(basename "$pack")"
		./target/release/iaf-import-pack "$pack" he assets/install assets/packs
	done
	if [[ -n $hebrew_iso ]]; then
		# Every other Hebrew file on the CD is already in Brief.zip / Menu.zip; these three the Hebrew v1.1 patch
		# turned back into the English ones. The Graphics page lacks v1.1's 32MB / 48MB slider labels.
		step "Hebrew CD: startup splash and Graphics page"
		rm -rf assets/hebrew-cd assets/hebrew-cd-pick
		./target/release/iaf-extract "$hebrew_iso" assets/hebrew-cd >/dev/null
		for f in bmp/back0.bmp bmp/pref/graph_0.bmp bmp/pref/graph_1.bmp; do
			mkdir -p "assets/hebrew-cd-pick/menu/$(dirname "$f")"
			cp "assets/hebrew-cd/resource/menu/$f" "assets/hebrew-cd-pick/menu/$f"
		done
		./target/release/iaf-import-pack assets/hebrew-cd-pick he assets/install assets/packs
		rm -rf assets/hebrew-cd assets/hebrew-cd-pick
	fi
}

j_briefings() {
	needs hebrew
	step "briefings (English + Hebrew pack when imported)"
	./target/release/iaf-convert --upscale briefings assets/install assets/packs assets/converted/briefings
}

j_reference() {
	step "Reference screen (refers.ref records, descriptions, pictures)"
	./target/release/iaf-convert --upscale reference assets/install assets/converted/reference
}

j_menu() {
	step "front-end menus (screens, strings, art, fonts)"
	./target/release/iaf-convert --upscale menu assets/install assets/converted/menu
}

j_menu_he() {
	needs hebrew
	if [[ -d assets/packs/he/resource/menu ]]; then
		step "front-end menus in Hebrew (the Hebrew pack over the English menus)"
		./target/release/iaf-convert --upscale menu assets/install assets/converted/menu_he --pack assets/packs/he
	fi
}

# Extra planes' arming art (docs/adding-a-plane.md §5): composed from the original arming art of the menus and the
# plane's front view (game/extra/planes/<p>/arm).
j_arm() {
	needs menu
	needs menu_he
	step "extra planes' arming art"
	local arm p m
	for arm in game/extra/planes/*/arm; do
		p=$(basename "$(dirname "$arm")")
		for m in assets/converted/menu assets/converted/menu_he; do
			if [[ -d $m/img/arm/jets ]]; then
				./target/release/iaf-convert arm-extra "$m/img" "$arm" "$m/img/arm/jets/x_$p.png"
			fi
		done
	done
}

j_keys() {
	needs hebrew
	step "key table (default keys from the exe + keys.trx labels, docs/controls.md)"
	./target/release/iaf-convert keys assets/install assets/packs assets/converted/keys.json
}

j_missions() {
	step "missions (all .mis + object database -> JSON, mission list)"
	./target/release/iaf-convert missions assets/install assets/converted/missions
}

j_aircraft() {
	needs missions
	step "aircraft: every plane's model (glTF, Lanczos textures, smoothed) + descriptor (docs/aircraft.md)"
	./target/release/iaf-convert --upscale --smooth aircraft assets/install assets/converted/missions assets/converted/planes
}

j_objects() {
	needs missions
	step "mission object models (every model the object database references)"
	./target/release/iaf-convert --upscale --smooth objects assets/install assets/converted/missions assets/converted/objects
}

j_theatre() {
	step "terrain: every level and inset of map.ptt as a node quadtree (docs/formats/ptt.md, ~30 s, ~730 MB)"
	rm -rf assets/converted/terrain/israel_l4  # the old Israel-only layout
	./target/release/iaf-terrain theatre assets/install/resource/terrain/map.ptt assets/converted/terrain/theatre
}

j_airbases() {
	needs theatre
	step "airbases: runways, taxi paths and paved surface from the 1998 art and iaf.ibx (docs/rendering.md §7, ~30 s)"
	./target/release/iaf-terrain airbases assets/install assets/converted/terrain/theatre assets/converted/terrain
}

j_godot() {
	step "Godot extension (flight model)"
	cargo build --release -p iaf-godot
}

j_icon() {
	step "icon and desktop launcher (the original icon from iafjets.exe)"
	./target/release/iaf-convert icon assets/install assets/converted/icon.png
	tools/install-launcher.sh
}
j_textures() {  # optional: a failure (offline) only leaves Graphics → MORE → Ground textures / Model detail on Original
	step "textures: ambientCG CC0 materials for Ground textures and Model detail (download, about 310 MB; docs/credits.md)"
	./target/release/iaf-textures assets/thirdparty/ambientcg ||
		echo "WARNING: the ambientCG textures could not be fetched (offline?): Ground textures and Model detail stay Original; run setup again online"
}

for j in fonts cockpits hebrew briefings reference menu menu_he arm keys missions aircraft objects theatre airbases \
	godot icon textures; do
	job "$j" "j_$j"
done
wait_jobs

imagery_refresh
[[ -n $imagery ]] && imagery_steps
[[ -n $scenery ]] && scenery_steps

# The pilot guides' pictures and PDFs (docs/guides; the Reference screen's Pilot guide view): real renders, so only
# with a display; they hold the original art and stay under assets/. After the imagery so the pictures show it.
step "pilot guides: pictures (tools/guide_shots.sh) and PDFs (tools/guide_pdf.py)"
if [[ $(uname) == Darwin && -z ${SSH_CONNECTION:-} ]] || [[ -n ${DISPLAY:-}${WAYLAND_DISPLAY:-} ]]; then
	[[ -d game/.godot ]] || godot --headless --path game --import >/dev/null 2>&1 || true
	tools/guide_shots.sh || echo "pilot guides: some pictures failed their checks (listed above); the PDFs use what was made"
	python3 -I tools/guide_pdf.py
else
	echo "no display: skipped (run tools/guide_shots.sh and python3 -I tools/guide_pdf.py from a desktop session)"
fi

step "done — run: ./iafjets (or the \"Jane's IAF (reborn)\" launcher)"

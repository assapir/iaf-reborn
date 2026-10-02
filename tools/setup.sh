#!/usr/bin/env bash
# One-shot setup: build everything the game needs from your own copy of Jane's IAF.
#
#   tools/setup.sh [--patch /path/to/v1.1-patch.exe] [--hebrew-iso IAF.Iso] "/path/to/Jane's IAF.iso" [Brief.zip] [Menu.zip]
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
# converted (needs GDAL; ~28 GB of range reads, ~6 GB on disk); mapi2015 / mapi2015-bases = the Survey of
# Israel 2015 2 m sheets (all / around the airbases), downloaded through your browser
# (tools/imagery/fetch-mapi2015.sh), then converted into the Israel layers (needs GDAL; re-run after adding
# sheets: only the 20 km units they touch are redone). Without the ISO argument only the imagery steps run
# (on an install set up before).
# Safe to re-run: each step overwrites its own output under assets/.
set -euo pipefail
cd "$(dirname "$0")/.."

usage='usage: tools/setup.sh [--patch <v1.1 patch>] [--hebrew-iso <Hebrew CD>] [--imagery sentinel2,mapi2015,mapi2015-bases] ["/path/to/Jane'"'"'s IAF.iso" [Brief.zip] [Menu.zip]]'
patch=${IAF_PATCH:-}
imagery=
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
		-h|--help) echo "$usage"; exit 0 ;;
		*) args+=("$1"); shift ;;
	esac
done
[[ ${#args[@]} -gt 0 || -n $imagery ]] || { echo "$usage"; exit 1; }
iso=${args[0]:-}
hebrew_zip=${args[1]:-}
hebrew_menu_zip=${args[2]:-}
for src in ${imagery//,/ }; do
	[[ $src =~ ^(sentinel2|mapi2015|mapi2015-bases)$ ]] || { echo "unknown imagery source '$src' (sentinel2, mapi2015, mapi2015-bases)"; exit 1; }
done

step() { printf '\n==> %s\n' "$*"; }

# Modern terrain imagery (--imagery): after the base setup, or alone on an install set up before.
imagery_steps() {
	for src in ${imagery//,/ }; do
		case $src in
			sentinel2)
				step "imagery: Sentinel-2 outside Israel (ESA WorldCover 2021, CC BY 4.0; GDAL range reads, resumable)"
				command -v gdal_translate >/dev/null || { echo "GDAL is needed (README: prerequisites)"; exit 1; }
				[[ -f assets/converted/terrain/theatre/meta.json ]] || { echo "run the base setup (with the ISO) first"; exit 1; }
				cargo build -q --release -p iaf-tools
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
				step "imagery: Survey of Israel 2015 2 m sheets (data.gov.il, through your browser)"
				tools/imagery/fetch-mapi2015.sh $([[ $src == mapi2015-bases ]] && echo --bases)
				step "imagery: Survey of Israel 2015 2 m layer from the downloaded sheets (resumable, incremental)"
				command -v gdal_translate >/dev/null || { echo "GDAL is needed (README: prerequisites)"; exit 1; }
				[[ -f assets/converted/terrain/theatre/meta.json ]] || { echo "run the base setup (with the ISO) first"; exit 1; }
				cargo build -q --release -p iaf-tools
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

if [[ -z $iso ]]; then
	imagery_steps
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

step "original HUD / MFD fonts"
./target/release/iaf-convert fonts assets/install assets/converted/fonts

step "cockpits (art and layout, every aircraft)"
for c in f16 f15 f4-2000 phantom cfir lavi mirage mig23 mig29; do
	./target/release/iaf-convert --upscale cockpit assets/install "$c" "assets/converted/cockpits/$c"
done

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

step "briefings (English + Hebrew pack when imported)"
./target/release/iaf-convert --upscale briefings assets/install assets/packs assets/converted/briefings

step "front-end menus (screens, strings, art, fonts)"
./target/release/iaf-convert --upscale menu assets/install assets/converted/menu
if [[ -d assets/packs/he/resource/menu ]]; then
	./target/release/iaf-convert --upscale menu assets/install assets/converted/menu_he --pack assets/packs/he
fi
# Extra planes' arming art (docs/adding-a-plane.md §5): composed from the original arming art above and the plane's
# front view (game/extra/planes/<p>/arm).
for arm in game/extra/planes/*/arm; do
	p=$(basename "$(dirname "$arm")")
	for m in assets/converted/menu assets/converted/menu_he; do
		[[ -d $m/img/arm/jets ]] && ./target/release/iaf-convert arm-extra "$m/img" "$arm" "$m/img/arm/jets/x_$p.png"
	done
done

step "key table (default keys from the exe + keys.trx labels, docs/controls.md)"
./target/release/iaf-convert keys assets/install assets/packs assets/converted/keys.json

step "missions (all .mis + object database -> JSON, mission list)"
./target/release/iaf-convert missions assets/install assets/converted/missions

step "aircraft: every plane's model (glTF, Lanczos textures, smoothed) + descriptor (docs/aircraft.md)"
./target/release/iaf-convert --upscale --smooth aircraft assets/install assets/converted/missions assets/converted/planes

step "mission object models (every model the object database references)"
./target/release/iaf-convert --upscale --smooth objects assets/install assets/converted/missions assets/converted/objects

step "terrain: every level and inset of map.ptt as a node quadtree (docs/formats/ptt.md, ~30 s, ~730 MB)"
rm -rf assets/converted/terrain/israel_l4  # the old Israel-only layout
./target/release/iaf-terrain theatre assets/install/resource/terrain/map.ptt assets/converted/terrain/theatre

step "Godot extension (flight model)"
cargo build --release -p iaf-godot

step "icon and desktop launcher (the original icon from iafjets.exe)"
./target/release/iaf-convert icon assets/install assets/converted/icon.png
tools/install-launcher.sh

[[ -n $imagery ]] && imagery_steps

step "done — run: ./iafjets (or the \"Jane's IAF (reborn)\" launcher)"

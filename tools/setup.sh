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
# Safe to re-run: each step overwrites its own output under assets/.
set -euo pipefail
cd "$(dirname "$0")/.."

usage='usage: tools/setup.sh [--patch <v1.1 patch>] [--hebrew-iso <Hebrew CD>] "/path/to/Jane'"'"'s IAF.iso" [Brief.zip] [Menu.zip]'
patch=${IAF_PATCH:-}
hebrew_iso=${IAF_HEBREW_ISO:-}
args=()
while (($#)); do
	case $1 in
		--patch) patch=${2:?$usage}; shift 2 ;;
		--patch=*) patch=${1#--patch=}; shift ;;
		--hebrew-iso) hebrew_iso=${2:?$usage}; shift 2 ;;
		--hebrew-iso=*) hebrew_iso=${1#--hebrew-iso=}; shift ;;
		-h|--help) echo "$usage"; exit 0 ;;
		*) args+=("$1"); shift ;;
	esac
done
iso=${args[0]:?$usage}
hebrew_zip=${args[1]:-}
hebrew_menu_zip=${args[2]:-}

step() { printf '\n==> %s\n' "$*"; }

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

step "done — run: ./iafjets (or the \"Jane's IAF (reborn)\" launcher)"

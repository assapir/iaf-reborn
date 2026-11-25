#!/usr/bin/env bash
# One game's release bundle for this OS (docs/release.md), from a checkout whose extension is built
# (target/release/libiaf_godot.*) and whose project is imported (godot --headless --path <project> --import):
#   tools/release/bundle.sh <modern-iaf|iaf-reborn> <out dir>
# Writes <out dir>/<project>-nightly-<linux-x86_64.tar.gz|windows-x86_64.zip|macos-arm64.dmg> and prints its path.
# The game's version: $IAF_VERSION, else tools/release/versions.txt's line + -nightly.$IAF_NIGHTLY (default
# <date>+<hash>: the nightly workflow passes one for all bundles, which manifest.sh lists).
# Needs Godot (GODOT, default godot) with its export templates; on macOS codesign and hdiutil, on Windows 7z.
# $IAF_TOOLS: a folder made by tools/release/tools_env.sh (GDAL and curl for setup), copied in as tools/.
# The export bakes the shaders into the .pck (Godot's shader baker, docs/release.md "Baked shaders"): it needs a
# rendering device, so it runs without --headless (on Linux under xvfb-run, with Mesa's software Vulkan where no GPU
# is). Where no device starts it exports again headless, unbaked, with a warning. $IAF_BAKE=0: headless, unbaked.
# On macOS it imports the project again with ETC2 / ASTC textures (Apple silicon's) and leaves that import in its
# .godot folder: run `godot --headless --path <project> --import` after it in a checkout you play from.
set -euo pipefail
cd "$(dirname "$0")/../.."
project=${1:?usage: tools/release/bundle.sh <modern-iaf|iaf-reborn> <out dir>}
out=$(mkdir -p "${2:?out dir}" && cd "$2" && pwd)
godot=${GODOT:-godot}
case $project in
modern-iaf)
	name="Modern IAF"
	# What setup and the game read by path (Settings.disk_path, Settings.app_root): copied beside the game.
	files=(modern-iaf/data modern-iaf/branding modern-iaf/manuals/manuals.json modern-iaf/manuals/pdf shared/extra)
	;;
iaf-reborn)
	name="IAF Reborn"
	files=(iaf-reborn/setup/icon.png shared/extra docs/guides)
	;;
*) echo "unknown project: $project" >&2; exit 2 ;;
esac
base=$(awk -v p="$project" '$1 == p {print $2}' tools/release/versions.txt)
version=${IAF_VERSION:-$base-nightly.${IAF_NIGHTLY:-$(date -u +%Y%m%d)+$(git rev-parse --short HEAD)}}
case $(uname -s) in
Linux) os=linux preset=Linux ext=tar.gz arch=x86_64 ;;
Darwin) os=macos preset=macOS ext=dmg arch=arm64 ;;
MINGW* | MSYS* | CYGWIN*) os=windows preset=Windows ext=zip arch=x86_64 ;;
*) echo "unknown OS: $(uname -s)" >&2; exit 2 ;;
esac
stage=$(mktemp -d)
keep=$(mktemp)
cp "$project/project.godot" "$keep"
trap 'cp "$keep" "$project/project.godot"; rm -rf "$stage" "$keep"' EXIT
# The version the front ends show (Settings.version), in the exported project only (put back on exit).
sed -i.bak "s|^config/version=.*|config/version=\"$version\"|" "$project/project.godot" && rm "$project/project.godot.bak"
echo "$project $version: exporting for $os"
# export_game <out file>: the export, baked when it can be; baked() tells from the .pck's file list.
baked() { grep -aqE 'shader_cache/[^ ]*\.(vulkan|metal|d3d12)\.cache' "$1" 2>/dev/null; }
export_game() {
	if [[ ${IAF_BAKE:-1} == 1 ]]; then
		local run=("$godot") to
		[[ $os == linux ]] && run=(xvfb-run -a "$godot" --display-driver x11)
		# A hung windowed export falls through to the headless one after 30 minutes.
		to=$(command -v timeout || command -v gtimeout || true)
		[[ -n $to ]] && run=("$to" 1800 "${run[@]}")
		"${run[@]}" --audio-driver Dummy --path "$project" --export-release "$preset" "$1" || true
		local pck=${1%.*}.pck ok=0
		[[ $os == macos && -s $1 ]] && unzip -p "$1" '*.pck' >"$pck" || true
		[[ -s $1 ]] && baked "$pck" && ok=1
		[[ $os == macos ]] && rm -f "$pck"
		if ((ok)); then
			echo "$project: shaders baked"
			return
		fi
		echo "::warning::$project ($os): no rendering device for the shader baker; this bundle compiles its shaders on the first start"
	fi
	"$godot" --headless --path "$project" --export-release "$preset" "$1"
}
if [[ $os == macos ]]; then
	# Apple silicon needs the ETC2 / ASTC textures: imported for this export only (the checkout imports S3TC / BPTC).
	awk '{print} /^\[rendering\]$/ {print "textures/vram_compression/import_etc2_astc=true"}' "$keep" >"$project/project.godot"
	sed -i.bak "s|^config/version=.*|config/version=\"$version\"|" "$project/project.godot" && rm "$project/project.godot.bak"
	"$godot" --headless --path "$project" --import
	export_game "$stage/app.zip"
	(cd "$stage" && unzip -q app.zip && rm app.zip)
	app=$(ls -d "$stage"/*.app)
	[[ $(basename "$app") == "$name.app" ]] || mv "$app" "$stage/$name.app"
	app="$stage/$name.app"
	root="$app/Contents/Resources"
else
	mkdir -p "$stage/$name"
	exe="$name.x86_64"
	[[ $os == windows ]] && exe="$name.exe"
	export_game "$stage/$name/$exe"
	root="$stage/$name"
fi
for f in "${files[@]}"; do
	mkdir -p "$root/$(dirname "$f")"
	cp -RL "$f" "$root/$f"
done
cp LICENSE docs/credits.md "$root/"
# The licences of the fonts built into the game library (the pilot guide PDFs, docs/credits.md).
mkdir -p "$root/licenses"
cp crates/iaf-tools/fonts/LICENSE-*.txt "$root/licenses/"
# Setup's outside programs (GDAL, curl), made by tools/release/tools_env.sh: the nightly passes them in $IAF_TOOLS.
if [[ -n ${IAF_TOOLS:-} ]]; then
	cp -R "$IAF_TOOLS" "$root/tools"
fi
file="$out/$project-nightly-$os-$arch.$ext"
rm -f "$file"
case $os in
linux)
	printf '#!/bin/sh\n# The setup wizard again (to add an extra or redo a step).\nexec "$(dirname "$0")/%s" --setup "$@"\n' "$exe" >"$root/setup"
	chmod +x "$root/setup" "$root/$exe"
	tar -C "$stage" -czf "$file" "$name"
	;;
windows)
	printf '@rem The setup wizard again (to add an extra or redo a step).\r\n@start "" "%%~dp0%s" --setup\r\n' "$exe" >"$root/Setup.cmd"
	(cd "$stage" && 7z a -tzip -bso0 "$(cygpath -w "$file")" "$name")
	;;
macos)
	# Unsigned (the user, 23 Nov 2026): an ad-hoc signature only, which Apple silicon needs to run the code at all.
	codesign --force --deep --sign - "$app"
	sed "s/<the game>/$name/g" tools/release/macos-readme.txt >"$stage/Read me first.txt"
	ln -s /Applications "$stage/Applications"
	# hdiutil fails now and then on CI's Macs ("Resource busy"): up to three tries.
	for try in 1 2 3; do
		hdiutil create -volname "$name" -srcfolder "$stage" -ov -format UDZO "$file" && break
		[[ $try == 3 ]] && exit 1
		sleep 10
	done
	;;
esac
echo "$file"

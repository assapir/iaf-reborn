#!/usr/bin/env bash
# CI only (docs/ci.md): installs the official Godot $GODOT_VERSION build for this runner and puts `godot` on the PATH.
# `tools/ci_install_godot.sh templates`: also this OS's export templates (the nightly's bundles, docs/release.md);
# $GODOT_TEMPLATES_TPZ names an already downloaded templates file (the workflow's cache).
set -euo pipefail
case "$RUNNER_OS" in
	Linux) zip=linux.x86_64.zip exe=Godot_v${GODOT_VERSION}_linux.x86_64 ;;
	macOS) zip=macos.universal.zip exe=Godot.app/Contents/MacOS/Godot ;;
	Windows) zip=win64.exe.zip exe=Godot_v${GODOT_VERSION}_win64_console.exe ;;
esac
dir="$RUNNER_TEMP/godot"
mkdir -p "$dir/bin"
curl -fsSL -o "$dir/godot.zip" \
	"https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_${zip}"
unzip -q "$dir/godot.zip" -d "$dir"
# A script, not a copy or link: the Windows console exe finds the main exe by its own name.
printf '#!/usr/bin/env bash\nexec "%s" "$@"\n' "$(cygpath -u "$dir/$exe" 2>/dev/null || echo "$dir/$exe")" >"$dir/bin/godot"
chmod +x "$dir/bin/godot"
echo "$dir/bin" >>"$GITHUB_PATH"

[[ ${1:-} == templates ]] || exit 0
case "$RUNNER_OS" in
	Linux) tdir=~/.local/share/godot/export_templates pick='linux_*x86_64' ;;
	macOS) tdir=~/"Library/Application Support/Godot/export_templates" pick='macos.zip' ;;
	Windows) tdir="$(cygpath -u "$APPDATA")/Godot/export_templates" pick='windows_*x86_64*' ;;
esac
tpz=${GODOT_TEMPLATES_TPZ:-$dir/templates.tpz}
[[ -s $tpz ]] || curl -fsSL -o "$tpz" \
	"https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_export_templates.tpz"
mkdir -p "$tdir/${GODOT_VERSION/-/.}"
unzip -q -j -o "$tpz" "templates/version.txt" "templates/$pick" -d "$tdir/${GODOT_VERSION/-/.}"

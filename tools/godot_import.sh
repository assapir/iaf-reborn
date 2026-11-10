#!/usr/bin/env bash
# Runs Godot's import when a project (default iaf-reborn; modern-iaf for ./start-modern-iaf) needs it, before the game or setup
# starts (./iafjets, ./setup, setup-cli.sh, ./start-modern-iaf):
#   - a fresh clone (no <project>/.godot/extension_list.cfg): Godot loads iaf.gdextension only once an import has listed it;
#   - a pull that brought new or changed imported files (a shader, a texture): their .import file or the file itself
#     is newer than the last import (<project>/.godot/.iaf_imported). Without it the game finds no imported copy
#     ("Cannot open file 'res://.godot/imported/…'"), e.g. the volumetric clouds' compute shaders.
# Usage: tools/godot_import.sh <godot binary> [project folder]
set -euo pipefail
cd "$(dirname "$0")/.."
project=${2:-iaf-reborn}
stamp=$project/.godot/.iaf_imported
need=0
if [[ ! -f $project/.godot/extension_list.cfg || ! -f $stamp ]]; then
	need=1
else
	while IFS= read -r f; do
		if [[ $f -nt $stamp || ${f%.import} -nt $stamp ]]; then
			need=1
			break
		fi
	done < <(find -L "$project" -path "$project/.godot" -prune -o -name '*.import' -print)
fi
((need)) || exit 0
echo "importing the game's new or changed files (shaders, textures)…"
"$1" --headless --path "$project" --import >/dev/null 2>&1 || true
touch "$stamp"

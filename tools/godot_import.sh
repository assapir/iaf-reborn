#!/usr/bin/env bash
# Runs Godot's import when the project needs it, before the game or setup starts (./iafjets, ./setup, setup-cli.sh):
#   - a fresh clone (no game/.godot/extension_list.cfg): Godot loads iaf.gdextension only once an import has listed it;
#   - a pull that brought new or changed imported files (a shader, a texture): their .import file or the file itself
#     is newer than the last import (game/.godot/.iaf_imported). Without it the game finds no imported copy
#     ("Cannot open file 'res://.godot/imported/…'"), e.g. the volumetric clouds' compute shaders.
# Usage: tools/godot_import.sh <godot binary>
set -euo pipefail
cd "$(dirname "$0")/.."
stamp=game/.godot/.iaf_imported
need=0
if [[ ! -f game/.godot/extension_list.cfg || ! -f $stamp ]]; then
	need=1
else
	while IFS= read -r f; do
		if [[ $f -nt $stamp || ${f%.import} -nt $stamp ]]; then
			need=1
			break
		fi
	done < <(find game -path game/.godot -prune -o -name '*.import' -print)
fi
((need)) || exit 0
echo "importing the game's new or changed files (shaders, textures)…"
"$1" --headless --path game --import >/dev/null 2>&1 || true
touch "$stamp"

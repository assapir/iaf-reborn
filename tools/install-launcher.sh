#!/usr/bin/env bash
# Desktop launcher (Linux): ~/.local/share/applications/iaf-reborn.desktop running ./iafjets with the original
# icon (assets/converted/icon.png, extracted from iafjets.exe). The file name matches the game window's app id
# (iaf-reborn), which is how GNOME / KDE pick the window icon. Run by tools/setup.sh; safe to re-run.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname)" == Linux ]] || exit 0
root=$(pwd)
apps=${XDG_DATA_HOME:-$HOME/.local/share}/applications
mkdir -p "$apps"
cat > "$apps/iaf-reborn.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Jane's IAF (iaf-reborn)
Comment=Jane's IAF: Israeli Air Force (1998) on a new engine
Exec="$root/iafjets"
Path=$root
Icon=$root/assets/converted/icon.png
Terminal=false
Categories=Game;Simulation;
StartupWMClass=iaf-reborn
DESKTOP
command -v update-desktop-database >/dev/null && update-desktop-database "$apps" 2>/dev/null || true
echo "launcher: $apps/iaf-reborn.desktop"

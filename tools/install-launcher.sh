#!/usr/bin/env bash
# Desktop launcher running ./iafjets with the original icon (assets/converted/icon.png, extracted from iafjets.exe).
# Linux: ~/.local/share/applications/iaf-reborn.desktop; the file name matches the game window's app id
# (iaf-reborn), which is how GNOME / KDE pick the window icon.
# macOS: ~/Applications/Jane's IAF (reborn).app, a bundle whose executable runs ./iafjets.
# Run by tools/setup.sh; safe to re-run.
set -euo pipefail
cd "$(dirname "$0")/.."
root=$(pwd)
if [[ "$(uname)" == Darwin ]]; then
	app="$HOME/Applications/Jane's IAF (reborn).app"
	rm -rf "$app"
	mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
	cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key><string>Jane's IAF (reborn)</string>
	<key>CFBundleIdentifier</key><string>org.iaf-reborn.launcher</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleExecutable</key><string>iafjets</string>
	<key>CFBundleIconFile</key><string>icon</string>
	<!-- the executable is a script: without this Launch Services runs it (and so Godot) under Rosetta -->
	<key>LSArchitecturePriority</key><array><string>arm64</string><string>x86_64</string></array>
	<key>LSApplicationCategoryType</key><string>public.app-category.simulation-games</string>
</dict>
</plist>
PLIST
	# Finder starts apps with a bare PATH: add where rustup and Homebrew put cargo and godot.
	cat > "$app/Contents/MacOS/iafjets" <<SH
#!/bin/bash
export PATH="\$HOME/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:\$PATH"
exec "$root/iafjets"
SH
	chmod +x "$app/Contents/MacOS/iafjets"
	sips -s format icns "$root/assets/converted/icon.png" --out "$app/Contents/Resources/icon.icns" >/dev/null
	echo "launcher: $app"
	exit 0
fi
[[ "$(uname)" == Linux ]] || exit 0
apps=${XDG_DATA_HOME:-$HOME/.local/share}/applications
mkdir -p "$apps"
cat > "$apps/iaf-reborn.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Jane's IAF (reborn)
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

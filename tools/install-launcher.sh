#!/usr/bin/env bash
# Desktop launchers for one game, per user: tools/install-launcher.sh [iaf-reborn|modern-iaf] [--remove]. Safe to
# re-run; --remove takes the game's launchers away.
# - iaf-reborn (the default; the original game's setup pipeline, its launcher step, docs/setup.md): "Jane's IAF
#   (reborn)" runs ./iafjets, with the original icon (assets/converted/icon.png, extracted from iafjets.exe); "Jane's
#   IAF (reborn) — Setup" runs ./setup (the setup wizard), with ours (iaf-reborn/setup/icon.png: the IAF roundel with
#   "REBORN").
# - modern-iaf (Modern IAF's setup wizard, its Done page, modern-iaf/docs/setup.md "Applications menu"): "Modern IAF" runs
#   ./start-modern-iaf and "Modern IAF — Setup" runs ./modern-iaf-setup, both with the app icon (modern-iaf/branding/,
#   tools/iaf-2026/logo.py).
# Linux: $XDG_DATA_HOME/applications/<id>.desktop (default ~/.local/share). The game's file name matches its window's
# app id (iaf-reborn; Modern IAF's is "Modern IAF", which GNOME reads as modern-iaf), which is how GNOME / KDE pick the
# window icon. Modern IAF's icon goes into the user's hicolor theme ($XDG_DATA_HOME/icons/hicolor).
# macOS: ~/Applications/<name>.app, bundles running the scripts.
# IAF_LAUNCHER_ROOT (the tests): every system's launchers under that one folder instead (its applications/ and icons/,
# its Applications/).
set -euo pipefail
cd "$(dirname "$0")/.."
root=$(pwd)
game=${1:-iaf-reborn}
remove=${2:-}
brand=$root/modern-iaf/branding
# One launcher a line: file id | name | Hebrew name | comment | Hebrew comment | script | macOS bundle id | icon (a
# file, or a hicolor name) | the window's class (the game's own launcher only).
case $game in
iaf-reborn)
	launchers=(
		"iaf-reborn|Jane's IAF (reborn)||Jane's IAF: Israeli Air Force (1998) on a new engine||iafjets|org.iaf-reborn.launcher|$root/assets/converted/icon.png|iaf-reborn"
		"iaf-reborn-setup|Jane's IAF (reborn) — Setup||Set up Jane's IAF (reborn) from your CDs, or add an extra||setup|org.iaf-reborn.setup|$root/iaf-reborn/setup/icon.png|"
	)
	;;
modern-iaf)
	launchers=(
		"modern-iaf|Modern IAF|הזרוע הארוכה|A flight sim of today's Israeli Air Force|סימולטור טיסה של חיל האוויר הישראלי בימינו|start-modern-iaf|org.modern-iaf.launcher|modern-iaf|Modern IAF"
		"modern-iaf-setup|Modern IAF — Setup|הזרוע הארוכה — התקנה|Build or update Modern IAF's data|בנייה ועדכון של נתוני הזרוע הארוכה|modern-iaf-setup|org.modern-iaf.setup|modern-iaf|"
	)
	;;
*)
	echo "usage: tools/install-launcher.sh [iaf-reborn|modern-iaf] [--remove]" >&2
	exit 2
	;;
esac

if [[ "$(uname)" == Darwin ]]; then
	apps=${IAF_LAUNCHER_ROOT:+$IAF_LAUNCHER_ROOT/Applications}
	apps=${apps:-$HOME/Applications}
	for entry in "${launchers[@]}"; do
		IFS='|' read -r _ name _ _ _ script id icon _ <<<"$entry"
		app="$apps/$name.app"
		rm -rf "$app"
		if [[ $remove == --remove ]]; then
			echo "removed: $app"
			continue
		fi
		mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
		cat >"$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key><string>$name</string>
	<key>CFBundleIdentifier</key><string>$id</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleExecutable</key><string>$script</string>
	<key>CFBundleIconFile</key><string>icon</string>
	<!-- the executable is a script: without this Launch Services runs it (and so Godot) under Rosetta -->
	<key>LSArchitecturePriority</key><array><string>arm64</string><string>x86_64</string></array>
	<key>LSApplicationCategoryType</key><string>public.app-category.simulation-games</string>
</dict>
</plist>
PLIST
		# Finder starts apps with a bare PATH: add where rustup and Homebrew put cargo and godot.
		cat >"$app/Contents/MacOS/$script" <<SH
#!/bin/bash
export PATH="\$HOME/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:\$PATH"
exec "$root/$script"
SH
		chmod +x "$app/Contents/MacOS/$script"
		if [[ $icon == /* ]]; then
			sips -s format icns "$icon" --out "$app/Contents/Resources/icon.icns" >/dev/null
		else
			cp "$brand/icon.icns" "$app/Contents/Resources/icon.icns"
		fi
		echo "launcher: $app"
	done
	exit 0
fi
[[ "$(uname)" == Linux ]] || exit 0
data=${IAF_LAUNCHER_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}}
apps=$data/applications
hicolor=$data/icons/hicolor
mkdir -p "$apps"
for entry in "${launchers[@]}"; do
	IFS='|' read -r file name name_he comment comment_he script _ icon class <<<"$entry"
	if [[ $remove == --remove ]]; then
		rm -f "$apps/$file.desktop"
		echo "removed: $apps/$file.desktop"
		continue
	fi
	{
		echo "[Desktop Entry]"
		echo "Type=Application"
		echo "Name=$name"
		[[ -z $name_he ]] || echo "Name[he]=$name_he"
		echo "Comment=$comment"
		[[ -z $comment_he ]] || echo "Comment[he]=$comment_he"
		echo "Exec=\"$root/$script\""
		echo "Path=$root"
		echo "Icon=$icon"
		echo "Terminal=false"
		echo "Categories=Game;Simulation;"
		[[ -z $class ]] || echo "StartupWMClass=$class"
	} >"$apps/$file.desktop"
	echo "launcher: $apps/$file.desktop"
done
# Modern IAF's icon in the hicolor theme: the PNGs (the small ones with bigger jets) and the SVG.
if [[ $game == modern-iaf ]]; then
	icons=("scalable/apps/modern-iaf.svg|icon.svg")
	for px in 16 24 32 48 64 128 256 512; do
		icons+=("${px}x$px/apps/modern-iaf.png|icon_$px.png")
	done
	for i in "${icons[@]}"; do
		f=$hicolor/${i%|*}
		if [[ $remove == --remove ]]; then
			rm -f "$f"
		else
			mkdir -p "${f%/*}" && cp "$brand/${i#*|}" "$f"
		fi
	done
	# A new time on the theme's folder makes GTK look again; a cache that is there already gets the icon too.
	[[ ! -d $hicolor ]] || touch "$hicolor"
	[[ ! -f $hicolor/icon-theme.cache ]] || gtk-update-icon-cache -q "$hicolor" 2>/dev/null || true
fi
command -v update-desktop-database >/dev/null && update-desktop-database "$apps" 2>/dev/null || true

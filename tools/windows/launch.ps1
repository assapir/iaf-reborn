# Windows: what ./setup, ./iafjets, ./mission-editor, ./iaf2026 and ./iaf2026-setup do on Linux and macOS (setup.ps1,
# iafjets.ps1, mission-editor.ps1, iaf2026.ps1 and iaf2026-setup.ps1 call this with their mode). Builds the game's
# extension, imports the Godot project on a fresh clone, then starts the setup wizard (setup), the game (game; without
# game data: the wizard), the mission editor (editor), IAF 2026 (sim; without its data: sim-setup; until its front end,
# item E2, its M0 probe) or IAF 2026's data build (sim-setup: iaf-sim all and terrain, until its wizard, item A3). The arguments
# after the mode go to the game, e.g. .\iafjets.ps1 --mission 311. IAF_SCENE=res://... starts that scene instead of the
# main menu. ASCII only: Windows PowerShell 5.1 reads a script without a BOM as ANSI. No param() block: PowerShell would
# bind game arguments such as -m or -- to its parameters.
$ErrorActionPreference = 'Stop'
$mode = $args[0]
$gameArgs = @($args | Select-Object -Skip 1 | Where-Object { $_ -ne '--' })
Push-Location (Resolve-Path "$PSScriptRoot\..\..")
try {
	function Tell([string]$msg) {
		Add-Type -AssemblyName PresentationFramework
		$title = if ($project -eq 'iaf-2026') { 'IAF 2026' } else { "Jane's IAF (reborn)" }
		[void][System.Windows.MessageBox]::Show($msg, "$title $([char]0x2014) Setup", 'OK', 'Warning')
		throw $msg
	}

	# Godot: $env:GODOT, else godot on PATH, else the newest winget install (winget without admin rights adds no
	# `godot` alias).
	function Find-Godot {
		if ($env:GODOT) { return $env:GODOT }
		foreach ($n in 'godot', 'godot_console') {
			$c = Get-Command $n -ErrorAction SilentlyContinue
			if ($c) { return $c.Source }
		}
		$pkgs = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
		if (Test-Path $pkgs) {
			$exe = Get-ChildItem $pkgs -Directory -Filter 'GodotEngine.GodotEngine*' |
				Get-ChildItem -Filter 'Godot_v*_win64.exe' |
				Where-Object { $_.Name -match '^Godot_v(\d+(\.\d+)+)-' } |
				Sort-Object { [version]($_.Name -replace '^Godot_v(\d+(\.\d+)+)-.*', '$1') } -Descending |
				Select-Object -First 1
			if ($exe) { return $exe.FullName }
		}
		return $null
	}

	# A native program's stderr is no error here (Windows PowerShell 5.1 turns it into one under 'Stop').
	function Native([scriptblock]$run) {
		$ErrorActionPreference = 'Continue'
		& $run
	}

	if ($mode -notin 'setup', 'game', 'editor', 'sim', 'sim-setup') { throw "usage: launch.ps1 setup|game|editor|sim|sim-setup [game arguments]" }
	$project = if ($mode -like 'sim*') { 'iaf-2026' } else { 'iaf-reborn' }
	. "$PSScriptRoot\gdal.ps1"
	$install = 'winget install Rustlang.Rustup GodotEngine.GodotEngine Microsoft.VisualStudio.BuildTools (the C++ workload), then: rustup default stable'
	if ($mode -eq 'game' -and -not (Test-Path 'assets\converted')) {
		Write-Host 'No game data yet: starting the setup wizard.'
		$mode = 'setup'
	}
	if ($mode -eq 'sim' -and -not (Test-Path 'assets\converted\own')) {
		Write-Host 'No IAF 2026 data yet: building it.'
		$mode = 'sim-setup'
	}
	if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
		$cargo = Join-Path $env:USERPROFILE '.cargo\bin'
		if (Test-Path "$cargo\cargo.exe") { $env:Path = "$cargo;$env:Path" } else { Tell "Setup needs Rust (cargo) to build the game. Install it: $install" }
	}
	$godot = Find-Godot
	if (-not $godot) { Tell "Setup needs Godot 4.7. Install it: $install" }
	# The console build next to the GUI one prints to this terminal and waits; the GUI build runs the game.
	$console = $godot -replace '(?<!_console)\.exe$', '_console.exe'
	if (-not (Test-Path $console)) { $console = $godot }
	$version = Native { & $console --version 2>$null }
	if ("$version" -notlike '4.7*') { Tell "Setup needs Godot 4.7 (this one is $version)." }
	# The scripts the game and setup start (the guides) find Godot here.
	$env:GODOT = $godot

	# The project's link to the shared engine folder (a junction on a clone without symlinks).
	& "$PSScriptRoot\links.ps1"
	if ($mode -eq 'setup') { Write-Host "building the game's extension (the first time takes a few minutes)..." }
	Native { cargo build --release -p iaf-godot }
	if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
	if ($mode -eq 'sim-setup') {
		Write-Host "IAF 2026's setup wizard comes with item A3; building the sim's data from the command line (iaf-sim all)..."
		Native { cargo build --release -p iaf-tools --bin iaf-sim }
		if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
		Native { & target\release\iaf-sim.exe all iaf-2026\data assets }
		if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
		# The terrain (iaf-2026/docs/terrain.md): GDAL, downloads, about two hours the first time; resumes.
		Native { & target\release\iaf-sim.exe terrain assets }
		exit $LASTEXITCODE
	}
	# Godot's import (as tools/godot_import.sh): on a fresh clone (Godot loads iaf.gdextension only once an import has
	# listed it in .godot/extension_list.cfg) and after a pull that brought new or changed shaders or textures (an
	# .import file or its source newer than the last import, <project>\.godot\.iaf_imported).
	$stamp = "$project\.godot\.iaf_imported"
	$need = -not (Test-Path "$project\.godot\extension_list.cfg") -or -not (Test-Path $stamp)
	if (-not $need) {
		$since = (Get-Item $stamp).LastWriteTime
		$need = [bool](Get-ChildItem $project, shared -Recurse -Filter *.import -File | Where-Object {
				$_.FullName -notlike '*\.godot\*' -and ($_.LastWriteTime -gt $since -or
					((Test-Path ($_.FullName -replace '\.import$', '')) -and
						(Get-Item ($_.FullName -replace '\.import$', '')).LastWriteTime -gt $since))
			} | Select-Object -First 1)
	}
	if ($need) {
		Write-Host "importing the game's new or changed files (shaders, textures)..."
		Native { & $console --headless --path $project --import *> $null }
		New-Item -ItemType File -Force $stamp | Out-Null
	}

	$godotArgs = @('--path', $project)
	if ($mode -eq 'sim' -and -not (Test-Path 'iaf-2026\main.tscn')) {
		Write-Host "IAF 2026's front end comes with item E2; the M0 probe meanwhile:"
		$env:IAF_DEFAULT_SETTINGS = '1'
		Native { & $console --headless --audio-driver Dummy --path iaf-2026 -s ../iaf-2026/tests/test_m0_boot.gd --log-file ([IO.Path]::GetTempFileName()) }
		exit $LASTEXITCODE
	}
	switch ($mode) {
		'sim' { $godotArgs += 'res://main.tscn' }
		'setup' { $godotArgs += @('--resolution', '1200x820', 'res://setup/wizard.tscn') }
		'editor' { $godotArgs += 'res://editor/mission_editor.tscn' }
		default { if ($env:IAF_SCENE) { $godotArgs += $env:IAF_SCENE } }
	}
	if ($mode -ne 'setup') { $godotArgs += @('--') + $gameArgs }
	& $godot @godotArgs
} finally {
	Pop-Location
}

# Windows: what ./setup, ./iafjets and ./mission-editor do on Linux and macOS (setup.ps1, iafjets.ps1 and
# mission-editor.ps1 call this with their mode). Builds the game's extension, imports the Godot project on a fresh
# clone, then starts the setup wizard (setup), the game (game; without game data: the wizard) or the mission editor
# (editor). The arguments after the mode go to the game, e.g. .\iafjets.ps1 --mission 311. IAF_SCENE=res://... starts
# that scene instead of the main menu. ASCII only: Windows PowerShell 5.1 reads a script without a BOM as ANSI.
# No param() block: PowerShell would bind game arguments such as -m or -- to its parameters.
$ErrorActionPreference = 'Stop'
$mode = $args[0]
$gameArgs = @($args | Select-Object -Skip 1 | Where-Object { $_ -ne '--' })
Push-Location (Resolve-Path "$PSScriptRoot\..\..")
try {
	function Tell([string]$msg) {
		Add-Type -AssemblyName PresentationFramework
		[void][System.Windows.MessageBox]::Show($msg, "Jane's IAF (reborn) $([char]0x2014) Setup", 'OK', 'Warning')
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

	if ($mode -notin 'setup', 'game', 'editor') { throw "usage: launch.ps1 setup|game|editor [game arguments]" }
	. "$PSScriptRoot\gdal.ps1"
	$install = 'winget install Rustlang.Rustup GodotEngine.GodotEngine Microsoft.VisualStudio.BuildTools (the C++ workload), then: rustup default stable'
	if ($mode -eq 'game' -and -not (Test-Path 'assets\converted')) {
		Write-Host 'No game data yet: starting the setup wizard.'
		$mode = 'setup'
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

	if ($mode -eq 'setup') { Write-Host "building the game's extension (the first time takes a few minutes)..." }
	Native { cargo build --release -p iaf-godot }
	if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
	# Godot loads iaf.gdextension only once an import has listed it in .godot/extension_list.cfg (a fresh clone has no
	# game/.godot): without it the mission starts with no flight model and hangs after the briefing.
	if (-not (Test-Path 'game\.godot\extension_list.cfg')) { Native { & $console --headless --path game --import *> $null } }

	$godotArgs = @('--path', 'game')
	switch ($mode) {
		'setup' { $godotArgs += @('--resolution', '1200x820', 'res://setup/wizard.tscn') }
		'editor' { $godotArgs += 'res://editor/mission_editor.tscn' }
		default { if ($env:IAF_SCENE) { $godotArgs += $env:IAF_SCENE } }
	}
	if ($mode -ne 'setup') { $godotArgs += @('--') + $gameArgs }
	& $godot @godotArgs
} finally {
	Pop-Location
}

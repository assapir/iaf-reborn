# Windows: tools/install-launcher.sh's launchers as Start Menu shortcuts. "Jane's IAF (reborn)" runs iafjets.ps1 with
# the original icon (assets/converted/icon.png, extracted from iafjets.exe); "Jane's IAF (reborn) - Setup" runs
# setup.ps1 with ours (game/setup/icon.png). A shortcut's icon must be an .ico: each PNG is wrapped in one (an .ico
# entry may hold a PNG) in assets/converted. Run by setup; safe to re-run. ASCII only: Windows PowerShell 5.1 reads a script
# without a BOM as ANSI.
# -Menu: the folder the shortcuts' folder goes into (default: the user's Start Menu programs; setup's scratch runs
# give one under their XDG_DATA_HOME).
param([string]$Menu = [Environment]::GetFolderPath('Programs'))
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path "$PSScriptRoot\..\..").Path
$menu = Join-Path $Menu "Jane's IAF (reborn)"
New-Item -ItemType Directory -Force $menu | Out-Null

function Ico([string]$png, [string]$ico) {
	$data = [IO.File]::ReadAllBytes($png)
	$w = [BitConverter]::ToInt32([byte[]]($data[19], $data[18], $data[17], $data[16]), 0)  # IHDR width, big-endian
	$h = [BitConverter]::ToInt32([byte[]]($data[23], $data[22], $data[21], $data[20]), 0)
	$out = [IO.BinaryWriter]::new([IO.File]::Create($ico))
	try {
		$out.Write([uint16]0); $out.Write([uint16]1); $out.Write([uint16]1)  # ICONDIR: reserved, type icon, 1 image
		$out.Write([byte]($w % 256)); $out.Write([byte]($h % 256))  # ICONDIRENTRY: 256 is stored as 0
		$out.Write([byte]0); $out.Write([byte]0); $out.Write([uint16]1); $out.Write([uint16]32)
		$out.Write([uint32]$data.Length); $out.Write([uint32]22)
		$out.Write($data)
	} finally { $out.Close() }
}

$shell = New-Object -ComObject WScript.Shell
foreach ($e in @(
		@{ Name = "Jane's IAF (reborn)"; Script = 'iafjets.ps1'; Icon = 'assets\converted\icon.png' },
		@{ Name = "Jane's IAF (reborn) $([char]0x2014) Setup"; Script = 'setup.ps1'; Icon = 'game\setup\icon.png' })) {
	$ico = Join-Path $root "assets\converted\$($e.Script -replace '\.ps1$', '').ico"
	Ico (Join-Path $root $e.Icon) $ico
	$lnk = $shell.CreateShortcut((Join-Path $menu "$($e.Name).lnk"))
	$lnk.TargetPath = Join-Path $PSHOME 'powershell.exe'
	$lnk.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $root $e.Script)`""
	$lnk.WorkingDirectory = $root
	$lnk.IconLocation = $ico
	$lnk.WindowStyle = 7  # minimized: the console only shows the build
	$lnk.Save()
	Write-Output "launcher: $($lnk.FullName)"
}

# Windows: the same as tools/migrate_converted.sh. Moves Modern IAF's built data from assets\converted\iaf-2026 to
# assets\converted\modern-iaf (the project folder's rename of 2026-11-10) and points the setup's stamps there at the
# new data path, so nothing is built or downloaded again. .\modern-iaf-setup.ps1 and .\start-modern-iaf.ps1 do the
# same on their first run. Safe to run again.
#   tools\windows\migrate_converted.ps1 [assets-dir (default: $env:IAF_ASSETS_DIR, else the repo's assets\)]
param([string]$assets = $(if ($env:IAF_ASSETS_DIR) { $env:IAF_ASSETS_DIR } else { Join-Path $PSScriptRoot '..\..\assets' }))
$ErrorActionPreference = 'Stop'
$c = Join-Path $assets 'converted'
$old = Join-Path $c 'iaf-2026'
$new = Join-Path $c 'modern-iaf'
$did = $false
if ((Test-Path $old) -and -not (Test-Path $new)) {
	Move-Item $old $new
	Write-Host "moved $old to $new"
	$did = $true
} elseif (Test-Path $old) {
	Write-Host "both $old and $new exist: kept $new; the old folder can be deleted"
}
if (Test-Path $new) {
	foreach ($s in Get-ChildItem $new -Filter '*.stamp' -File) {
		$t = [IO.File]::ReadAllText($s.FullName)
		if ($t -match '(?m)^input iaf-2026/') {
			[IO.File]::WriteAllText($s.FullName, ($t -replace '(?m)^input iaf-2026/', 'input modern-iaf/'))
			Write-Host "rewrote $($s.FullName)"
			$did = $true
		}
	}
}
if (-not $did) { Write-Host 'nothing to do' }

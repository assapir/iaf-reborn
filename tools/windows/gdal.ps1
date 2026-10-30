# Windows: GDAL for setup's imagery and scenery steps (optional). The winget package (GISInternals.GDAL) installs to
# C:\Program Files\GDAL but puts it on no PATH and sets no data folders; without PROJ_LIB every reprojection fails
# ("Cannot find proj.db"). Dot-sourced by launch.ps1 and setup-cli.ps1: when GDAL is there, this run (and the
# programs it starts) gets its folder on PATH and GDAL_DATA / PROJ_LIB, unless they are set already. ASCII only.
$gdal = Join-Path $env:ProgramFiles 'GDAL'
if (Test-Path (Join-Path $gdal 'gdal_translate.exe')) {
	if (-not (Get-Command gdal_translate -ErrorAction SilentlyContinue)) { $env:Path = "$env:Path;$gdal" }
	if (-not $env:GDAL_DATA -and (Test-Path "$gdal\gdal-data")) { $env:GDAL_DATA = "$gdal\gdal-data" }
	if (-not $env:PROJ_LIB -and (Test-Path "$gdal\projlib")) { $env:PROJ_LIB = "$gdal\projlib" }
}

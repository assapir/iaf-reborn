# Windows: makes each Godot project's link to the shared engine folder (iaf-reborn\shared and iaf-2026\shared -> shared,
# docs/windows.md) a directory junction. Git for Windows checks the committed symlink out as a small text file unless
# symlinks are enabled (core.symlinks with Developer Mode); a junction needs no rights. A real symlink or junction is
# kept. launch.ps1 runs this before every start; run it by hand after a clone to use Godot directly. ASCII only.
$ErrorActionPreference = 'Stop'
$root = Resolve-Path "$PSScriptRoot\..\.."
foreach ($project in 'iaf-reborn', 'iaf-2026') {
	$link = Join-Path $root "$project\shared"
	$item = Get-Item $link -Force -ErrorAction SilentlyContinue
	if ($item -and $item.LinkType) { continue }
	if ($item) { Remove-Item $link -Force }
	New-Item -ItemType Junction -Path $link -Target (Join-Path $root 'shared') | Out-Null
	# Git sees the junction as the committed link changed: it keeps the link as committed.
	git -C $root update-index --skip-worktree "$project/shared"
	Write-Host "linked $project\shared -> shared"
}

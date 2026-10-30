# Windows: tools/setup-cli.sh's setup from PowerShell, through the same pipeline the wizard runs (crates/iaf-setup):
#
#   tools\windows\setup-cli.ps1 [--patch <v1.1 patch>] [--hebrew-iso <Hebrew CD>] [--imagery ...] "<Jane's IAF.iso>" [Brief.zip] [Menu.zip]
#
# Every option of iaf-setup (crates/iaf-setup/src/bin/iaf-setup.rs) works. Re-run it to add an extra or redo a step.
$ErrorActionPreference = 'Stop'
Set-Location (Resolve-Path "$PSScriptRoot\..\..")
cargo run --release -q -p iaf-setup -- @args
exit $LASTEXITCODE

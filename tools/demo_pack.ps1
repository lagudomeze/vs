# Build a standalone demo zip. Uses the same exe with --demo and an isolated save root.
param(
    [string]$Version = "0.1.0"
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$pkg = Join-Path $root ("dist/vx-{0}-win64" -f $Version)
if (-not (Test-Path (Join-Path $pkg "vx.exe"))) {
    Write-Host "package missing; running tools/package.ps1"
    & (Join-Path $PSScriptRoot "package.ps1")
}
if (-not (Test-Path (Join-Path $pkg "vx.exe"))) { throw "vx.exe still missing from $pkg" }

$stage = Join-Path $env:TEMP ("vx-demo-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $stage | Out-Null
try {
    Copy-Item (Join-Path $pkg "*") $stage -Recurse -Force

    $cmd = @(
        "@echo off"
        'start "" "%~dp0vx.exe" --demo'
    ) -join [Environment]::NewLine
    Set-Content -Path (Join-Path $stage "PLAY_DEMO.cmd") -Value $cmd -Encoding ascii

    $readme = @"
VX: AETHER KEEP - DEMO $Version

Run PLAY_DEMO.cmd (or: vx.exe --demo).

- Only floor 1; the run ends at the stairs.
- Demo saves/settings live in %APPDATA%\lagudomeze\vx\demo, separate from the full game.
- F2 settings, H help, F4 copy diagnostics, F3 feedback.
- No telemetry. Death is permanent; R restarts.

Wishlist the full game on Steam.
"@
    Set-Content -Path (Join-Path $stage "DEMO_README.txt") -Value $readme -Encoding utf8

    $outDir = Join-Path $root "dist/demo"
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    $zip = Join-Path $outDir ("vx-demo-{0}.zip" -f $Version)
    if (Test-Path $zip) { Remove-Item $zip -Force }
    & (Join-Path $PSScriptRoot "zip_dir.ps1") -Source $stage -Destination $zip
    Write-Host ("demo package: {0} ({1:N1} MB)" -f $zip, ((Get-Item $zip).Length / 1MB))
}
finally {
    Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
}

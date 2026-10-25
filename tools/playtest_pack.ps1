# Build a self-contained playtest zip from the current dist package.
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

$stage = Join-Path $env:TEMP ("vx-playtest-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $stage | Out-Null
try {
    Copy-Item (Join-Path $pkg "*") $stage -Recurse -Force
    Copy-Item (Join-Path $root "playtest/*") $stage -Recurse -Force

    $outDir = Join-Path $root "dist/playtest"
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    $zip = Join-Path $outDir ("vx-playtest-{0}.zip" -f $Version)
    if (Test-Path $zip) { Remove-Item $zip -Force }
    & (Join-Path $PSScriptRoot "zip_dir.ps1") -Source $stage -Destination $zip
    Write-Host ("playtest package: {0} ({1:N1} MB)" -f $zip, ((Get-Item $zip).Length / 1MB))
}
finally {
    Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
}

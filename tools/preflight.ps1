# One-command release preflight. Fails fast on the first broken gate.
param(
    [switch]$SkipTests,
    [switch]$SkipPackage
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

function Step([string]$name, [scriptblock]$body) {
    Write-Host ""
    Write-Host ("=== " + $name + " ===")
    $global:LASTEXITCODE = 0
    & $body
    if ($LASTEXITCODE -ne 0) {
        throw ("preflight failed: " + $name + " (exit " + $LASTEXITCODE + ")")
    }
}

Step "zig fmt --check" { zig fmt --check src }
if (-not $SkipTests) {
    Step "zig build test" { zig build test }
    Step "zig build test-qa" { zig build test-qa }
    Step "zig build test-qa3" { zig build test-qa3 }
}
if (-not $SkipPackage) {
    Step "package" { & (Join-Path $PSScriptRoot "package.ps1") }
    Step "steam_check" { & (Join-Path $PSScriptRoot "steam_check.ps1") }
    Step "steam_package_check" { & (Join-Path $PSScriptRoot "steam_package_check.ps1") }
    Step "demo_pack" { & (Join-Path $PSScriptRoot "demo_pack.ps1") }
}
Step "deck_check" { & (Join-Path $PSScriptRoot "deck_check.ps1") }
$python = $env:VX_PYTHON
$pyArgs = @()
if (-not $python) {
    $cmd = Get-Command python -ErrorAction SilentlyContinue
    if ($cmd) { $python = $cmd.Source }
}
if (-not $python) {
    $cmd = Get-Command py -ErrorAction SilentlyContinue
    if ($cmd) { $python = $cmd.Source; $pyArgs = @("-3") }
}
if ($python) {
    Step "link check" { & $python @pyArgs (Join-Path $PSScriptRoot "check_links.py") }
    Step "i18n audit" { & $python @pyArgs (Join-Path $PSScriptRoot "i18n_audit.py") --check }
    Step "i18n remaining" { & $python @pyArgs (Join-Path $PSScriptRoot "i18n_visible_audit.py") --check }
    Step "screenshot shrink check" { & $python @pyArgs (Join-Path $PSScriptRoot "shrink_shots.py") --check docs/screenshots }
} else {
    Write-Host "WARN python not found (set VX_PYTHON); skipping i18n/screenshot audits"
}

Write-Host ""
Write-Host "PREFLIGHT PASS"

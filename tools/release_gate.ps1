# One release gate: preflight, packages, Steam checks, artifact hashes.
param(
    [switch]$SkipPreflight,
    [switch]$SkipPackage,
    [switch]$DryRun
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

function Run-Step([string]$Name, [scriptblock]$Body) {
    Write-Host ""
    Write-Host ("=== " + $Name + " ===")
    if ($DryRun) {
        Write-Host ("DRY: " + $Name)
        return
    }
    & $Body
    if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) {
        throw ("step failed: " + $Name + " (exit " + $LASTEXITCODE + ")")
    }
}

if (-not $SkipPreflight) {
    Run-Step "preflight" { & (Join-Path $PSScriptRoot "preflight.ps1") }
}
if (-not $SkipPackage) {
    Run-Step "package" { & (Join-Path $PSScriptRoot "package.ps1") }
    Run-Step "demo_pack" { & (Join-Path $PSScriptRoot "demo_pack.ps1") }
}
Run-Step "playtest_pack" { & (Join-Path $PSScriptRoot "playtest_pack.ps1") }
Run-Step "press_kit" { & (Join-Path $PSScriptRoot "press_kit.ps1") }
Run-Step "steam_check" { & (Join-Path $PSScriptRoot "steam_check.ps1") }
Run-Step "steam_package_check" { & (Join-Path $PSScriptRoot "steam_package_check.ps1") }

$artifacts = @(
    "dist/vx-0.1.0-win64.zip",
    "dist/demo/vx-demo-0.1.0.zip",
    "dist/playtest/vx-playtest-0.1.0.zip"
)
Write-Host ""
Write-Host "=== artifacts ==="
foreach ($rel in $artifacts) {
    $path = Join-Path $root $rel
    if (-not (Test-Path $path)) { throw ("missing artifact: " + $rel) }
    $hash = (Get-FileHash $path -Algorithm SHA256).Hash
    $size = (Get-Item $path).Length
    Write-Host ("{0}  {1} bytes  {2}" -f $rel, $size, $hash)
}

if (-not $DryRun) {
    Write-Host ""
    Write-Host "release gate complete (AppID/DepotID and hardware tests remain manual)"
}

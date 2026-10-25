# Verify deterministic packaging: run the gate twice, compare three artifact hashes.
param(
    [switch]$SkipPreflight
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$artifacts = @(
    "dist/vx-0.1.0-win64.zip",
    "dist/demo/vx-demo-0.1.0.zip",
    "dist/playtest/vx-playtest-0.1.0.zip"
)

function Run-Gate() {
    if ($SkipPreflight) {
        & (Join-Path $PSScriptRoot "release_gate.ps1") -SkipPreflight
    } else {
        & (Join-Path $PSScriptRoot "release_gate.ps1")
    }
    if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) { throw "release gate failed" }
}

function Get-Hashes() {
    $map = [ordered]@{}
    foreach ($rel in $artifacts) {
        $path = Join-Path $root $rel
        if (-not (Test-Path $path)) { throw "missing artifact: $rel" }
        $map[$rel] = (Get-FileHash $path -Algorithm SHA256).Hash
    }
    return $map
}

Run-Gate
$first = Get-Hashes
Run-Gate
$second = Get-Hashes

$failed = $false
foreach ($rel in $artifacts) {
    $same = $first[$rel] -eq $second[$rel]
    Write-Host ("{0}  {1}  {2}" -f $rel, $(if ($same) { "SAME" } else { "DIFF" }), $second[$rel])
    if (-not $same) { $failed = $true }
}
if ($failed) { throw "non-deterministic artifacts detected" }
Write-Host "reproducibility: PASS (two gate runs, identical SHA)"

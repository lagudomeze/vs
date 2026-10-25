param(
    [string]$Version = "0.1.0"
)
$ErrorActionPreference = "Stop"
Set-Location (Split-Path -Parent $PSScriptRoot)

Write-Host "building vx $Version (ReleaseFast)..."
zig build -Doptimize=ReleaseFast

$name = "vx-$Version-win64"
$dist = Join-Path "dist" $name
if (Test-Path $dist) { Remove-Item -Recurse -Force $dist }
New-Item -ItemType Directory -Force -Path $dist | Out-Null

Copy-Item "zig-out/bin/vx.exe" (Join-Path $dist "vx.exe")
Copy-Item "README.md" (Join-Path $dist "README.md")
Copy-Item "CHANGELOG.md" (Join-Path $dist "CHANGELOG.md")
Copy-Item "assets/CREDITS.md" (Join-Path $dist "CREDITS.md")
Copy-Item "assets/fonts/OFL.txt" (Join-Path $dist "OFL.txt")
Set-Content -Path (Join-Path $dist "VERSION.txt") -Value ("vx " + $Version + " / Windows x64")

$zip = Join-Path "dist" "$name.zip"
if (Test-Path $zip) { Remove-Item -Force $zip }
& (Join-Path $PSScriptRoot "zip_dir.ps1") -Source $dist -Destination $zip

$size = (Get-Item $zip).Length
Write-Host ("packaged: {0} ({1:N1} MB)" -f $zip, ($size / 1MB))
Write-Host "contents:"
Get-ChildItem $dist | Select-Object Name,Length | Format-Table -AutoSize

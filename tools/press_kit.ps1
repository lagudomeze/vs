param(
    [string]$Version = "0.1.0"
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$name = "vx-press-kit-$Version"
$outDir = Join-Path $root "dist/press-kit"
$stage = Join-Path $outDir $name
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory -Force -Path $stage | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $stage "screenshots") | Out-Null

Copy-Item "docs/PRESS_KIT.md" (Join-Path $stage "PRESS_KIT.md")
Copy-Item "README.md" (Join-Path $stage "README.md")
Copy-Item "assets/CREDITS.md" (Join-Path $stage "CREDITS.md")
Copy-Item "assets/fonts/OFL.txt" (Join-Path $stage "OFL.txt")
Copy-Item "docs/store/key_art_1920x1080.png" $stage
Copy-Item "docs/store/logo_920x430.png" $stage
Copy-Item "docs/store/library_logo_1280x720.png" $stage
Copy-Item "docs/store/header_capsule_920x430.png" $stage
Copy-Item "docs/store/trailer_30s.mp4" $stage
Copy-Item "docs/store/gameplay_capture_30s.mp4" $stage
Copy-Item "docs/store/trailer_capture_30s.mp4" $stage
Copy-Item "docs/store/screenshots_1920/*.png" (Join-Path $stage "screenshots")

$zip = Join-Path $outDir "$name.zip"
if (Test-Path $zip) { Remove-Item -Force $zip }
Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $zip -CompressionLevel Optimal
Write-Host ("press kit: {0} ({1:N1} MB)" -f $zip, ((Get-Item $zip).Length / 1MB))
Get-ChildItem $stage | Select-Object Name,Length | Format-Table -AutoSize

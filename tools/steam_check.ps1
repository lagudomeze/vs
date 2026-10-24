param(
    [switch]$Build
)
$ErrorActionPreference = "Stop"
Set-Location (Split-Path -Parent $PSScriptRoot)

if ($Build) {
    & (Join-Path $PSScriptRoot "package.ps1")
}

$zip = Get-ChildItem "dist" -Filter "vx-*-win64.zip" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if (-not $zip) {
    throw "no dist/vx-*-win64.zip; run tools/package.ps1 first"
}

$tmp = Join-Path $env:TEMP ("vx-steam-check-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
try {
    Expand-Archive -Path $zip.FullName -DestinationPath $tmp
    $exe = Get-ChildItem $tmp -Recurse -Filter "vx.exe" | Select-Object -First 1
    if (-not $exe) { throw "vx.exe missing from package" }

    $version = (& $exe.FullName --version 2>&1 | Out-String).Trim()
    if ($version -notmatch "^vx ") { throw "unexpected --version output: $version" }

    $leak = Get-ChildItem $tmp -Recurse -Filter "steam_appid.txt" -ErrorAction SilentlyContinue
    if ($leak) { throw "developer steam_appid.txt leaked into package" }

    Write-Host ("package: {0} ({1:N1} MB)" -f $zip.Name, ($zip.Length / 1MB))
    Write-Host ("exe:     {0}" -f $version)
    Write-Host "auto-cloud roots:"
    Write-Host "  WinAppDataRoaming / lagudomeze/vx/saves / *.save / recursive"
    Write-Host "  WinAppDataRoaming / lagudomeze/vx/saves / records.json"
    Write-Host "OK: package is SteamPipe-ready (appid/depot still to fill)"
}
finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

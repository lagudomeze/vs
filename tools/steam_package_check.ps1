# SteamPipe package preflight. Exits 1 on FAIL, 0 otherwise.
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$fail = @()
$warn = @()

$pkg = Get-ChildItem (Join-Path $root "dist") -Directory -Filter "vx-*-win64" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $pkg) {
    $fail += "no dist/vx-*-win64 directory"
} else {
    $exe = Join-Path $pkg.FullName "vx.exe"
    if (-not (Test-Path $exe)) {
        $fail += "vx.exe missing from package root"
    } else {
        Push-Location (Split-Path $exe)
        $raw = (cmd /c ".\vx.exe --version 2>&1" | Out-String).Trim()
        Pop-Location
        $version = ($raw -replace '^.*?:\s*', '')
        if ($version -notmatch "^vx ") { $fail += "unexpected --version: $version" }
        else { Write-Output ("package version: " + $version) }
        $built = Join-Path $root "zig-out/bin/vx.exe"
        if (Test-Path $built) {
            $pkgTime = (Get-Item $exe).LastWriteTime
            $builtTime = (Get-Item $built).LastWriteTime
            if ($builtTime -gt $pkgTime.AddMinutes(1)) {
                $warn += "package is older than zig-out/bin/vx.exe; rerun tools/package.ps1"
            }
        }
    }
    if (Get-ChildItem $pkg.FullName -Recurse -Filter "steam_appid.txt" -ErrorAction SilentlyContinue) {
        $fail += "steam_appid.txt leaked into package"
    }
}

$app = Join-Path $root "steam/app_build.vdf.example"
$depot = Join-Path $root "steam/depot_build.vdf.example"
foreach ($v in @($app, $depot)) {
    if (-not (Test-Path $v)) { $fail += "missing " + (Split-Path -Leaf $v) }
}
if (Test-Path $app) {
    $text = Get-Content -Raw $app
    if ($text -notmatch '"ContentRoot"\s+"\.\./dist/vx-[^"]+-win64"') { $warn += "app_build ContentRoot is not the current package name" }
    if ($text -match "YOUR_APP_ID") { $warn += "app_build still has YOUR_APP_ID (expected until AppID exists)" }
    if ($text -notmatch "depot_build\.vdf") { $fail += "app_build does not reference depot_build.vdf" }
}
if (Test-Path $depot) {
    $dtext = Get-Content -Raw $depot
    if ($dtext -match "YOUR_DEPOT_ID") { $warn += "depot_build still has YOUR_DEPOT_ID (expected until DepotID exists)" }
    if ($dtext -notmatch '"recursive"\s+"1"') { $fail += "depot_build is not recursive" }
    if ($dtext -notmatch "steam_appid\.txt") { $warn += "depot_build does not exclude steam_appid.txt" }
}

if (Test-Path (Join-Path $root "steam_appid.txt")) { $fail += "root steam_appid.txt must not be committed" }

foreach ($w in $warn) { Write-Output ("WARN " + $w) }
foreach ($f in $fail) { Write-Output ("FAIL " + $f) }
if ($fail.Count -gt 0) { Write-Output "steam package preflight: FAIL"; exit 1 }
Write-Output "steam package preflight: PASS (AppID/DepotID/launch options still manual)"

# Static Steam Deck/Proton preflight. File-level only; no hardware claim.
param(
    [string]$Version = "0.1.0"
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$pkg = Join-Path $root ("dist/vx-{0}-win64" -f $Version)
$zip = Join-Path $root ("dist/vx-{0}-win64.zip" -f $Version)
$fail = 0
$warn = 0
function Check($ok, $name, $detail) {
    if ($ok) { Write-Host ("PASS  {0}  {1}" -f $name, $detail) }
    else { Write-Host ("FAIL  {0}  {1}" -f $name, $detail); $script:fail += 1 }
}
function Warn($ok, $name, $detail) {
    if ($ok) { Write-Host ("PASS  {0}  {1}" -f $name, $detail) }
    else { Write-Host ("WARN  {0}  {1}" -f $name, $detail); $script:warn += 1 }
}
Check (Test-Path $pkg) "package" $pkg
if (-not (Test-Path $pkg)) { exit 1 }
Check (Test-Path (Join-Path $pkg "vx.exe")) "exe" "vx.exe"
Warn (Test-Path (Join-Path $pkg "SDL3.dll")) "sdl" "SDL3.dll (static link expected)"
Check (-not (Test-Path (Join-Path $pkg "steam_appid.txt"))) "no-appid" "steam_appid.txt absent"
foreach ($f in @("README.md", "CREDITS.md", "OFL.txt")) {
    Check (Test-Path (Join-Path $pkg $f)) "doc" $f
}
if (Test-Path $zip) {
    $mb = (Get-Item $zip).Length / 1MB
    Warn ($mb -lt 100) "zip-size" ("{0:N1} MB" -f $mb)
} else {
    Warn $false "zip-size" "zip missing"
}
Warn (Test-Path (Join-Path $pkg "assets")) "assets" "assets dir (embedded build has none)"
Write-Host ""
Write-Host ("static preflight: {0} fail, {1} warn" -f $fail, $warn)
Write-Host "NOTE: this is not a Deck/Proton test. See docs/DECK_CHECK.md."
if ($fail -gt 0) { exit 1 }

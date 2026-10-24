# Steam Input template preflight. Exits 1 on FAIL, 0 otherwise.
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$manifest = Join-Path $root "steam/steam_input_manifest.vdf.example"
$fail = @()
$warn = @()

if (-not (Test-Path $manifest)) {
    $fail += "manifest missing: $manifest"
} else {
    $text = Get-Content -Raw $manifest
    $open = ([regex]::Matches($text, '\{')).Count
    $close = ([regex]::Matches($text, '\}')).Count
    if ($open -ne $close) { $fail += "brace mismatch: $open open / $close close" }
    foreach ($action in @("move","confirm","cancel","inventory","character","talent1","talent2","talent3","wait")) {
        if ($text -notmatch ('"' + [regex]::Escape($action) + '"')) { $fail += "missing action: $action" }
    }
    if ($text -notmatch '"schinese"') { $warn += "no schinese localization" }
    if ($text -notmatch '"english"') { $warn += "no english localization" }
}

$appid = Join-Path $root "steam_appid.txt"
if (Test-Path $appid) { $fail += "steam_appid.txt must not be committed" }

if (-not $env:STEAMWORKS_SDK) {
    $warn += "STEAMWORKS_SDK not set (SDK integration still pending)"
} elseif (-not (Test-Path $env:STEAMWORKS_SDK)) {
    $warn += "STEAMWORKS_SDK path does not exist"
}

$exe = Join-Path $root "zig-out/bin/vx.exe"
if (-not (Test-Path $exe)) { $warn += "no zig-out/bin/vx.exe (run zig build first)" }

foreach ($w in $warn) { Write-Output ("WARN " + $w) }
foreach ($f in $fail) { Write-Output ("FAIL " + $f) }
if ($fail.Count -gt 0) { Write-Output "steam input preflight: FAIL"; exit 1 }
Write-Output "steam input preflight: PASS (template not wired; SDL fallback stays)"

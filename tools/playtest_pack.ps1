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

    $readme = @"
VX: AETHER KEEP - PLAYTEST BUILD $Version

1. Unzip this folder anywhere writable.
2. Run vx.exe (no installer).
3. Optional fixed seed: vx.exe --seed 12345
4. Settings: F2. Help: H. Feedback page: F3.
5. Copy diagnostics for a bug report: F4, then paste into the issue.
6. Saves: %APPDATA%\lagudomeze\vx\saves (portable: vx.exe --portable).
7. No telemetry is uploaded. Notes stay with the facilitator unless you post them yourself.
8. If the game does not start, include the error text and your Windows version.

Goal: reach floor 3 and defeat the Abyss Warden. Death is permanent; R restarts.
"@
    Set-Content -Path (Join-Path $stage "PLAYTEST_README.txt") -Value $readme -Encoding utf8

    $consent = @"
PLAYTEST CONSENT (plain language)

- Participation is voluntary; you may stop at any time.
- We record only: build version, seed, class, floor reached, death cause, and your answers.
- Do not share passwords, real names, or other sensitive data.
- We will not record audio/video without asking first.
- Feedback may be summarized in a public issue without your identity.
- Ask the facilitator to delete your notes after the session.
"@
    Set-Content -Path (Join-Path $stage "CONSENT.txt") -Value $consent -Encoding utf8

    $feedback = @"
# Playtest notes (one per tester)

- Tester: (nickname or number)
- Build/seed:
- Class:
- Floor reached:
- Death cause:
- Stuck point:
- Most confusing thing (quote):
- Most satisfying thing (quote):
- Play again? yes/no/maybe
- Wishlist? yes/no/no answer
- Diagnostics (F4 paste):

## Severity
- P0 crash/save loss:
- P1 cannot progress:
- P2 confusing but playable:
- P3 polish:
"@
    Set-Content -Path (Join-Path $stage "FEEDBACK.md") -Value $feedback -Encoding utf8

    $outDir = Join-Path $root "dist/playtest"
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    $zip = Join-Path $outDir ("vx-playtest-{0}.zip" -f $Version)
    if (Test-Path $zip) { Remove-Item $zip -Force }
    Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $zip -CompressionLevel Optimal
    Write-Host ("playtest package: {0} ({1:N1} MB)" -f $zip, ((Get-Item $zip).Length / 1MB))
}
finally {
    Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
}

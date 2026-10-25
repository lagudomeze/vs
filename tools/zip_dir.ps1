# Deterministic zip: sorted entries, fixed 1980 timestamp.
param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Destination
)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$src = (Resolve-Path -LiteralPath $Source).Path.TrimEnd('\', '/')
$dest = [System.IO.Path]::GetFullPath($Destination)
$parent = [System.IO.Path]::GetDirectoryName($dest)
if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Force }

$fixed = [DateTimeOffset]::new(1980, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
$zip = [System.IO.Compression.ZipFile]::Open($dest, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    $files = Get-ChildItem -LiteralPath $src -Recurse -File | Sort-Object FullName
    foreach ($f in $files) {
        $rel = $f.FullName.Substring($src.Length).TrimStart('\', '/').Replace('\', '/')
        $entry = $zip.CreateEntry($rel, [System.IO.Compression.CompressionLevel]::Optimal)
        $entry.LastWriteTime = $fixed
        $input = [System.IO.File]::OpenRead($f.FullName)
        try {
            $output = $entry.Open()
            try { $input.CopyTo($output) } finally { $output.Dispose() }
        } finally { $input.Dispose() }
    }
} finally {
    $zip.Dispose()
}

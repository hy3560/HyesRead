# Package the already verified Windows Release bundle without rebuilding it.
[CmdletBinding()]
param(
    [string]$ArchiveName = 'HyesRead-Flutter-Windows-x64-0.1.0-preview-20261105.zip',
    [string]$BundleDirectory = 'release-bundle',
    [switch]$ValidateOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$project = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$outputRoot = Join-Path $project 'build\windows_portable'
if ([IO.Path]::GetFileName($BundleDirectory) -ne $BundleDirectory -or
    $BundleDirectory -match '[.]{2}') {
    throw 'BundleDirectory must be a single safe directory name.'
}
$bundle = Join-Path $outputRoot $BundleDirectory
$archivePath = Join-Path $outputRoot $ArchiveName

$required = @(
    'HyesRead.exe', 'flutter_windows.dll', 'rive_native.dll',
    'rive_native_plugin.dll', 'url_launcher_windows_plugin.dll',
    'dartjni.dll', 'pdfium.dll', 'data\app.so', 'data\icudtl.dat',
    'data\flutter_assets\AssetManifest.bin'
)
foreach ($relative in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $bundle $relative) -PathType Leaf)) {
        throw "Missing required Windows runtime file: $relative"
    }
}
if ($ValidateOnly) {
    if (-not (Test-Path -LiteralPath $archivePath)) {
        throw "Archive missing for validation: $archivePath"
    }
} else {
    if (Test-Path -LiteralPath $archivePath) {
        throw "Refusing to overwrite an existing Windows preview archive: $archivePath"
    }
    Copy-Item -LiteralPath (Join-Path $project 'WINDOWS_PREVIEW.md') -Destination (Join-Path $bundle 'README-WINDOWS.md') -Force
    Compress-Archive -Path (Join-Path $bundle '*') -DestinationPath $archivePath -CompressionLevel Optimal
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead($archivePath)
try {
    foreach ($relative in $required) {
        $path = $relative.Replace('\', '/')
        $found = @($zip.Entries | Where-Object {
            $_.FullName.Replace('\', '/') -eq $path
        })
        if ($found.Count -ne 1 -or $found[0].Length -le 0) {
            throw "Archive does not contain intact runtime file: $relative"
        }
    }
    # Read every compressed entry to detect truncation, not just list names.
    $buffer = New-Object byte[] 65536
    $checked = 0
    foreach ($entry in $zip.Entries) {
        if ($entry.Name.Length -eq 0) { continue }
        $stream = $entry.Open()
        try {
            $length = 0L
            while (($n = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $length += $n
            }
            if ($length -ne $entry.Length) {
                throw "Archive entry size mismatch: $($entry.FullName)"
            }
            $checked++
        } finally { $stream.Dispose() }
    }
} finally { $zip.Dispose() }

$item = Get-Item -LiteralPath $archivePath
Write-Output "Windows ZIP: $($item.FullName)"
Write-Output "ZIP bytes: $($item.Length)"
Write-Output "ZIP entries fully readable: $checked"
Write-Output "ZIP SHA256: $((Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash)"

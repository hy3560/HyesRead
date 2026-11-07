param(
    [string]$ArchiveName = 'HyesRead-Android-0.1.0-preview.apk'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($ArchiveName -notmatch '^[a-zA-Z0-9_.-]+\.apk$') {
    throw 'ArchiveName must be a simple APK filename.'
}

$project = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$source = Join-Path $project 'build\app\outputs\flutter-apk\app-release.apk'
$destinationFolder = Join-Path $project 'build\android_previews'
$destination = Join-Path $destinationFolder $ArchiveName

if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
    throw 'Release APK not found. Run flutter build apk --release first.'
}
if (Test-Path -LiteralPath $destination) {
    throw 'An APK with this name already exists.'
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead($source)
try {
    $required = @('AndroidManifest.xml', 'classes.dex',
        'lib/arm64-v8a/libflutter.so', 'lib/arm64-v8a/libapp.so')
    foreach ($name in $required) {
        if (-not @($zip.Entries | Where-Object { $_.FullName -eq $name }).Count) {
            throw "Missing APK entry: $name"
        }
    }
    $buffer = New-Object byte[] 65536
    $checked = 0
    foreach ($entry in $zip.Entries) {
        if (-not $entry.Name) { continue }
        $stream = $entry.Open()
        try {
            $length = 0L
            while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $length += $read
            }
            if ($length -ne $entry.Length) {
                throw "Corrupt APK entry: $($entry.FullName)"
            }
            $checked++
        } finally {
            $stream.Dispose()
        }
    }
} finally {
    $zip.Dispose()
}

$sdk = 'D:\3D\AndroidSDK'
$signer = Get-ChildItem -LiteralPath (Join-Path $sdk 'build-tools') -Directory |
    Sort-Object Name -Descending |
    ForEach-Object { Join-Path $_.FullName 'apksigner.bat' } |
    Where-Object { Test-Path -LiteralPath $_ } |
    Select-Object -First 1
if (-not $signer) {
    throw 'Android apksigner not found.'
}
& $signer verify --verbose $source
if ($LASTEXITCODE -ne 0) {
    throw 'Android APK signature verification failed.'
}

New-Item -ItemType Directory -Path $destinationFolder -Force | Out-Null
Copy-Item -LiteralPath $source -Destination $destination
Write-Output "Android APK: $destination"
Write-Output "APK bytes: $((Get-Item -LiteralPath $destination).Length)"
Write-Output "APK entries readable: $checked"
Write-Output "APK SHA256: $((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash)"

# Build the Flutter Windows desktop bundle using already installed MSVC tools.
# No Developer Mode, system registration, or global Visual Studio changes.
# The generated junctions stay under windows/flutter/ephemeral only.
[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release',
    [string]$ArtifactLabel = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$project = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$vsRoot = 'C:\Program Files\Microsoft Visual Studio\2022\Community'
$vcvars = Join-Path $vsRoot 'VC\Auxiliary\Build\vcvars64.bat'
$cmake = Join-Path $vsRoot 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
$ninjaDir = Join-Path $vsRoot 'Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja'
$dartDir = Join-Path $project '.flutter_sdk\bin\cache\dart-sdk\bin'

foreach ($file in @($vcvars, $cmake, (Join-Path $ninjaDir 'ninja.exe'),
        (Join-Path $dartDir 'dart.exe'))) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        throw "Required Windows build tool unavailable: $file"
    }
}

# Flutter's normal build pipeline requires symbolic-link privileges for its
# pub plugin folders. Windows directory junctions work for CMake source
# directories without changing system-wide Developer Mode settings.
$packageFile = Join-Path $project '.dart_tool\package_config.json'
if (-not (Test-Path -LiteralPath $packageFile)) {
    throw 'Missing package_config.json: run Flutter pub get before building.'
}
$packages = (Get-Content -Raw -LiteralPath $packageFile |
    ConvertFrom-Json).packages
$linkRoot = Join-Path $project 'windows\flutter\ephemeral\.plugin_symlinks'
if (-not (Test-Path -LiteralPath $linkRoot)) {
    New-Item -ItemType Directory -Path $linkRoot | Out-Null
}

# Rive's setup command installs binary artifacts in the application's build
# tree, while the plugin CMakeLists expects binaries beside its source. Stage
# a disposable local copy of the Windows plugin so the downloaded binaries
# and CMake source agree; never modify the shared pub cache.
$env:PATH = "$dartDir;$(Join-Path $project '.flutter_sdk\bin');$(Split-Path $cmake);$ninjaDir;$env:PATH"
if ([string]::IsNullOrEmpty($env:APPDATA)) {
    $env:APPDATA = [Environment]::GetFolderPath('ApplicationData')
}
if ([string]::IsNullOrEmpty($env:LOCALAPPDATA)) {
    $env:LOCALAPPDATA = [Environment]::GetFolderPath('LocalApplicationData')
}
if ([string]::IsNullOrEmpty($env:USERPROFILE)) {
    $env:USERPROFILE = [Environment]::GetFolderPath('UserProfile')
}
if ([string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable('PROGRAMFILES(X86)'))) {
    [Environment]::SetEnvironmentVariable('PROGRAMFILES(X86)',
        'C:\Program Files (x86)', 'Process')
}
$riveLibraries = Join-Path $project 'build\rive_native\native\build\windows\bin\lib'
if (-not (Test-Path -LiteralPath (Join-Path $riveLibraries 'release\rive_native.lib'))) {
    Push-Location $project
    try {
        & (Join-Path $dartDir 'dart.exe') run rive_native:setup -p windows
        if ($LASTEXITCODE -ne 0) { throw 'Rive Native Windows setup failed.' }
    } finally { Pop-Location }
}

foreach ($pluginName in @('desktop_drop', 'rive_native', 'url_launcher_windows', 'jni')) {
    $package = @($packages | Where-Object { $_.name -eq $pluginName })
    if ($package.Count -ne 1) {
        throw "Expected exactly one package entry for $pluginName"
    }
    $packageRoot = ([Uri]$package[0].rootUri).LocalPath
    if (-not (Test-Path -LiteralPath (Join-Path $packageRoot 'windows\CMakeLists.txt'))) {
        throw "Missing Windows plugin source: $packageRoot"
    }
    $effectiveRoot = $packageRoot
    if ($pluginName -eq 'rive_native') {
        $effectiveRoot = Join-Path $project 'build\windows_portable\staged_plugins\rive_native'
        $sourceWindows = Join-Path $packageRoot 'windows'
        $stagedWindows = Join-Path $effectiveRoot 'windows'
        if (-not (Test-Path -LiteralPath $stagedWindows)) {
            New-Item -ItemType Directory -Path $stagedWindows -Force | Out-Null
        }
        Copy-Item -Path (Join-Path $sourceWindows '*') -Destination $stagedWindows -Recurse -Force
        # Some Windows headers forward to ../../../native/include in the
        # package root, so stage the matching platform-neutral headers too.
        $sourceHeaders = Join-Path $packageRoot 'native\include'
        $stagedHeaders = Join-Path $effectiveRoot 'native\include'
        if (-not (Test-Path -LiteralPath $sourceHeaders)) {
            throw "Rive Native headers missing: $sourceHeaders"
        }
        if (-not (Test-Path -LiteralPath $stagedHeaders)) {
            New-Item -ItemType Directory -Path $stagedHeaders -Force | Out-Null
        }
        Copy-Item -Path (Join-Path $sourceHeaders '*') -Destination $stagedHeaders -Recurse -Force
        foreach ($mode in @('debug', 'release')) {
            $targetLibDir = Join-Path $stagedWindows "bin\lib\$mode"
            if (-not (Test-Path -LiteralPath $targetLibDir)) {
                New-Item -ItemType Directory -Path $targetLibDir -Force | Out-Null
            }
            foreach ($extension in @('dll', 'lib')) {
                $nativeFile = Join-Path $riveLibraries "$mode\rive_native.$extension"
                if (-not (Test-Path -LiteralPath $nativeFile)) {
                    throw "Missing generated Rive Native library: $nativeFile"
                }
                Copy-Item -LiteralPath $nativeFile -Destination $targetLibDir -Force
            }
        }
        # The upstream CMake plugin invokes 'dart run rive_native:setup'
        # unconditionally on every configure. That can re-download native
        # binaries even though this script has already verified and staged
        # both ABI-matched DLL/import-lib pairs above. Remove only that setup
        # block from the disposable local plugin copy, never the pub source.
        $riveCmake = Join-Path $stagedWindows 'CMakeLists.txt'
        $riveText = [IO.File]::ReadAllText($riveCmake)
        $setupStart = $riveText.IndexOf('execute_process(', [StringComparison]::Ordinal)
        $setupEnd = $riveText.IndexOf('set(PLUGIN_NAME "rive_native_plugin")',
            [StringComparison]::Ordinal)
        if ($setupStart -lt 0 -or $setupEnd -le $setupStart) {
            throw 'Unexpected Rive CMake setup format; refusing to bypass unverified setup.'
        }
        $riveText = $riveText.Substring(0, $setupStart) +
            "message(STATUS `"rive_native: locally verified Windows binaries staged`")`n`n" +
            $riveText.Substring($setupEnd)
        [IO.File]::WriteAllText($riveCmake, $riveText,
            [Text.UTF8Encoding]::new($false))
    }
    $link = Join-Path $linkRoot $pluginName
    if (Test-Path -LiteralPath $link) {
        $existing = Get-Item -LiteralPath $link -Force
        if (-not ($existing.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Refusing to replace non-junction plugin directory: $link"
        }
        $actual = @($existing.Target)[0]
        $matches = [string]::Equals($actual.TrimEnd('\'), $effectiveRoot.TrimEnd('\'),
            [StringComparison]::OrdinalIgnoreCase)
        if ($matches) { continue }
        # Dart's setup task may change the pub cache selected by package_config.
        # Accept a previous junction only if it names the same cached package
        # and version inside a hosted pub cache; never replace arbitrary links.
        $oldPackageName = [IO.Path]::GetFileName($actual.TrimEnd('\'))
        $newPackageName = [IO.Path]::GetFileName($packageRoot.TrimEnd('\'))
        if ($actual -notmatch '(?i)\\Pub\\Cache\\hosted\\pub.dev\\' -or
            -not [string]::Equals($oldPackageName, $newPackageName,
                [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to replace unexpected plugin junction: $link -> $actual"
        }
        # rmdir on a Windows junction only removes the link, never its target.
        & cmd.exe /d /c ('rmdir "{0}"' -f $link)
        if ($LASTEXITCODE -ne 0) { throw "Unable to replace generated junction: $link" }
    }
    New-Item -ItemType Junction -Path $link -Target $effectiveRoot | Out-Null
    Write-Output "Plugin junction: $pluginName"
}

if ([string]::IsNullOrWhiteSpace($ArtifactLabel)) {
    # Preserve the original default output paths for existing workflows.
    $buildDir = Join-Path $project ('build\windows_portable\cmake-' + $Configuration.ToLowerInvariant() + '-x64')
    $bundleDir = Join-Path $project ('build\windows_portable\' + $Configuration.ToLowerInvariant() + '-bundle')
} else {
    if ($ArtifactLabel -notmatch '^[a-z0-9][a-z0-9-]{0,47}$') {
        throw 'ArtifactLabel must contain only lowercase letters, digits, and hyphens.'
    }
    $buildDir = Join-Path $project ('build\windows_portable\cmake-' + $ArtifactLabel + '-' + $Configuration.ToLowerInvariant() + '-x64')
    $bundleDir = Join-Path $project ('build\windows_portable\' + $ArtifactLabel + '-bundle')
    if (Test-Path -LiteralPath $bundleDir) {
        throw "Refusing to overwrite an existing labeled Windows bundle: $bundleDir"
    }
}
# The Flutter backend provides the DLL as an explicit Ninja output, but its
# import library is an implicit link input. Seed that generated import lib
# from the matching SDK engine mode before Ninja checks dependencies.
$engineMode = if ($Configuration -eq 'Release') { 'windows-x64-release' } else { 'windows-x64' }
$engineImportLib = Join-Path $project ".flutter_sdk\bin\cache\artifacts\engine\$engineMode\flutter_windows.dll.lib"
$ephemeralImportLib = Join-Path $project 'windows\flutter\ephemeral\flutter_windows.dll.lib'
if (-not (Test-Path -LiteralPath $engineImportLib -PathType Leaf)) {
    throw "Flutter Windows engine import library missing: $engineImportLib"
}
Copy-Item -LiteralPath $engineImportLib -Destination $ephemeralImportLib -Force

Write-Output "Building Flutter Windows $Configuration using local MSVC + Ninja."
$buildCommands = @(
    ('call "{0}" >nul' -f $vcvars),
    ('"{0}" -S "{1}" -B "{2}" -G Ninja -DCMAKE_BUILD_TYPE={3} -DFLUTTER_TARGET_PLATFORM=windows-x64 -DCMAKE_INSTALL_PREFIX="{4}"' -f $cmake, (Join-Path $project 'windows'), $buildDir, $Configuration, $bundleDir),
    ('"{0}" --build "{1}" --config {2} -j 4' -f $cmake, $buildDir, $Configuration),
    ('"{0}" --install "{1}" --config {2}' -f $cmake, $buildDir, $Configuration)
)
& cmd.exe /d /s /c ($buildCommands -join ' && ')
if ($LASTEXITCODE -ne 0) {
    throw "Windows CMake build failed (exit $LASTEXITCODE)."
}

$exe = Join-Path $bundleDir 'HyesRead.exe'
foreach ($required in @(
        $exe,
        (Join-Path $bundleDir 'flutter_windows.dll'),
        (Join-Path $bundleDir 'desktop_drop_plugin.dll'),
        (Join-Path $bundleDir 'data\icudtl.dat'),
        (Join-Path $bundleDir 'data\flutter_assets\AssetManifest.bin')
    )) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Windows bundle is incomplete: $required"
    }
}
Write-Output "Windows bundle validated: $bundleDir"
Write-Output "EXE SHA256: $((Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash)"

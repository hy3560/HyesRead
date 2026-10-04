param(
  [Parameter(Mandatory)][ValidatePattern('^v\d+\.\d+\.\d+$')][string]$Tag,
  [string]$Destination
)
$ErrorActionPreference = 'Stop'
if (-not $Destination) { $Destination = Join-Path (Split-Path $PSScriptRoot -Parent) "dist/releases/$Tag" }
$releaseDirectory = [IO.Path]::GetFullPath($Destination)
New-Item -ItemType Directory -Path $releaseDirectory -Force | Out-Null
$release = Invoke-RestMethod "https://api.github.com/repos/hy3560/HyesRead/releases/tags/$Tag"
if ($release.draft -or $release.prerelease) { throw 'This is not a final release.' }
$version = $Tag.Substring(1)
$required = @("HyesRead_${version}_x64-setup.exe", 'app-universal-release.apk', 'app-universal-release.aab', 'sbom.spdx.json', 'SHA256SUMS.txt')
$verified = @{}
foreach ($name in $required) {
  $assets = @($release.assets | Where-Object name -eq $name)
  if ($assets.Count -ne 1) { throw "Release asset missing or ambiguous: $name" }
  $asset = $assets[0]
  if ($asset.digest -notmatch '^sha256:([a-fA-F0-9]{64})$') { throw "Release digest is unavailable: $name" }
  $expected = $Matches[1].ToLowerInvariant()
  $target = Join-Path $releaseDirectory $name
  if (-not (Test-Path -LiteralPath $target)) {
    $temporary = Join-Path $releaseDirectory "$name.$([guid]::NewGuid().ToString('N')).part"
    try {
      Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $temporary
      $digest = (Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash.ToLowerInvariant()
      if ($digest -ne $expected) { throw "Downloaded asset digest mismatch: $name" }
      Move-Item -LiteralPath $temporary -Destination $target
    } finally {
      if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary }
    }
  }
  $digest = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($digest -ne $expected) { throw "Existing file does not match the release; preserved without overwrite: $target" }
  if ((Get-Item -LiteralPath $target).Length -ne $asset.size) { throw "Release file size mismatch: $name" }
  $verified[$name] = $digest
}
$manifest = @{}
foreach ($line in Get-Content -LiteralPath (Join-Path $releaseDirectory 'SHA256SUMS.txt')) {
  if ($line -notmatch '^([a-fA-F0-9]{64})\s+\*?(.+)$') { throw 'Malformed release checksum manifest.' }
  $digest = $Matches[1].ToLowerInvariant()
  $name = ($Matches[2] -replace '\\', '/').Split('/')[-1]
  if ($manifest.ContainsKey($name)) { throw "Duplicate checksum entry: $name" }
  $manifest[$name] = $digest
}
foreach ($name in $required | Where-Object { $_ -ne 'SHA256SUMS.txt' }) {
  if ($manifest[$name] -ne $verified[$name]) { throw "Checksum manifest mismatch: $name" }
}
$sbom = Get-Content -LiteralPath (Join-Path $releaseDirectory 'sbom.spdx.json') -Raw | ConvertFrom-Json
if ($sbom.spdxVersion -notlike 'SPDX-*' -or $sbom.packages.Count -eq 0) { throw 'The SPDX SBOM is empty or invalid.' }
$receipt = [ordered]@{ tag = $Tag; releaseUrl = $release.html_url; verifiedAtUtc = [DateTime]::UtcNow.ToString('o'); sha256 = $verified; sbomPackages = $sbom.packages.Count }
$receipt | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $releaseDirectory 'verification.json') -Encoding utf8
$receipt | ConvertTo-Json -Depth 5

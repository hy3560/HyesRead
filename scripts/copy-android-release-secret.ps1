param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('ANDROID_KEY_BASE64', 'ANDROID_KEY_ALIAS', 'ANDROID_KEY_PASSWORD', 'ANDROID_STORE_PASSWORD')]
    [string]$Name
)

$ErrorActionPreference = 'Stop'
$protectedPath = Join-Path $env:LOCALAPPDATA 'HyesRead\android-release\secrets.dpapi'
if (-not (Test-Path -LiteralPath $protectedPath)) {
    throw "Protected Android release Secrets were not found at '$protectedPath'. Run scripts/create-android-release-keystore.ps1 first."
}

$protectedBytes = [IO.File]::ReadAllBytes($protectedPath)
$plainBytes = $null
try {
    $plainBytes = [System.Security.Cryptography.ProtectedData]::Unprotect(
        $protectedBytes,
        $null,
        [System.Security.Cryptography.DataProtectionScope]::CurrentUser
    )
    $manifest = [Text.Encoding]::UTF8.GetString($plainBytes) | ConvertFrom-Json
    $value = [string]$manifest.$Name
    if (-not $value) { throw "The protected value for $Name is empty." }
    Set-Clipboard -Value $value
    Write-Output "Copied $Name to the clipboard. Paste it into the matching GitHub Actions Secret field. The value was not printed."
}
finally {
    [Array]::Clear($protectedBytes, 0, $protectedBytes.Length)
    if ($plainBytes) { [Array]::Clear($plainBytes, 0, $plainBytes.Length) }
    $manifest = $null
    $value = $null
    [GC]::Collect()
}

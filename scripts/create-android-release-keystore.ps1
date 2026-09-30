param(
    [string]$KeytoolPath
)

$ErrorActionPreference = 'Stop'

if (-not $KeytoolPath) {
    if ($env:JAVA_HOME) {
        $candidate = Join-Path $env:JAVA_HOME 'bin\keytool.exe'
        if (Test-Path -LiteralPath $candidate) { $KeytoolPath = $candidate }
    }
    if (-not $KeytoolPath) {
        $command = Get-Command keytool.exe -ErrorAction SilentlyContinue
        if ($command) { $KeytoolPath = $command.Source }
    }
}
if (-not $KeytoolPath -or -not (Test-Path -LiteralPath $KeytoolPath)) {
    throw 'JDK keytool.exe was not found. Install a JDK or pass -KeytoolPath.'
}

$root = Join-Path $env:LOCALAPPDATA 'HyesRead\android-release'
$keystorePath = Join-Path $root 'hyesread-release.jks'
$protectedSecretsPath = Join-Path $root 'secrets.dpapi'
if ((Test-Path -LiteralPath $keystorePath) -or (Test-Path -LiteralPath $protectedSecretsPath)) {
    throw "Android signing files already exist under '$root'. Refusing to overwrite them."
}

New-Item -ItemType Directory -Path $root -Force | Out-Null
$identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
$directoryAcl = [System.Security.AccessControl.DirectorySecurity]::new()
$directoryAcl.SetOwner($identity)
$directoryAcl.SetAccessRuleProtection($true, $false)
$userRule = [System.Security.AccessControl.FileSystemAccessRule]::new(
    $identity,
    [System.Security.AccessControl.FileSystemRights]::FullControl,
    [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit,
    [System.Security.AccessControl.PropagationFlags]::None,
    [System.Security.AccessControl.AccessControlType]::Allow
)
$directoryAcl.AddAccessRule($userRule)
Set-Acl -LiteralPath $root -AclObject $directoryAcl

$randomBytes = [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(48)
$storePassword = [Convert]::ToBase64String($randomBytes).TrimEnd('=').Replace('+', 'A').Replace('/', 'B')
[Array]::Clear($randomBytes, 0, $randomBytes.Length)

$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = $KeytoolPath
$startInfo.Arguments = @(
    '-genkeypair',
    '-keystore', ('"' + $keystorePath + '"'),
    '-storetype', 'JKS',
    '-keyalg', 'RSA',
    '-keysize', '2048',
    '-validity', '10000',
    '-alias', 'hyesread-release',
    '-dname', '"CN=HyesRead Release, OU=HyesRead, O=HyesRead, C=CN"'
) -join ' '
$startInfo.UseShellExecute = $false
$startInfo.CreateNoWindow = $true
$startInfo.RedirectStandardInput = $true
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true

$process = [System.Diagnostics.Process]::new()
$process.StartInfo = $startInfo
try {
    if (-not $process.Start()) { throw 'keytool could not be started.' }
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $process.StandardInput.WriteLine($storePassword)
    $process.StandardInput.WriteLine($storePassword)
    $process.StandardInput.WriteLine('')
    $process.StandardInput.Close()
    $process.WaitForExit()
    $null = $stdoutTask.GetAwaiter().GetResult()
    $null = $stderrTask.GetAwaiter().GetResult()
    if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $keystorePath)) {
        throw "keytool failed with exit code $($process.ExitCode). No password was written to the console."
    }

    $manifest = [ordered]@{
        ANDROID_KEY_BASE64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($keystorePath))
        ANDROID_KEY_ALIAS = 'hyesread-release'
        ANDROID_KEY_PASSWORD = $storePassword
        ANDROID_STORE_PASSWORD = $storePassword
    }
    $plainBytes = [Text.Encoding]::UTF8.GetBytes(($manifest | ConvertTo-Json -Compress))
    try {
        $protectedBytes = [System.Security.Cryptography.ProtectedData]::Protect(
            $plainBytes,
            $null,
            [System.Security.Cryptography.DataProtectionScope]::CurrentUser
        )
        [IO.File]::WriteAllBytes($protectedSecretsPath, $protectedBytes)
        [Array]::Clear($protectedBytes, 0, $protectedBytes.Length)
    }
    finally {
        [Array]::Clear($plainBytes, 0, $plainBytes.Length)
    }
}
catch {
    Remove-Item -LiteralPath $keystorePath, $protectedSecretsPath -Force -ErrorAction SilentlyContinue
    throw
}
finally {
    $process.Dispose()
    $storePassword = $null
    $manifest = $null
    $plainBytes = $null
    $protectedBytes = $null
    [GC]::Collect()
}

Write-Output "Android release keystore created: $keystorePath"
Write-Output "DPAPI-protected GitHub Secrets saved for the current Windows account: $protectedSecretsPath"
Write-Output 'No secret values were printed. Use scripts/copy-android-release-secret.ps1 to copy one value at a time into GitHub Actions Secrets.'

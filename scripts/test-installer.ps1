param(
  [Parameter(Mandatory = $true)]
  [string]$MsiPath
)

$ErrorActionPreference = 'Stop'
$resolvedMsi = (Resolve-Path -LiteralPath $MsiPath).Path
$fixture = (Resolve-Path -LiteralPath 'tests/fixtures/hyesread-acceptance.epub').Path
$uninstallKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
$associationKey = 'HKLM:\SOFTWARE\Classes\HyesRead.epub'
$installRegistryKey = 'HKCU:\Software\hyes\HyesRead'
$installLog = Join-Path ([IO.Path]::GetTempPath()) 'hyesread-msi-install.log'
$uninstallLog = Join-Path ([IO.Path]::GetTempPath()) 'hyesread-msi-uninstall.log'
$appProcess = $null
$productCode = $null
$appPath = $null

function Get-HyesReadUninstallEntry {
  Get-ChildItem -LiteralPath $uninstallKey -ErrorAction SilentlyContinue |
    ForEach-Object { Get-ItemProperty -LiteralPath $_.PSPath } |
    Where-Object { $_.DisplayName -like '*HyesRead*' } |
    Select-Object -First 1
}

try {
  Write-Host 'Installing the Windows MSI on the isolated runner.'
  $install = Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/i', "`"$resolvedMsi`"", '/qn', '/norestart', 'AUTOLAUNCHAPP=', '/l*v', "`"$installLog`"") -Wait -PassThru
  if ($install.ExitCode -notin @(0, 3010)) {
    $details = if (Test-Path -LiteralPath $installLog) { (Get-Content -LiteralPath $installLog -Tail 80) -join "`n" } else { 'No MSI verbose log was created.' }
    throw "MSI installation failed with exit code $($install.ExitCode).`n$details"
  }

  $entry = Get-HyesReadUninstallEntry
  if (-not $entry) {
    $installedApps = Get-ChildItem -LiteralPath $uninstallKey -ErrorAction SilentlyContinue |
      ForEach-Object { Get-ItemProperty -LiteralPath $_.PSPath } |
      Where-Object { $_.DisplayName -match 'Hyes|Read' } |
      ForEach-Object { "$($_.DisplayName) [$($_.PSChildName)]" }
    throw "HyesRead was not registered in the Windows uninstall list. Similar entries: $($installedApps -join '; ')"
  }
  $productCode = [string]$entry.PSChildName
  if ($productCode -notmatch '^\{[0-9A-Fa-f-]{36}\}$') {
    throw "The installed MSI product code is invalid: $productCode"
  }

  $installDirectory = (Get-ItemProperty -LiteralPath $installRegistryKey -Name InstallDir -ErrorAction Stop).InstallDir
  $appPath = Join-Path $installDirectory 'hyes-read.exe'
  if (-not (Test-Path -LiteralPath $appPath -PathType Leaf)) {
    throw "The installed application executable is missing: $appPath"
  }

  if (-not (Test-Path -LiteralPath "$associationKey\shell\open\command")) {
    throw 'The EPUB Open with command was not registered by the installer.'
  }
  foreach ($extension in @('epub', 'mobi', 'azw3', 'kf8', 'pdf', 'cbz', 'txt', 'md', 'fb2', 'fbz')) {
    if (-not (Test-Path -LiteralPath "HKLM:\SOFTWARE\Classes\HyesRead.$extension")) {
      throw "The installer did not register the $extension Open with association."
    }
  }

  Write-Host 'Launching an EPUB through the installed application executable.'
  $appProcess = Start-Process -FilePath $appPath -ArgumentList @("`"$fixture`"") -PassThru
  $deadline = [DateTime]::UtcNow.AddSeconds(20)
  do {
    Start-Sleep -Milliseconds 250
    $appProcess.Refresh()
    if ($appProcess.HasExited) {
      throw "Installed HyesRead exited during startup with code $($appProcess.ExitCode)."
    }
    if ($appProcess.MainWindowHandle -ne [IntPtr]::Zero) { break }
  } while ([DateTime]::UtcNow -lt $deadline)
  if ($appProcess.MainWindowHandle -eq [IntPtr]::Zero) {
    throw 'Installed HyesRead did not create a desktop window.'
  }

  Write-Host 'Installed MSI, executable, window startup, and EPUB Open with registration passed.'
}
finally {
  if ($appProcess) {
    $appProcess.Refresh()
    if (-not $appProcess.HasExited) {
      [void]$appProcess.CloseMainWindow()
      if (-not $appProcess.WaitForExit(5000)) {
        Stop-Process -Id $appProcess.Id -Force -ErrorAction SilentlyContinue
        [void]$appProcess.WaitForExit(5000)
      }
    }
  }

  if (-not $productCode) {
    $entry = Get-HyesReadUninstallEntry
    if ($entry) { $productCode = [string]$entry.PSChildName }
  }
  if ($productCode) {
    Write-Host 'Uninstalling HyesRead and checking cleanup.'
    $uninstall = Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/x', $productCode, '/qn', '/norestart', '/l*v', "`"$uninstallLog`"") -Wait -PassThru
    if ($uninstall.ExitCode -notin @(0, 3010)) {
      $details = if (Test-Path -LiteralPath $uninstallLog) { (Get-Content -LiteralPath $uninstallLog -Tail 80) -join "`n" } else { 'No MSI verbose log was created.' }
      throw "MSI uninstall failed with exit code $($uninstall.ExitCode).`n$details"
    }
    if ($appPath -and (Test-Path -LiteralPath $appPath)) {
      throw "The installed executable remains after uninstall: $appPath"
    }
    if (Get-HyesReadUninstallEntry) { throw 'HyesRead remains in the Windows uninstall list after uninstall.' }
    foreach ($extension in @('epub', 'mobi', 'azw3', 'kf8', 'pdf', 'cbz', 'txt', 'md', 'fb2', 'fbz')) {
      if (Test-Path -LiteralPath "HKLM:\SOFTWARE\Classes\HyesRead.$extension") {
        throw "The $extension Open with registration remains after uninstall."
      }
    }
    if (Test-Path -LiteralPath $installRegistryKey) { throw 'The HyesRead install registry key remains after uninstall.' }
    Write-Host 'MSI uninstall and registration cleanup passed.'
  }
}

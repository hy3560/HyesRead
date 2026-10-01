param(
  [Parameter(Mandatory = $true)]
  [string]$InstallerPath
)

$ErrorActionPreference = 'Stop'
$resolvedInstaller = (Resolve-Path -LiteralPath $InstallerPath).Path
$fixture = (Resolve-Path -LiteralPath 'tests/fixtures/hyesread-acceptance.epub').Path
$uninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall'
$classesKey = 'HKCU:\Software\Classes'
$appProcess = $null
$entry = $null
$appPath = $null
$stage = 'initialization'

function Get-HyesReadUninstallEntry {
  Get-ChildItem -LiteralPath $uninstallKey -ErrorAction SilentlyContinue |
    ForEach-Object { Get-ItemProperty -LiteralPath $_.PSPath } |
    Where-Object { $_.DisplayName -like '*HyesRead*' } |
    Select-Object -First 1
}

function Write-GitHubFailureSummary([string]$message) {
  $safeMessage = $message -replace '[\r\n]+', ' '
  if ($env:GITHUB_STEP_SUMMARY) {
    Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value "`n### HyesRead EXE acceptance failed`n`n- Stage: ``$stage```n- Error: $safeMessage`n- Install log: ``$installLog```n- Uninstall log: ``$uninstallLog```n"
  }
  if ($env:GITHUB_OUTPUT) {
    $outputMessage = $safeMessage.Replace('%', '%25').Replace("`r", '%0D').Replace("`n", '%0A')
    Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "failure_message=$outputMessage"
    Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "failure_stage=$stage"
  }
}

try {
  $stage = 'install Windows EXE'
  Write-Host 'Installing the Windows EXE on the isolated runner.'
  $install = Start-Process -FilePath $resolvedInstaller -ArgumentList @('/S', "/D=$env:LOCALAPPDATA\HyesRead") -Wait -PassThru
  if ($install.ExitCode -ne 0) {
    throw "EXE installation failed with exit code $($install.ExitCode). Installer log: $installLog"
  }

  $stage = 'find uninstall registration'
  $entry = Get-HyesReadUninstallEntry
  if (-not $entry) { throw 'HyesRead was not registered in the current user uninstall list.' }

  $stage = 'find installed executable'
  $installDirectory = ([string]$entry.InstallLocation).Trim('"')
  if (-not $installDirectory) { throw 'The HyesRead install location is missing from its uninstall registration.' }
  $appPath = Join-Path $installDirectory 'hyes-read.exe'
  if (-not (Test-Path -LiteralPath $appPath -PathType Leaf)) { throw "The installed application executable is missing: $appPath" }

  $stage = 'check ebook file associations'
  foreach ($extension in @('epub', 'mobi', 'azw3', 'kf8', 'pdf', 'cbz', 'txt', 'md', 'fb2', 'fbz')) {
    $extensionKey = "$classesKey\.$extension"
    $association = [string](Get-ItemProperty -LiteralPath $extensionKey -Name '(default)' -ErrorAction SilentlyContinue).'(default)'
    if (-not $association) { throw "The installer did not register the $extension extension." }
    $openCommand = [string](Get-ItemProperty -LiteralPath "$classesKey\$association\shell\open\command" -Name '(default)' -ErrorAction SilentlyContinue).'(default)'
    if (-not $openCommand -or $openCommand -notmatch 'hyes-read\.exe') {
      throw "The $extension association does not open with HyesRead: $openCommand"
    }
  }

  $stage = 'launch installed application with EPUB'
  Get-Process -Name 'hyes-read' -ErrorAction SilentlyContinue | Stop-Process -Force
  Start-Sleep -Milliseconds 500
  $appProcess = Start-Process -FilePath $appPath -ArgumentList @("`"$fixture`"") -PassThru
  $deadline = [DateTime]::UtcNow.AddSeconds(20)
  do {
    Start-Sleep -Milliseconds 250
    $appProcess.Refresh()
    if ($appProcess.HasExited) { throw "Installed HyesRead exited during startup with code $($appProcess.ExitCode)." }
    if ($appProcess.MainWindowHandle -ne [IntPtr]::Zero) { break }
  } while ([DateTime]::UtcNow -lt $deadline)
  if ($appProcess.MainWindowHandle -eq [IntPtr]::Zero) { throw 'Installed HyesRead did not create a desktop window.' }
  Write-Host 'EXE install, registered ebook associations, installed app startup with EPUB, and window creation passed.'
} catch {
  $failureMessage = $_.Exception.Message -replace '[\r\n]+', ' '
  Write-GitHubFailureSummary $failureMessage
  Write-Output "::error title=HyesRead EXE acceptance failed::$stage - $failureMessage"
  throw
} finally {
  try {
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

    $entry = Get-HyesReadUninstallEntry
    if ($entry) {
      $stage = 'uninstall Windows EXE and check cleanup'
      $uninstaller = [string]$entry.UninstallString
      if (-not $uninstaller) { throw 'The HyesRead uninstaller command is missing.' }
      if ($uninstaller -match '^"([^"]+)"') { $uninstallerPath = $Matches[1] }
      else { $uninstallerPath = ($uninstaller -split '\s+', 2)[0] }
      if (-not (Test-Path -LiteralPath $uninstallerPath -PathType Leaf)) { throw "The uninstaller is missing: $uninstallerPath" }
      $uninstall = Start-Process -FilePath $uninstallerPath -ArgumentList @('/S') -Wait -PassThru
      if ($uninstall.ExitCode -ne 0) { throw "EXE uninstallation failed with exit code $($uninstall.ExitCode)." }

      if ($appPath -and (Test-Path -LiteralPath $appPath)) { throw "The installed executable remains after uninstall: $appPath" }
      if (Get-HyesReadUninstallEntry) { throw 'HyesRead remains in the Windows uninstall list after uninstall.' }
      foreach ($extension in @('epub', 'mobi', 'azw3', 'kf8', 'pdf', 'cbz', 'txt', 'md', 'fb2', 'fbz')) {
        if (Test-Path -LiteralPath "$classesKey\HyesRead.$extension") { throw "The $extension Open with registration remains after uninstall." }
      }
      Write-Host 'EXE uninstall and registration cleanup passed.'
    }
  } catch {
    $stage = 'uninstall Windows EXE and check cleanup'
    $failureMessage = $_.Exception.Message -replace '[\r\n]+', ' '
    Write-GitHubFailureSummary $failureMessage
    Write-Output "::error title=HyesRead EXE acceptance failed::$stage - $failureMessage"
    throw
  }
}

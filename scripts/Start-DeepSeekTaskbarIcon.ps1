[CmdletBinding()]
param(
  [ValidateRange(250, 30000)][int]$IntervalMilliseconds = 1200,
  [ValidateNotNullOrEmpty()][ValidateLength(1, 128)][string]$WindowTitle = 'DeepSeek',
  [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$iconPath = Join-Path $projectRoot 'assets\deepseek\deepseek-taskbar.ico'
$helperPath = Join-Path $projectRoot 'bin\DeepSeekTaskbarPresentation.exe'
if (-not (Test-Path -LiteralPath $iconPath)) {
  throw "DeepSeek taskbar icon is missing: $iconPath"
}

$package = Get-AppxPackage -Name 'OpenAI.Codex' | Sort-Object Version -Descending | Select-Object -First 1
if (-not $package) {
  throw 'The OpenAI Codex Appx package is not installed.'
}
$installRoot = [System.IO.Path]::GetFullPath($package.InstallLocation).TrimEnd('\')

$stateDir = Join-Path $env:LOCALAPPDATA 'CodeDrobe\OneShot'
$pidFile = Join-Path $stateDir 'naruto-shinobi-deepseek-icon.json'
$stopFile = Join-Path $stateDir 'naruto-shinobi-deepseek-icon.stop'
$stdoutLog = Join-Path $stateDir 'naruto-shinobi-deepseek-icon.log'
$stderrLog = Join-Path $stateDir 'naruto-shinobi-deepseek-icon.err.log'

$configuration = [pscustomobject]@{
  Helper = $helperPath
  Icon = $iconPath
  InstallRoot = $installRoot
  StateDirectory = $stateDir
  PidFile = $pidFile
  StopFile = $stopFile
  IntervalMilliseconds = $IntervalMilliseconds
  WindowTitle = $WindowTitle
  HelperExists = (Test-Path -LiteralPath $helperPath)
}
if ($DryRun) {
  $configuration
  exit 0
}

New-Item -ItemType Directory -Force -Path $stateDir | Out-Null

if (Test-Path -LiteralPath $pidFile) {
  try {
    $metadata = Get-Content -Raw -LiteralPath $pidFile | ConvertFrom-Json
    $existing = Get-CimInstance Win32_Process -Filter "ProcessId = $([int]$metadata.pid)" -ErrorAction SilentlyContinue
    $owned = $existing -and $existing.CommandLine -and
      $existing.CommandLine.Contains([string]$metadata.helperPath) -and
      $existing.CommandLine.Contains([string]$metadata.stopFile)
    if ($owned) {
      Set-Content -LiteralPath ([string]$metadata.stopFile) -Value 'stop' -NoNewline -Encoding ascii
      $deadline = (Get-Date).AddSeconds(10)
      do {
        Start-Sleep -Milliseconds 200
        $existing = Get-CimInstance Win32_Process -Filter "ProcessId = $([int]$metadata.pid)" -ErrorAction SilentlyContinue
      } while ($existing -and (Get-Date) -lt $deadline)
      if ($existing) {
        throw 'The previous owned taskbar icon watcher did not restore and exit within 10 seconds.'
      }
    }
  } catch {
    throw "Could not replace the previous DeepSeek taskbar icon watcher: $($_.Exception.Message)"
  }
}

Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $stopFile -Force -ErrorAction SilentlyContinue
$helperPath = (& (Join-Path $PSScriptRoot 'Build-DeepSeekTaskbarIcon.ps1') | Select-Object -Last 1)
Set-Content -LiteralPath $stdoutLog -Value '' -Encoding utf8
Set-Content -LiteralPath $stderrLog -Value '' -Encoding utf8

$arguments = @(
  '--icon', ('"{0}"' -f $iconPath),
  '--install-root', ('"{0}"' -f $installRoot),
  '--stop-file', ('"{0}"' -f $stopFile),
  '--window-title', ('"{0}"' -f $WindowTitle),
  '--interval-ms', "$IntervalMilliseconds"
)
$watcher = Start-Process -FilePath $helperPath -ArgumentList $arguments -WindowStyle Hidden `
  -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog -PassThru

$metadata = [ordered]@{
  pid = $watcher.Id
  helperPath = $helperPath
  iconPath = $iconPath
  installRoot = $installRoot
  windowTitle = $WindowTitle
  stopFile = $stopFile
  stdoutLog = $stdoutLog
  stderrLog = $stderrLog
  startedAt = (Get-Date).ToString('o')
}
$metadata | ConvertTo-Json | Set-Content -LiteralPath $pidFile -Encoding utf8

$deadline = (Get-Date).AddSeconds(5)
do {
  Start-Sleep -Milliseconds 200
  $watcher.Refresh()
  $ready = (Test-Path -LiteralPath $stdoutLog) -and ((Get-Content -Raw -LiteralPath $stdoutLog) -match 'READY')
} while (-not $watcher.HasExited -and -not $ready -and (Get-Date) -lt $deadline)

if ($watcher.HasExited -or -not $ready) {
  $stdout = if (Test-Path -LiteralPath $stdoutLog) { Get-Content -Raw -LiteralPath $stdoutLog } else { '' }
  $stderr = if (Test-Path -LiteralPath $stderrLog) { Get-Content -Raw -LiteralPath $stderrLog } else { '' }
  if (-not $watcher.HasExited) {
    Set-Content -LiteralPath $stopFile -Value 'stop' -NoNewline -Encoding ascii
    $watcher.WaitForExit(3000) | Out-Null
  }
  if ($watcher.HasExited) {
    Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $stopFile -Force -ErrorAction SilentlyContinue
  }
  throw "DeepSeek taskbar icon watcher did not become ready.`n$stdout`n$stderr"
}

Write-Host "DeepSeek taskbar icon watcher started (PID $($watcher.Id))."
Write-Host "Log: $stdoutLog"

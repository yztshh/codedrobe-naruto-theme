[CmdletBinding()]
param([ValidateRange(1, 30)][int]$TimeoutSeconds = 10)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$stateDir = Join-Path $env:LOCALAPPDATA 'CodeDrobe\OneShot'
$pidFile = Join-Path $stateDir 'naruto-shinobi-deepseek-icon.json'
if (-not (Test-Path -LiteralPath $pidFile)) {
  Write-Host 'No owned DeepSeek taskbar icon watcher is registered.'
  exit 0
}

$metadata = Get-Content -Raw -LiteralPath $pidFile | ConvertFrom-Json
$process = Get-CimInstance Win32_Process -Filter "ProcessId = $([int]$metadata.pid)" -ErrorAction SilentlyContinue
if (-not $process) {
  Remove-Item -LiteralPath $pidFile -Force
  Write-Warning 'The icon watcher was already gone. Restart Codex if its cached icon remains.'
  exit 0
}

$owned = $process.CommandLine -and
  $process.CommandLine.Contains([string]$metadata.helperPath) -and
  $process.CommandLine.Contains([string]$metadata.stopFile)
if (-not $owned) {
  throw 'The recorded PID is no longer owned by this project; it was not stopped.'
}

Set-Content -LiteralPath ([string]$metadata.stopFile) -Value 'stop' -NoNewline -Encoding ascii
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
do {
  Start-Sleep -Milliseconds 200
  $process = Get-CimInstance Win32_Process -Filter "ProcessId = $([int]$metadata.pid)" -ErrorAction SilentlyContinue
} while ($process -and (Get-Date) -lt $deadline)

if ($process) {
  throw "The owned icon watcher did not restore and exit within $TimeoutSeconds seconds. Restart Codex to restore its packaged icon."
}

Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath ([string]$metadata.stopFile) -Force -ErrorAction SilentlyContinue
Write-Host 'The original Codex/ChatGPT window icon has been restored.'

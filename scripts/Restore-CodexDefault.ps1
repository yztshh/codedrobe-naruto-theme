[CmdletBinding()]
param([ValidateRange(1, 65535)][int]$Port = 9335)

. (Join-Path $PSScriptRoot 'CodeDrobe.Common.ps1')

& (Join-Path $PSScriptRoot 'Stop-DeepSeekTaskbarIcon.ps1')

$stateDir = Join-Path $env:LOCALAPPDATA 'CodeDrobe\OneShot'
$pidFile = Join-Path $stateDir 'naruto-shinobi-watch.json'
if (Test-Path -LiteralPath $pidFile) {
  try {
    $metadata = Get-Content -Raw -LiteralPath $pidFile | ConvertFrom-Json
    $process = Get-CimInstance Win32_Process -Filter "ProcessId = $([int]$metadata.pid)" -ErrorAction SilentlyContinue
    if ($process -and $process.CommandLine -and $process.CommandLine.Contains([string]$metadata.workerFile)) {
      Stop-Process -Id ([int]$metadata.pid) -Force
    }
    Remove-Item -LiteralPath $pidFile -Force
  } catch {
    Write-Warning 'The watcher state could not be read; it was left in place.'
  }
}

$listener = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if (-not $listener) {
  & (Join-Path $PSScriptRoot 'Launch-CodexWithCdp.ps1') -Port $Port -RestartExisting
}

Invoke-CodeDrobe -Arguments @('restore', '--app', 'codex', '--port', "$Port")
Write-Host 'CodeDrobe theme removed. Restart Codex if host colors remain cached.'

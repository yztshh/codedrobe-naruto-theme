[CmdletBinding()]
param([ValidateRange(1, 65535)][int]$Port = 9335)

. (Join-Path $PSScriptRoot 'CodeDrobe.Common.ps1')

& (Join-Path $PSScriptRoot 'Build-Theme.ps1')
$package = Join-Path $script:CodeDrobeProjectRoot 'dist\naruto-shinobi.codedrobe-theme'
$artifacts = Join-Path $script:CodeDrobeProjectRoot 'artifacts'
$screenshot = Join-Path $artifacts 'naruto-shinobi-verified.png'
New-Item -ItemType Directory -Force -Path $artifacts | Out-Null

$listener = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if (-not $listener) {
  & (Join-Path $PSScriptRoot 'Launch-CodexWithCdp.ps1') -Port $Port -RestartExisting
}

$probe = Invoke-CodeDrobeCapture -Arguments @('probe', '--app', 'codex', '--port', "$Port", '--timeout-ms', '5000', '--theme', $package)
if ($probe.ExitCode -ne 0) {
  if ($probe.Output -match 'avatar-overlay') {
    throw 'CodeDrobe 0.3.0 still sees the Codex avatar overlay. Disable the mascot/avatar, restart Codex, and rerun this script.'
  }
  Write-Host $probe.Output
  throw 'CodeDrobe DOM preflight failed.'
}

$node = Get-CodeDrobeNode
$helper = Join-Path $PSScriptRoot 'windows_apply_theme.mjs'
& $node $helper --theme $package --app codex --port $Port
if ($LASTEXITCODE -ne 0) { throw "Windows apply helper exited with code $LASTEXITCODE." }

if (Test-Path -LiteralPath $screenshot) { Remove-Item -LiteralPath $screenshot -Force }
$verified = $false
for ($attempt = 1; $attempt -le 3; $attempt += 1) {
  $verify = Invoke-CodeDrobeCapture -Arguments @('verify', '--app', 'codex', '--port', "$Port", '--theme', $package, '--screenshot', $screenshot)
  Write-Host $verify.Output
  if ($verify.ExitCode -eq 0 -and (Test-Path -LiteralPath $screenshot)) {
    $verified = $true
    break
  }
  if ($attempt -lt 3) { Start-Sleep -Seconds 2 }
}
if (-not $verified) { throw 'Theme verification or screenshot capture failed after three attempts.' }

$pidFile = Join-Path $env:LOCALAPPDATA 'CodeDrobe\OneShot\naruto-shinobi-watch.json'
if (-not (Test-Path -LiteralPath $pidFile)) { throw 'The CodeDrobe watcher state file was not created.' }
$watcher = Get-Content -Raw -LiteralPath $pidFile | ConvertFrom-Json
$watcherProcess = Get-CimInstance Win32_Process -Filter "ProcessId = $([int]$watcher.pid)" -ErrorAction SilentlyContinue
if (-not $watcherProcess -or -not $watcherProcess.CommandLine -or
    -not $watcherProcess.CommandLine.Contains([string]$watcher.workerFile)) {
  Write-Warning 'The theme is installed and verified, but the watcher was reclaimed by the parent process environment. Run Apply Naruto Theme.cmd directly from File Explorer to keep the watcher detached.'
} else {
  Write-Host "Watcher PID: $($watcher.pid)"
}

Write-Host "Installed and verified: $package"
Write-Host "Screenshot: $screenshot"

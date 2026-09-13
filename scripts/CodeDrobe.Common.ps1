Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$env:npm_config_loglevel = 'warn'

$script:CodeDrobeProjectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$script:CodeDrobeBin = Join-Path $script:CodeDrobeProjectRoot 'bin'
$script:CodeDrobeCoreCli = Join-Path $script:CodeDrobeProjectRoot 'node_modules\@codedrobe\core\bin\codedrobe.mjs'
$env:PATH = "$script:CodeDrobeBin;$env:PATH"

function Get-CodeDrobeNode {
  $command = Get-Command node.exe -ErrorAction SilentlyContinue
  if (-not $command) { $command = Get-Command node -ErrorAction SilentlyContinue }
  if (-not $command) {
    throw 'Node.js was not found. Install Node.js 22.4 or newer from https://nodejs.org/ and try again.'
  }

  $versionText = (& $command.Source --version).TrimStart('v')
  $version = $null
  if (-not [version]::TryParse($versionText, [ref]$version) -or $version -lt [version]'22.4.0') {
    throw "Node.js 22.4 or newer is required. Detected: $versionText"
  }
  return $command.Source
}

function Install-CodeDrobeDependencies {
  $patcher = Join-Path $PSScriptRoot 'Patch-CodeDrobeCore.ps1'
  if (Test-Path -LiteralPath $script:CodeDrobeCoreCli) {
    & $patcher
    return
  }

  Get-CodeDrobeNode | Out-Null
  $npm = Get-Command npm.cmd -ErrorAction SilentlyContinue
  if (-not $npm) { $npm = Get-Command npm -ErrorAction SilentlyContinue }
  if (-not $npm) {
    throw 'npm was not found. Install the standard Node.js package (including npm) and try again.'
  }

  Write-Host 'First run: installing the pinned public @codedrobe/core dependency...'
  $previousPreference = $ErrorActionPreference
  Push-Location $script:CodeDrobeProjectRoot
  try {
    $ErrorActionPreference = 'Continue'
    & $npm.Source install --ignore-scripts --no-audit --no-fund
    $exitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previousPreference
    Pop-Location
  }
  if ($exitCode -ne 0 -or -not (Test-Path -LiteralPath $script:CodeDrobeCoreCli)) {
    throw "npm install failed with code $exitCode."
  }
  & $patcher
}

function Get-CodeDrobeRunner {
  Install-CodeDrobeDependencies
  $runner = Join-Path $script:CodeDrobeBin 'codedrobe.cmd'
  if (-not (Test-Path -LiteralPath $runner)) { throw "CodeDrobe runner is missing: $runner" }
  return [pscustomobject]@{ Executable = $runner; Prefix = @() }
}

function Invoke-CodeDrobe {
  param([Parameter(Mandatory = $true)][string[]]$Arguments)
  $runner = Get-CodeDrobeRunner
  & $runner.Executable @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "CodeDrobe exited with code $LASTEXITCODE."
  }
}

function Invoke-CodeDrobeCapture {
  param([Parameter(Mandatory = $true)][string[]]$Arguments)
  $runner = Get-CodeDrobeRunner
  $previousPreference = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    $output = (& $runner.Executable @Arguments 2>&1 | Out-String)
    $exitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previousPreference
  }
  return [pscustomobject]@{ ExitCode = $exitCode; Output = $output }
}

function Test-CodeDrobeRendererEndpoint {
  [CmdletBinding()]
  param(
    [ValidateRange(1, 65535)][int]$Port = 9335,
    [ValidateRange(1, 10)][int]$TimeoutSeconds = 2
  )

  foreach ($hostAddress in @('127.0.0.1', '[::1]')) {
    try {
      $targets = Invoke-RestMethod -Method Get -Uri "http://${hostAddress}:$Port/json/list" `
        -TimeoutSec $TimeoutSeconds -ErrorAction Stop
      $renderers = @($targets | Where-Object {
        $url = [string]$_.url
        $_.type -eq 'page' -and
          $url.StartsWith('app://', [System.StringComparison]::OrdinalIgnoreCase) -and
          -not $url.Contains('initialRoute=%2Favatar-overlay') -and
          -not $url.Contains('detached-window.html')
      })
      if ($renderers.Count -gt 0) { return $true }
    } catch {
      # Try the other loopback family.
    }
  }
  return $false
}

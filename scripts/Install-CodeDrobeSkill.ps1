[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$destination = Join-Path $env:USERPROFILE '.codex\skills\codedrobe-one-shot-theme'
if (Test-Path -LiteralPath (Join-Path $destination 'SKILL.md')) {
  Write-Host "CodeDrobe one-shot theme skill is already installed: $destination"
  exit 0
}
if (Test-Path -LiteralPath $destination) {
  throw "Destination exists but is not a valid installed skill: $destination"
}

$tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\') + '\'
$tempRoot = [System.IO.Path]::GetFullPath((Join-Path $tempBase ("codedrobe-skill-" + [guid]::NewGuid().ToString('N'))))
if (-not $tempRoot.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw 'Refusing to use a temporary path outside the system temporary directory.'
}

try {
  New-Item -ItemType Directory -Path $tempRoot | Out-Null
  $archive = Join-Path $tempRoot 'skill.zip'
  $extract = Join-Path $tempRoot 'extract'
  Write-Host 'Downloading qcrao/codedrobe-one-shot-theme-skill from GitHub...'
  Invoke-WebRequest -UseBasicParsing -Headers @{ 'User-Agent' = 'codedrobe-naruto-theme-installer' } `
    -Uri 'https://api.github.com/repos/qcrao/codedrobe-one-shot-theme-skill/zipball/main' -OutFile $archive
  Expand-Archive -LiteralPath $archive -DestinationPath $extract

  $repositoryRoot = Get-ChildItem -LiteralPath $extract -Directory | Select-Object -First 1
  if (-not $repositoryRoot) { throw 'The downloaded GitHub archive is empty.' }
  $source = Join-Path $repositoryRoot.FullName 'skills\codedrobe-one-shot-theme'
  if (-not (Test-Path -LiteralPath (Join-Path $source 'SKILL.md'))) {
    throw 'The expected skill path was not found in the downloaded repository.'
  }

  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
  Copy-Item -LiteralPath $source -Destination $destination -Recurse
  Write-Host "Installed skill: $destination"
  Write-Host 'Restart Codex so it discovers the newly installed skill.'
} finally {
  if (Test-Path -LiteralPath $tempRoot) {
    $resolved = [System.IO.Path]::GetFullPath($tempRoot)
    if ($resolved.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase)) {
      Remove-Item -LiteralPath $resolved -Recurse -Force
    }
  }
}

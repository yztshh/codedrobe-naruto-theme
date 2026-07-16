[CmdletBinding()]
param()

. (Join-Path $PSScriptRoot 'CodeDrobe.Common.ps1')

$manifest = Join-Path $script:CodeDrobeProjectRoot 'theme\theme.json'
$dist = Join-Path $script:CodeDrobeProjectRoot 'dist'
$package = Join-Path $dist 'naruto-shinobi.codedrobe-theme'

New-Item -ItemType Directory -Force -Path $dist | Out-Null
Invoke-CodeDrobe -Arguments @('theme', 'pack', $manifest, '--output', $package, '--force')
Invoke-CodeDrobe -Arguments @('theme', 'inspect', $package)

Write-Host "Theme package: $package"

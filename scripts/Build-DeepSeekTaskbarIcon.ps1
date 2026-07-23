[CmdletBinding()]
param([switch]$Force)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$source = Join-Path $projectRoot 'tools\DeepSeekTaskbarIcon\DeepSeekTaskbarIcon.cs'
$output = Join-Path $projectRoot 'bin\DeepSeekTaskbarPresentation.exe'

$compilerCandidates = @(
  (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
  (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
)
$compiler = $compilerCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $compiler) {
  throw 'The Windows .NET Framework C# compiler was not found.'
}
if (-not (Test-Path -LiteralPath $source)) {
  throw "Taskbar icon helper source is missing: $source"
}

$needsBuild = $Force -or -not (Test-Path -LiteralPath $output)
if (-not $needsBuild) {
  $needsBuild = (Get-Item -LiteralPath $source).LastWriteTimeUtc -gt (Get-Item -LiteralPath $output).LastWriteTimeUtc
}

if ($needsBuild) {
  & $compiler /nologo /target:exe /platform:x64 /optimize+ /warnaserror+ "/out:$output" $source
  if ($LASTEXITCODE -ne 0) {
    throw "DeepSeek taskbar icon helper compilation failed with code $LASTEXITCODE."
  }
}

Write-Output $output

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$adapterPath = Join-Path $projectRoot 'node_modules\@codedrobe\core\src\adapters\codex.mjs'
if (-not (Test-Path -LiteralPath $adapterPath)) {
  throw "The local CodeDrobe Codex adapter was not found: $adapterPath"
}

$source = [System.IO.File]::ReadAllText($adapterPath)
$marker = 'CODEDROBE_NARUTO_IGNORE_AVATAR_OVERLAY'
if ($source.Contains($marker)) { exit 0 }

$original = @'
  matchTarget(target) {
    return target?.type === "page" && String(target.url ?? "").startsWith("app://");
  },
'@
$replacement = @'
  matchTarget(target) {
    const url = String(target.url ?? "");
    return target?.type === "page"
      && url.startsWith("app://")
      && !url.includes("initialRoute=%2Favatar-overlay"); // CODEDROBE_NARUTO_IGNORE_AVATAR_OVERLAY
  },
'@

if (-not $source.Contains($original)) {
  throw 'The CodeDrobe Codex adapter no longer matches the expected 0.3.0 source. Refusing to patch an unknown version.'
}

$patched = $source.Replace($original, $replacement)
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($adapterPath, $patched, $utf8NoBom)
Write-Host 'Applied the local CodeDrobe 0.3.0 avatar-overlay target filter.'

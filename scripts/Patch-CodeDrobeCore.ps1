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
$marker = 'CODEDROBE_NARUTO_CURRENT_CODEX_V5'
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
      && !url.includes("initialRoute=%2Favatar-overlay")
      && !url.includes("detached-window.html"); // CODEDROBE_NARUTO_CURRENT_CODEX_V5
  },
'@

$previousReplacementV4 = @'
  matchTarget(target) {
    const url = String(target.url ?? "");
    return target?.type === "page"
      && url.startsWith("app://")
      && !url.includes("initialRoute=%2Favatar-overlay")
      && !url.includes("detached-window.html"); // CODEDROBE_NARUTO_CURRENT_CODEX_V4
  },
'@

$previousReplacementV3 = @'
  matchTarget(target) {
    const url = String(target.url ?? "");
    return target?.type === "page"
      && url.startsWith("app://")
      && !url.includes("initialRoute=%2Favatar-overlay")
      && !url.includes("detached-window.html"); // CODEDROBE_NARUTO_CURRENT_CODEX_V3
  },
'@

$previousReplacementV2 = @'
  matchTarget(target) {
    const url = String(target.url ?? "");
    return target?.type === "page"
      && url.startsWith("app://")
      && !url.includes("initialRoute=%2Favatar-overlay")
      && !url.includes("detached-window.html"); // CODEDROBE_NARUTO_IGNORE_AUXILIARY_WINDOWS_V2
  },
'@

$previousReplacementV1 = @'
  matchTarget(target) {
    const url = String(target.url ?? "");
    return target?.type === "page"
      && url.startsWith("app://")
      && !url.includes("initialRoute=%2Favatar-overlay"); // CODEDROBE_NARUTO_IGNORE_AVATAR_OVERLAY
  },
'@

if ($source.Contains($previousReplacementV4)) {
  $patched = $source.Replace($previousReplacementV4, $replacement)
} elseif ($source.Contains($previousReplacementV3)) {
  $patched = $source.Replace($previousReplacementV3, $replacement)
} elseif ($source.Contains($previousReplacementV2)) {
  $patched = $source.Replace($previousReplacementV2, $replacement)
} elseif ($source.Contains($previousReplacementV1)) {
  $patched = $source.Replace($previousReplacementV1, $replacement)
} elseif ($source.Contains($original)) {
  $patched = $source.Replace($original, $replacement)
} else {
  throw 'The CodeDrobe Codex adapter no longer matches the expected 0.3.0 source. Refusing to patch an unknown version.'
}

$oldRoots = @(
  'rootAny: ["main.main-surface"]',
  'rootAny: ["main"]',
  'rootAny: ["main", "[role=''main'']"]'
)
$newRoot = 'rootAny: ["main[class*=''_MainContentSurface_'']", "[role=''main'']", "main:not(.bg-surface)"]'
$rootRepaired = $false
foreach ($oldRoot in $oldRoots) {
  if ($patched.Contains($oldRoot)) {
    $patched = $patched.Replace($oldRoot, $newRoot)
    $rootRepaired = $true
    break
  }
}
if (-not $rootRepaired -and -not $patched.Contains($newRoot)) {
  throw 'The CodeDrobe Codex root verification no longer matches the expected source.'
}

$oldComposer = '{ name: "composer", any: [".composer-surface-chrome"] }'
$newComposer = '{ name: "composer", any: [".composer-surface-chrome", ".ProseMirror[contenteditable=''true'']"] }'
if ($patched.Contains($oldComposer)) {
  $patched = $patched.Replace($oldComposer, $newComposer)
} elseif (-not $patched.Contains($newComposer)) {
  throw 'The CodeDrobe Codex composer verification no longer matches the expected source.'
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($adapterPath, $patched, $utf8NoBom)
Write-Host 'Applied the local CodeDrobe 0.3.0 current-Codex compatibility repair.'

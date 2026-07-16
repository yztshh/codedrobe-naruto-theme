[CmdletBinding()]
param(
  [ValidateRange(1, 65535)][int]$Port = 9335,
  [switch]$RestartExisting
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not ('CodeDrobeNaruto.ApplicationActivator' -as [type])) {
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace CodeDrobeNaruto {
  [ComImport]
  [Guid("2e941141-7f97-4756-ba1d-9decde894a3d")]
  [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IApplicationActivationManager {
    [PreserveSig]
    int ActivateApplication(
      [MarshalAs(UnmanagedType.LPWStr)] string appUserModelId,
      [MarshalAs(UnmanagedType.LPWStr)] string arguments,
      uint options,
      out uint processId);
    int ActivateForFile(IntPtr appUserModelId, IntPtr itemArray, IntPtr verb, out uint processId);
    int ActivateForProtocol(IntPtr appUserModelId, IntPtr itemArray, out uint processId);
  }

  [ComImport]
  [Guid("45BA127D-10A8-46EA-8AB7-56EA9078943C")]
  class ApplicationActivationManager { }

  public static class ApplicationActivator {
    public static uint Activate(string appUserModelId, string arguments) {
      var manager = (IApplicationActivationManager)new ApplicationActivationManager();
      uint processId;
      int result = manager.ActivateApplication(appUserModelId, arguments ?? string.Empty, 0, out processId);
      if (result < 0) Marshal.ThrowExceptionForHR(result);
      return processId;
    }
  }
}
'@
}

$package = Get-AppxPackage -Name 'OpenAI.Codex' | Sort-Object Version -Descending | Select-Object -First 1
if (-not $package) { throw 'The OpenAI Codex Appx package is not installed.' }

$manifest = Get-AppxPackageManifest -Package $package
$applicationId = @($manifest.Package.Applications.Application)[0].Id
$aumid = "$($package.PackageFamilyName)!$applicationId"
$installRoot = [System.IO.Path]::GetFullPath($package.InstallLocation).TrimEnd('\')

$processes = @(Get-CimInstance Win32_Process -Filter "Name = 'ChatGPT.exe'" -ErrorAction SilentlyContinue | Where-Object {
  $_.ExecutablePath -and [System.IO.Path]::GetFullPath($_.ExecutablePath).StartsWith($installRoot, [System.StringComparison]::OrdinalIgnoreCase)
})

if ($processes.Count -gt 0) {
  if (-not $RestartExisting) { throw 'Codex is already running. Pass -RestartExisting to enable the CodeDrobe port.' }
  Stop-Process -Id $processes.ProcessId -Force -ErrorAction SilentlyContinue
  $deadline = (Get-Date).AddSeconds(10)
  do {
    Start-Sleep -Milliseconds 250
    $remaining = @(Get-CimInstance Win32_Process -Filter "Name = 'ChatGPT.exe'" -ErrorAction SilentlyContinue | Where-Object {
      $_.ExecutablePath -and [System.IO.Path]::GetFullPath($_.ExecutablePath).StartsWith($installRoot, [System.StringComparison]::OrdinalIgnoreCase)
    })
  } while ($remaining.Count -gt 0 -and (Get-Date) -lt $deadline)
  if ($remaining.Count -gt 0) { throw 'Codex did not close in time.' }
}

$arguments = "--remote-debugging-address=127.0.0.1 --remote-debugging-port=$Port"
$activationPid = [CodeDrobeNaruto.ApplicationActivator]::Activate($aumid, $arguments)

$deadline = (Get-Date).AddSeconds(45)
do {
  Start-Sleep -Milliseconds 400
  $listener = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
} while (-not $listener -and (Get-Date) -lt $deadline)

if (-not $listener) { throw "Codex did not expose the loopback CDP port $Port." }
Write-Host "Codex CDP is ready on 127.0.0.1:$Port (activation PID $activationPid)."

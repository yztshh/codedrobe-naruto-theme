# DeepSeek taskbar icon design

## Goal

Show the DeepSeek icon and `DeepSeek` title for the running Microsoft Store Codex window without
editing the signed Appx package, `WindowsApps`, Codex files, or the CodeDrobe
theme runtime.

## Design

1. `Start-DeepSeekTaskbarIcon.ps1` resolves the newest installed
   `OpenAI.Codex` package and its absolute installation directory.
2. `Build-DeepSeekTaskbarIcon.ps1` compiles the auditable C# source with the
   Windows-provided .NET Framework compiler. The generated executable stays in
   `bin/` and is rebuilt only when its source changes.
3. The hidden watcher enumerates visible top-level windows and accepts a window
   only when its owning executable is located below the resolved Codex package
   directory. Matching by installation root prevents unrelated `ChatGPT.exe`
   processes from being changed.
4. For every accepted taskbar window, the watcher captures its original title
   and large/small icons, applies `DeepSeek` through `WM_SETTEXT`, applies the
   local DeepSeek `.ico` through `WM_SETICON`, and updates
   `System.AppUserModel.RelaunchIconResource` when the window property store
   allows it.
5. A single owned PID file and stop-signal file are stored below
   `%LOCALAPPDATA%\CodeDrobe\OneShot`. Reapplying first asks the old watcher to
   restore all captured values and exit. It never kills by process name.
6. `Stop-DeepSeekTaskbarIcon.ps1` uses the same owned stop signal. If ownership
   cannot be proven, it leaves the process alone. If graceful restoration is
   impossible, restarting Codex restores the package-provided icon.

## Lifecycle

```text
Apply Naruto Theme
  -> package / probe / apply / verify
  -> start DeepSeek icon watcher
  -> capture original icon values
  -> apply icon to current and future Codex windows

Restore Codex Default
  -> signal icon watcher
  -> restore captured icon values
  -> stop theme watcher / restore CodeDrobe appearance
```

## Scope and limitations

- The taskbar label and window title become `DeepSeek` by default. Use the
  `-WindowTitle` parameter to choose another label.
- This is a per-user, per-session presentation change. No administrator rights
  are requested.
- A Codex Appx update changes its installation directory. Run the Set/Apply
  entry again after an update so the watcher targets the new package version.
- Windows Explorer and packaged Electron applications cache icons differently.
  The watcher sets both documented window icons and the documented relaunch icon
  property, but a full Codex restart may still be required to clear an old
  Explorer cache.
- The DeepSeek artwork is used only for local customization and does not imply
  affiliation with or endorsement by DeepSeek.
- The bundled DeepSeek favicon is excluded from the repository's Apache-2.0
  license; see `ASSET-NOTICE.md` before redistribution or commercial use.

## Recovery

Preferred recovery:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Stop-DeepSeekTaskbarIcon.ps1
```

If the watcher was force-terminated before it could restore captured values,
fully close and reopen Codex. No package or registry repair is necessary.

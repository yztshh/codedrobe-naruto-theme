@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Apply-NarutoTheme.ps1" %*
set "code=%ERRORLEVEL%"
echo.
pause
exit /b %code%

@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Restore-CodexDefault.ps1"
set "code=%ERRORLEVEL%"
echo.
pause
exit /b %code%

@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Start-DeepSeekTaskbarIcon.ps1"
set "code=%ERRORLEVEL%"
echo.
pause
exit /b %code%

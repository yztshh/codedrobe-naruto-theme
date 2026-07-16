@echo off
setlocal
set "core=%~dp0..\node_modules\@codedrobe\core\bin\codedrobe.mjs"
if not exist "%core%" (
  echo Local @codedrobe/core is missing. Run npm install in the project directory. 1>&2
  exit /b 1
)

where node.exe >nul 2>&1
if not errorlevel 1 (
  node.exe "%core%" %*
  exit /b %ERRORLEVEL%
)

echo Node.js was not found. 1>&2
exit /b 1

@echo off
setlocal

set "TARGET_APP=C:\CreativeSeeds\Applications\guerilla2\app"
set "GUERILLA_ROOT=C:\CreativeSeeds\Applications\guerilla2"
set "INSTALLER=%~dp0tools\install.ps1"
set "EXTRA_ARGS="

if /I "%~1"=="/dryrun" set "EXTRA_ARGS=-WhatIf"
if /I "%~1"=="--dry-run" set "EXTRA_ARGS=-WhatIf"
if /I "%~1"=="-WhatIf" set "EXTRA_ARGS=-WhatIf"

echo Rebellion installer
echo Target: %TARGET_APP%
echo.

if not exist "%INSTALLER%" (
  echo ERROR: Missing installer script:
  echo %INSTALLER%
  pause
  exit /b 1
)

if not exist "%TARGET_APP%\" (
  echo ERROR: Guerilla app folder was not found:
  echo %TARGET_APP%
  pause
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%INSTALLER%" -GuerillaRoot "%GUERILLA_ROOT%" %EXTRA_ARGS%
if errorlevel 1 (
  echo.
  echo ERROR: Rebellion install failed.
  pause
  exit /b 1
)

echo.
if "%EXTRA_ARGS%"=="-WhatIf" (
  echo Dry run complete. Nothing was installed.
) else (
  echo Rebellion installed. Restart Guerilla if it is currently open.
)
pause

@echo off
rem Updates ObsidiNote to the newest release now (ObsidiNote also does this at every start).
rem Go back to an earlier release: update.cmd -To v0.1.3 (automatic updates then skip the newer ones).
rem One ( ) block with exit /b inside: cmd reads all of it before running, so an update that replaces this file while it runs cannot make cmd read on in the new file.
(
  cd /d "%~dp0"
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\update.ps1" -Force -Report %*
  echo.
  echo If ObsidiNote is running, start it again to use the new version.
  pause
  exit /b
)

@echo off
rem Updates ObsidiNote to the newest release now (ObsidiNote also does this at every start).
rem Go back to an earlier release: update.cmd -To v0.1.3 (automatic updates then skip the newer ones).
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\update.ps1" -Force -Report %*
echo.
echo If ObsidiNote is running, start it again to use the new version.
pause

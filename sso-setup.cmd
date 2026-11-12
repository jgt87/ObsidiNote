@echo off
rem Turns on single sign-on with your Windows work account in ObsidiNote's Edge profile, so Copilot
rem signs in by itself after a restart. No password is stored. Writes a log to %LOCALAPPDATA%\ObsidiNote\logs.
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\sso-setup.ps1" %*
echo.
pause

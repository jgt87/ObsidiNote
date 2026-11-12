@echo off
rem ObsidiNote - double-click to start. Checks for an update, checks this computer, opens OneNote and Microsoft 365 Copilot.
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0obsidinote.ps1" %*
pause

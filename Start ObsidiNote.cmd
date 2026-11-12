@echo off
rem ObsidiNote - double-click to start. Checks for an update, checks this computer, opens OneNote and Microsoft 365 Copilot.
rem One ( ) block with exit /b inside: cmd reads all of it before running, so an update that replaces this file while it runs cannot make cmd read on in the new file.
(
  cd /d "%~dp0"
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0obsidinote.ps1" %*
  pause
  exit /b
)

@echo off
rem ObsidiNote validation kit: the link summary probes only (P7 and P8) - double-click to run them.
rem P7 asks you for a SharePoint page address and a OneDrive document address (paste each, or press Enter to skip one);
rem P8 uses a public documentation page. Copilot summarizes each with your own access.
rem Read only: nothing is written. The addresses are never logged. The log goes to your Desktop (safe to send).
rem One ( ) block with exit /b inside: cmd reads all of it before running, so an update that replaces this file while it runs cannot make cmd read on in the new file.
(
  cd /d "%~dp0"
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Run-Validation.ps1" -Stage V5 -Probe P7,P8 %*
  pause
  exit /b
)

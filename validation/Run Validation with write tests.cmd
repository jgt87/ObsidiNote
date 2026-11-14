@echo off
rem ObsidiNote validation kit with the write tests - double-click to run all checks, write tests included.
rem The write tests write only into the kit's own notebooks ObsidiNote-Probe and ObsidiNote-Validation.
rem Options are passed on, for example: "Run Validation with write tests.cmd" -Stage V5
rem The log goes to your Desktop: ObsidiNote-validation-<date>.txt (no content; safe to send).
rem One ( ) block with exit /b inside: cmd reads all of it before running, so an update that replaces this file while it runs cannot make cmd read on in the new file.
(
  cd /d "%~dp0"
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Run-Validation.ps1" -WriteTest %*
  pause
  exit /b
)

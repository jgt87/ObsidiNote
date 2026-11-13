@echo off
rem ObsidiNote validation kit - double-click to run all checks without the write tests.
rem Options are passed on, for example: "Run Validation.cmd" -Stage V1,V2,V4 -NoCopilot   or   -WriteTest
rem The log goes to your Desktop: ObsidiNote-validation-<date>.txt (no content; safe to send).
rem One ( ) block with exit /b inside: cmd reads all of it before running, so an update that replaces this file while it runs cannot make cmd read on in the new file.
(
  cd /d "%~dp0"
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Run-Validation.ps1" %*
  pause
  exit /b
)

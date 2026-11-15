@echo off
rem ObsidiNote validation kit: the Loop search probe only (P4) - double-click to run it.
rem First type a line such as OBSN-P4-ABC123 on a Loop page of your own; the kit asks you for that marker
rem and asks Copilot (Work IQ on, your own access) to find it.
rem Read only: nothing is written. The marker is never logged. The log goes to your Desktop (safe to send).
rem One ( ) block with exit /b inside: cmd reads all of it before running, so an update that replaces this file while it runs cannot make cmd read on in the new file.
(
  cd /d "%~dp0"
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Run-Validation.ps1" -Stage V5 -Probe P4 %*
  pause
  exit /b
)

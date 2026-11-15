@echo off
rem ObsidiNote validation kit: the OneNote search probe only (P3) - double-click to run it.
rem It asks Copilot (Work IQ on, your own access) to find the newest marker pages in the notebook ObsidiNote-Probe.
rem Run "Run Validation with write tests.cmd" once first (it makes a marker page), then run this after 1 hour and after 24 hours.
rem Read only: nothing is written. The log goes to your Desktop (found yes/no and timings only; safe to send).
rem One ( ) block with exit /b inside: cmd reads all of it before running, so an update that replaces this file while it runs cannot make cmd read on in the new file.
(
  cd /d "%~dp0"
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Run-Validation.ps1" -Stage V5 -Probe P3 -NoPrompt %*
  pause
  exit /b
)

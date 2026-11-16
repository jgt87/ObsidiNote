@echo off
rem ObsidiNote validation kit: OneNote only (stage V2), read only - double-click to run it.
rem It counts your open notebooks and tries every read method of OneNote's API once on the first page OneNote lists:
rem reading the hierarchy, a page, an image, its links, OneNote's own search, Meta search, special folders and windows.
rem Nothing is written, no dialog opens and OneNote's window does not change. No Copilot, no Edge window.
rem The log goes to your Desktop (statuses, timings, counts and OneNote error codes only; safe to send).
rem One ( ) block with exit /b inside: cmd reads all of it before running, so an update that replaces this file while it runs cannot make cmd read on in the new file.
(
  cd /d "%~dp0"
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Run-Validation.ps1" -Stage V2 -NoCopilot -NoPrompt %*
  pause
  exit /b
)

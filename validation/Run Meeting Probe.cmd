@echo off
rem ObsidiNote validation kit: the meetings probe only (P10) - double-click to run it.
rem It asks Copilot (Work IQ on, your own access) for your Teams meetings of the last 7 days, then for every
rem meeting of TODAY (-MeetingDay today; another day: add -MeetingDay yyyy-mm-dd), and turns two of that day's
rem meetings with a transcript, recap or notes into structured notes, one question each. Read only: nothing is written.
rem The log goes to your Desktop: ObsidiNote-validation-<date>.txt (counts only, no titles, names, dates or text; safe to send).
rem One ( ) block with exit /b inside: cmd reads all of it before running, so an update that replaces this file while it runs cannot make cmd read on in the new file.
(
  cd /d "%~dp0"
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Run-Validation.ps1" -Stage V5 -Probe P10 -NoPrompt -MeetingDay today %*
  pause
  exit /b
)

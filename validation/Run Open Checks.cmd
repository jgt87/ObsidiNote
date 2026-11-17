@echo off
rem ObsidiNote validation kit: only the checks still open after the v0.12.4 run of 2026-11-16 - double-click to run it.
rem V3: Copilot connect and the Work IQ switch. V5: only the meetings probe, for TODAY's meetings (P10 -MeetingDay today).
rem V6: the notebook selection probe (shows each open notebook in OneNote in turn, then your page again) and the write
rem tests: Add, "Check for the answer", Ask, a link in another page's text after Archive, the journal's day page. They write
rem ONLY into the notebook ObsidiNote-Validation and put back what they made (OneNote's Deleted Pages). It asks nothing.
rem The log goes to your Desktop: ObsidiNote-validation-<date>.txt (counts only, no titles, names, dates or text; safe to send).
rem One ( ) block with exit /b inside: cmd reads all of it before running, so an update that replaces this file while it runs cannot make cmd read on in the new file.
(
  cd /d "%~dp0"
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Run-Validation.ps1" -Stage V3,V5,V6 -Probe P10 -NoPrompt -MeetingDay today -WriteTest -SelectNotebooks %*
  pause
  exit /b
)

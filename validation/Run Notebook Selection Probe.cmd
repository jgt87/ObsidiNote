@echo off
rem ObsidiNote validation kit: the notebook selection probe (V6 -SelectNotebooks) - double-click to run it.
rem With OneNote open, it shows each open notebook in OneNote in turn and reads every ObsidiNote vault each time,
rem to see whether what OneNote returns for a vault depends on the notebook it shows. It writes nothing; OneNote's
rem window switches notebooks while it runs and shows your page again at the end.
rem The log goes to your Desktop: ObsidiNote-validation-<date>.txt (counts only, notebooks as "notebook #1"; safe to send).
rem One ( ) block with exit /b inside: cmd reads all of it before running, so an update that replaces this file while it runs cannot make cmd read on in the new file.
(
  cd /d "%~dp0"
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Run-Validation.ps1" -Stage V6 -NoCopilot -NoPrompt -SelectNotebooks %*
  pause
  exit /b
)

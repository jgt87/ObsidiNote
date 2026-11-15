@echo off
rem ObsidiNote validation kit: the vault checks only (stage V6), read only - double-click to run them.
rem It reads your open notebooks and vaults: which notebook OneNote has selected, the index, the knowledge graph,
rem the settings and the Markdown export (built in memory, never saved). No Copilot, no Edge window, nothing written.
rem Run it twice: once with ANOTHER notebook selected in OneNote, once with the vault's notebook selected (RB-05 step 3a).
rem The log goes to your Desktop (counts and yes/no only; safe to send).
rem One ( ) block with exit /b inside: cmd reads all of it before running, so an update that replaces this file while it runs cannot make cmd read on in the new file.
(
  cd /d "%~dp0"
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Run-Validation.ps1" -Stage V6 -NoCopilot -NoPrompt %*
  pause
  exit /b
)

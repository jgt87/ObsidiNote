# Probes

Go/no-go tests from ../FEASIBILITY.md. Windows PowerShell 5.1, no install, no admin.
Every probe writes only into its own notebook, **ObsidiNote-Probe**.

## On a Microsoft 365 business tenant with a Copilot licence

1. Open desktop OneNote (Microsoft 365 version) and sign in with the business account.
   Make sure at least one notebook stored in OneDrive for Business is open.
2. P1, the OneNote write test:
   ```
   powershell -NoProfile -ExecutionPolicy Bypass -File .\p1-roundtrip.ps1
   ```
   If the probe notebook ends up in the wrong place, pass the folder explicitly:
   `-BasePath https://<tenant>-my.sharepoint.com/personal/<user>/Documents/`
   Pass = every line starts with OK and the checks print True. In OneNote, click the links on
   both pages to confirm they open.
3. P3, Copilot grounding on OneNote: in M365 Copilot Chat (Work IQ on), paste
   `p3-copilot-prompt.txt`. Do it right after P1, after about 1 hour, and after about 24 hours.
   Record FOUND or NOT FOUND and the time.
4. P4, the same check for Loop: create a Loop page, type the line
   `OBSN-PROBE-LOOP-3M8W`, then ask the same question with that marker.
5. Cleanup: `p1-cleanup.ps1` closes the notebook. Then delete the ObsidiNote-Probe folder in
   OneDrive.

`p1-find.ps1` shows what OneNote search returns. It is unreliable until Windows Search has
indexed the pages.

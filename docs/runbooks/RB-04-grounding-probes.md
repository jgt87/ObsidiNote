# RB-04 Grounding probes P3, P4, P7 and P8

These probes check what Microsoft 365 Copilot can read for ObsidiNote, with Work IQ (your
Microsoft 365 data) switched on. They run in stage V5 of the kit. They decide how ObsidiNote makes
link summaries, and whether Copilot's own search over OneNote is of any use.

| Probe | Question | Pass if |
|---|---|---|
| P3 | Does Copilot find a unique marker on a OneNote page? | Found, and it names the marker page. Right after writing it may not be found yet: that is why it runs again after 1 hour and 24 hours. |
| P4 | The same for a Loop page (optional) | Found |
| P7 | Can Copilot summarize a SharePoint page and a OneDrive document you can open, in ObsidiNote's fixed shape? | "summary made yes", "access ok", "JSON valid yes" |
| P8 | The same for a public web page, with Work IQ off and on | "summary made yes", "JSON valid yes" |

## Why the addresses are not logged

The addresses you paste can show site names, folder names and file names, so the kit never writes
them anywhere. They are kept in memory only while Copilot reads them. The log keeps only: found
yes/no, access, whether the answer had the expected shape, how long the answer was, and how long it
took. The same holds for the markers, the prompts and Copilot's answers.

## Steps

1. Make sure ObsidiNote's Copilot works: RB-02 done, and in RB-03 stage V3 showed
   `[OK] Copilot reply`.
   - If not, send this: the Desktop log of RB-03 first.

2. Pick two addresses before you start (copy them into Notepad):
   - P7 SharePoint page: open a SharePoint page you can read (for example a team site's home
     page or news post), copy the address from the address bar. It contains `.sharepoint.com`.
   - P7 OneDrive document: in OneDrive, open a Word or PowerPoint file of your own, choose
     **Share > Copy link** or copy the address bar. It contains `-my.sharepoint.com`.
   - Prefer something harmless. The address is not logged, and Copilot reads it only with your
     own access.

3. Optional, P4 Loop: create a Loop page (loop.cloud.microsoft) and type one line such as
   `OBSN-P4-ABC123` (letters and digits of your own choice after `OBSN-P4-`). Write the marker
   down.

4. Run stage V5 with the write test (it puts a new P3 marker page into `ObsidiNote-Probe`). In
   **Windows PowerShell**:
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\Programs\ObsidiNote\validation\Run-Validation.ps1" -Stage V5 -WriteTest
   ```
   When asked:
   - P4: type the Loop marker, or press Enter to skip.
   - P7: paste the SharePoint address, then the OneDrive address. Press Enter to skip one.
   - What you should see:
     - `[OK] P3 marker page  new marker page in ObsidiNote-Probe`
     - `P3 OneNote grounding  marker age 0.0 h: found no ...` as `[INFO]` is normal right away.
     - `P7 SharePoint page` and `P7 OneDrive document` with `summary made yes; access ok; JSON valid yes`.
     - `P8 web, Work IQ off` and `P8 web, Work IQ on` lines.
   - If not, send this: the two newest Desktop files. A `[WARN]` with "access no-access" means
     Copilot could not open the address; say whether you can open it in your normal browser.

5. Each prompt takes 20 to 60 seconds. Copilot may show the prompts in ObsidiNote's Edge window;
   that is expected. Do not type in that window while the kit runs.

6. After about 1 hour, and again after about 24 hours, run V5 without `-WriteTest`:
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\Programs\ObsidiNote\validation\Run-Validation.ps1" -Stage V5
   ```
   Press Enter at the P4 and P7 questions (they were done in step 4).
   - What you should see: `P3 OneNote grounding  marker age 1.0 h: found ...` and later
     `marker age 24.0 h: found ...`. Found yes and "names the marker page yes" is a pass.
     Found no after 24 hours is a valid result too: it means ObsidiNote must not rely on Copilot's
     own search over OneNote.
   - If not, send this: the Desktop files of each run.

7. Send all Desktop files (RB-00).

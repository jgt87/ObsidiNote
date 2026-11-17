# RB-04 Grounding probes P3, P4, P7, P8 and P10

These probes check what Microsoft 365 Copilot can read for ObsidiNote, with Work IQ (your
Microsoft 365 data) switched on. They run in stage V5 of the kit. They decide how ObsidiNote makes
link summaries, and whether Copilot's own search over OneNote is of any use.

| Probe | Question | Pass if |
|---|---|---|
| P3 | Does Copilot find a unique marker on a OneNote page? | Found, and it names the marker page. Right after writing it may not be found yet: that is why it runs again after 1 hour and 24 hours. |
| P4 | The same for a Loop page (optional) | Found |
| P7 | Can Copilot summarize a SharePoint page and a OneDrive document you can open, in ObsidiNote's fixed shape? | "summary made yes", "access ok", "JSON valid yes" |
| P8 | The same for a public web page, with Work IQ off and on | "summary made yes", "JSON valid yes" |
| P10 | Can Copilot list your Teams meetings of the last 7 days, list every meeting of one full day, and turn two of that day's meetings with a transcript, recap or notes into structured notes (attendees, decisions, actions with owner and due date), one question per meeting? Decides whether ObsidiNote gets an "Add a day's meetings" step. | "P10 meetings list" with meetings > 0; "P10 day's meetings" with meetings > 0 and "0 of another day"; "P10 meeting notes 1" and "2" with "read yes", "date matches the day yes" and decisions or actions > 0 |

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
     - `P10 meetings list  N meetings in the last 7 days; with a transcript ..., a recap ..., notes
       ..., a link ...`, then `P10 day's meetings  N meetings on the busiest day of the last 7 days
       (0 of another day); ...`, then `P10 meeting notes 1` and `P10 meeting notes 2  read yes
       (based on transcript|recap|notes); date matches the day yes; N attendees, N decisions, N
       actions (...)`. Best right after a week with a few Teams meetings that had transcription, a
       Copilot recap or Facilitator notes. The log has counts only: no meeting titles, names, dates
       or text.
   - If not, send this: the two newest Desktop files. A `[WARN]` with "access no-access" means
     Copilot could not open the address; say whether you can open it in your normal browser.
     For P10, also say (no titles) whether you had meetings with transcription or a recap in the
     last 7 days, and whether Copilot in Teams shows their recap to you.

   - P10 alone, for today's meetings (run it late in a day with Teams meetings that had
     transcription, a Copilot recap or Facilitator notes): double-click **Run Meeting Probe.cmd** in
     `%LOCALAPPDATA%\Programs\ObsidiNote\validation`. It asks nothing and writes nothing; it shows
     the four `P10` lines and puts the log on your Desktop. It takes 2 to 15 minutes (four questions).
     The day line says "today".
   - P10 for a day you choose (a day with several meetings that had transcription, a recap or
     notes), in **Windows PowerShell**:
     ```powershell
     powershell -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\Programs\ObsidiNote\validation\Run-Validation.ps1" -Stage V5 -Probe P10 -NoPrompt -MeetingDay 2026-11-12
     ```
     Put your day in place of `2026-11-12`. The date is not written to the log; the line says
     "on the day given with -MeetingDay".
   - P7 and P8 alone: double-click **Run Link Probes.cmd**; it asks for the two addresses of step 2.
     P4 alone: double-click **Run Loop Probe.cmd**; it asks for the marker of step 3.

5. Each prompt takes 20 to 60 seconds. Copilot may show the prompts in ObsidiNote's Edge window;
   that is expected. Do not type in that window while the kit runs.

6. After about 1 hour, and again after about 24 hours, double-click **Run OneNote Search Probe.cmd**
   in `%LOCALAPPDATA%\Programs\ObsidiNote\validation` (P3 only; it asks nothing). Or, for all of V5
   without `-WriteTest`:
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\Programs\ObsidiNote\validation\Run-Validation.ps1" -Stage V5
   ```
   and press Enter at the P4 and P7 questions (they were done in step 4).
   - What you should see: `P3 OneNote grounding  marker age 1.0 h: found ...` and later
     `marker age 24.0 h: found ...`. Found yes and "names the marker page yes" is a pass.
     Found no after 24 hours is a valid result too: it means ObsidiNote must not rely on Copilot's
     own search over OneNote.
   - If not, send this: the Desktop files of each run.

7. Send all Desktop files (RB-00).

8. **Today's meetings in the window** (after the update that has it, late in a day with Teams
   meetings that had transcription, a recap or notes). On the home page, under the box, press
   **Fetch today's meetings**.
   - What you should see: within about a minute, today's meetings with their time and what Copilot
     can read ("Transcript", "Recap", "Notes" or "Nothing Copilot can read"); the ones it can read
     are ticked. Untick all but one, press **Add 1 meeting**: the row says "Copilot is reading the
     meeting...", then "Adding to your wiki...", then "Added as ..." (or "Waiting for Copilot").
     The page is under **Meetings** in OneNote with attendees, summary, decisions and actions, and
     **History** lists it with **Undo**. Undo it if it was only a test.
   - If not, send this: the row's message word for word (it holds no meeting text), and the newest
     `obsidinote.log` (counts only).

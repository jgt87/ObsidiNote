# RB-03 Run the validation kit

The kit checks this PC, OneNote, Copilot and the ObsidiNote window, one line per check, and writes
a log to your Desktop that you can send back. It is in the folder
`%LOCALAPPDATA%\Programs\ObsidiNote\validation`.

## The stages

| Stage | What it checks | Writes anything? | Time |
|---|---|---|---|
| V1 This computer | The start checks (PowerShell, OneNote, Edge and its policies, the debug port, the Edge profile, GitHub), the Edge policy values, ports 9334 and 8767, OneNote running, versions, the install folder against its manifest | No | 5 s |
| V2 OneNote | Your open notebooks: counts of notebooks, section groups, sections and pages, where each notebook lives, which are ObsidiNote vaults, COM speed; then every read method of OneNote's API tried once on the first page OneNote lists (`API ...` lines) | No (with `-WriteTest`: yes, only in `ObsidiNote-Probe`) | 5 to 20 s (1 min with `-WriteTest`) |
| V3 Copilot | The Edge profile's account type and single sign-on, then Copilot in ObsidiNote's Edge window: connect, one harmless prompt, the answer checked | No | 1 min |
| V4 Window | Starts the window's server on a test port (not 8767), calls it, checks that bad requests are refused, stops it | No | 5 s |
| V5 Grounding | Probes P3, P4, P7, P8 and P10: can Copilot find a marker on a OneNote page, summarize links, and list your Teams meetings, all meetings of one day, and turn two of them into notes. See RB-04 | Only with `-WriteTest`: one marker page in `ObsidiNote-Probe` | 5 to 18 min (P10 alone, with `Run Meeting Probe.cmd`: 2 to 15 min) |
| V6 Vaults | Vaults, index completeness, knowledge graph counts, Add and Ask. Shows `[SKIP] not in this version yet` until the version has them. See RB-05 | Only with `-WriteTest`: only in `ObsidiNote-Validation` | 1 to 5 min |

## Options

| Option | Meaning |
|---|---|
| `-Stage V1,V3` | Run only these stages. Without it, all stages run, in order. |
| `-WriteTest` | Also run the write tests. They write ONLY into two throwaway notebooks that the kit creates next to your first OneDrive notebook: `ObsidiNote-Probe` (sections `Notes`, `P1b size`, `P1c home`, `P1c moved`, `P3 markers`) and `ObsidiNote-Validation` (a test vault). Your own notebooks are only read. |
| `-NoCopilot` | Skip Copilot. No Edge window opens. |
| `-NoPrompt` | Ask nothing. The steps that need you (P1c by hand, P4, P7) are skipped. |
| `-ProbeBasePath <address>` | Where to create the test notebooks, when the kit cannot find a OneDrive notebook. Use your OneDrive Documents address. |
| `-TestPort <n>` | The port for V4 (default 18768). |
| `-Probe P10` | In stage V5, run only the named probes (`P3`, `P4`, `P7`, `P8`, `P10`; several with commas). Without it, all of them run. A name that is not a probe gives a `[FAIL] Probe` line that lists the probes, and Copilot is not opened for it. |
| `-SelectNotebooks` | In stage V6: show each open notebook in OneNote in turn and read every vault each time (RB-05, step 3b). Writes nothing; OneNote shows your page again at the end. |
| `-MeetingDay 2026-11-12` | The day P10 lists all meetings of and reads two of (written yyyy-mm-dd, or `today` for this computer's date). Without it, P10 takes the busiest day of the last 7 days. The date is not written to the log; a value that is not a date gives a `[FAIL] P10 day's meetings` line. |
| `-PublicUrl <address>` | The public web page P8 summarizes (default: a public documentation page). |
| `-SharePointUrl <address>`, `-OneDriveUrl <address>` | The addresses for P7, so the kit does not ask for them. They are not written to the log. |
| `-OutDir <folder>` | Where the two result files go (default: your Desktop). |

The files to double-click in the `validation` folder:

| File | What it runs |
|---|---|
| `Run Validation.cmd` | All stages, read only. |
| `Run Validation with write tests.cmd` | All stages with `-WriteTest`. Run it once before the OneNote search probe: it makes the marker page. |
| `Run Open Checks.cmd` | Only what is still open after the v0.12.4 run of 2026-11-16: `-Stage V3,V5,V6 -Probe P10 -NoPrompt -MeetingDay today -WriteTest -SelectNotebooks`. Copilot and its Work IQ switch, today's meetings, the notebook selection probe (OneNote switches notebooks, then shows your page again), and the write tests in ObsidiNote-Validation (Add, "Check for the answer", Ask, a link in another page after Archive). It asks nothing. Run it on a day with meetings, after at least one of them has ended. |
| `Run Meeting Probe.cmd` | Only the meetings probe, for today's meetings: `-Stage V5 -Probe P10 -NoPrompt -MeetingDay today`. It asks nothing and writes nothing (RB-04, step 4). |
| `Run Notebook Selection Probe.cmd` | Only the vault checks plus the selection probe: `-Stage V6 -NoCopilot -NoPrompt -SelectNotebooks`. OneNote switches notebooks while it runs; nothing is written (RB-05, step 3b). |
| `Run OneNote Search Probe.cmd` | Only P3: `-Stage V5 -Probe P3 -NoPrompt`. Run it 1 hour and 24 hours after the write tests. It asks nothing and writes nothing (RB-04, step 6). |
| `Run Link Probes.cmd` | Only P7 and P8: `-Stage V5 -Probe P7,P8`. It asks for a SharePoint page address and a OneDrive document address (Enter skips one) and writes nothing (RB-04, steps 2 and 4). |
| `Run Loop Probe.cmd` | Only P4: `-Stage V5 -Probe P4`. It asks for the marker you typed on a Loop page and writes nothing (RB-04, step 3). |
| `Run Vault Check.cmd` | Only the vault checks, read only: `-Stage V6 -NoCopilot -NoPrompt`. No Edge window opens and nothing is written (RB-05, steps 3 and 3a). |
| `Run OneNote API Probe.cmd` | Only OneNote, read only: `-Stage V2 -NoCopilot -NoPrompt`. It counts your notebooks and tries every read method of OneNote's API once (step 6 below). Nothing is written, no dialog opens and OneNote's window does not change. |

## Steps

1. Open **OneNote** and wait until it shows your notebooks. ObsidiNote itself may run or not.
   - What you should see: your notebooks in OneNote.
   - If not, send this: a screenshot of OneNote.

2. First pass, read only: open `%LOCALAPPDATA%\Programs\ObsidiNote\validation` and double-click
   **Run Validation.cmd**.
   - It may ask questions for P4 and P7. Press Enter to skip them for now (RB-04 explains them).
   - What you should see: headings V1 to V6, one line per check, then `Summary: ...` and
     `Result: OK` (or `WARN`). The last lines name the two files on your Desktop. Expect
     `[SKIP]` lines for the write tests and, before the release with Add, for V6.
   - If not, send this: the two Desktop files. If the window closed before you could read it,
     send a screenshot of what you saw and the two files if they exist.

3. Second pass, with the write tests: in the same folder, double-click
   **Run Validation with write tests.cmd**. (The same from **Windows PowerShell**:
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\Programs\ObsidiNote\validation\Run-Validation.ps1" -WriteTest
   ```
   )
   - During P1c, OneNote jumps to a page in `ObsidiNote-Probe` and back. If OneNote does not let
     the kit move a page, the kit asks you to drag the page `P1c move me` from section
     `P1c home` to section `P1c moved` in OneNote, then press Enter. Type `s` and Enter to skip.
   - What you should see: `[OK] ObsidiNote-Probe created` (or `opened`), then `P1 create`,
     `P1 write`, `P1 read back`, `P1 owned outline` with `[OK]`, a `P1b Meta size` line, two
     `P1c` lines, `P3 marker page`, and in OneNote the new notebooks `ObsidiNote-Probe` and, from
     the release with Add, `ObsidiNote-Validation`.
   - If not, send this: the two newest Desktop files.

4. After 1 hour and after 24 hours, run V5 again (RB-04 step 6). Leave `ObsidiNote-Probe` open in
   OneNote until then.

5. Send the Desktop files of every pass (RB-00, "How to send the results back").

6. OneNote's API, once: open a notebook that has at least one page with a picture (any notebook;
   it is only read), then double-click **Run OneNote API Probe.cmd**.
   - What you should see: under V2, one `API ...` line per read method (`GetHierarchy`,
     `GetHierarchyParent`, `GetPageContent`, `GetBinaryPageContent`, `GetHyperlinkToObject`,
     `GetWebHyperlinkToObject`, `FindPages`, `FindMeta`, `GetSpecialLocation`, `Windows`), each
     `[OK]` with a time, and a last line `[INFO] API not tried` that names the methods that write.
     `GetWebHyperlinkToObject` is `[INFO]` for a notebook on this PC (it has no web address).
     `GetBinaryPageContent` is `[SKIP]` when the first pages hold no picture, ink or file.
   - If not, send this: the two newest Desktop files. A `[FAIL]` line names OneNote's error code.

## Cleaning up (after the 24-hour run)

1. In OneNote, right-click `ObsidiNote-Probe` and choose **Close This Notebook**. Do the same for
   `ObsidiNote-Validation`.
2. In OneDrive, delete the folders `ObsidiNote-Probe` and `ObsidiNote-Validation` if you want them
   gone. Nothing else was created.
3. The Desktop log files can be deleted after you sent them.

## Exit codes (for the curious)

0 = no `[FAIL]` line, 1 = at least one `[FAIL]` (also for a `-Probe` name that is not a probe),
2 = an unknown stage name was given.

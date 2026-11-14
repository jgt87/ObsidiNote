# RB-03 Run the validation kit

The kit checks this PC, OneNote, Copilot and the ObsidiNote window, one line per check, and writes
a log to your Desktop that you can send back. It is in the folder
`%LOCALAPPDATA%\Programs\ObsidiNote\validation`.

## The stages

| Stage | What it checks | Writes anything? | Time |
|---|---|---|---|
| V1 This computer | The start checks (PowerShell, OneNote, Edge and its policies, the debug port, the Edge profile, GitHub), the Edge policy values, ports 9334 and 8767, OneNote running, versions, the install folder against its manifest | No | 5 s |
| V2 OneNote | Your open notebooks: counts of notebooks, section groups, sections and pages, where each notebook lives, which are ObsidiNote vaults, COM speed | No (with `-WriteTest`: yes, only in `ObsidiNote-Probe`) | 5 s (1 min with `-WriteTest`) |
| V3 Copilot | The Edge profile's account type and single sign-on, then Copilot in ObsidiNote's Edge window: connect, one harmless prompt, the answer checked | No | 1 min |
| V4 Window | Starts the window's server on a test port (not 8767), calls it, checks that bad requests are refused, stops it | No | 5 s |
| V5 Grounding | Probes P3, P4, P7, P8: can Copilot find a marker on a OneNote page, and summarize links. See RB-04 | Only with `-WriteTest`: one marker page in `ObsidiNote-Probe` | 3 to 7 min |
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

## Cleaning up (after the 24-hour run)

1. In OneNote, right-click `ObsidiNote-Probe` and choose **Close This Notebook**. Do the same for
   `ObsidiNote-Validation`.
2. In OneDrive, delete the folders `ObsidiNote-Probe` and `ObsidiNote-Validation` if you want them
   gone. Nothing else was created.
3. The Desktop log files can be deleted after you sent them.

## Exit codes (for the curious)

0 = no `[FAIL]` line, 1 = at least one `[FAIL]`, 2 = an unknown stage name was given.

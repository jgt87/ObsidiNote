# RB-05 Vaults, Add, Ask and the knowledge graph

**Available from the first release with Add (a version after v0.3.0).** Before that version, stage
V6 shows `[SKIP] ... not in this version yet` for every check. That is the expected result, and
you can skip this runbook.

Stage V6 checks the parts of ObsidiNote that write: the vault structure, the central index, the
knowledge graph's data, Add and Ask.

| Check | What it does | Writes? |
|---|---|---|
| Vaults | Lists the ObsidiNote vaults in your open notebooks (counts only) | No |
| Index of Vault n | Loads each vault's index and checks that every page is listed in it | No |
| Graph of notebook #n | Builds the knowledge graph's data for each open notebook (counts of pages, topics, links) | No |
| Markdown export of Vault n | Builds the Markdown export of each vault in memory and drops it (counts of pages, unreadable pages, size, time); nothing is saved | No |
| Dev vault | Creates or continues the test vault `ObsidiNote-Validation` (a new notebook next to your first OneDrive notebook), runs it twice, checks that ObsidiNote refuses writes into every other notebook, and writes its index | Only `ObsidiNote-Validation`, with `-WriteTest` |
| Add (synthetic) and Undo | Adds a made-up sentence about tidal gardens to the test vault with Copilot, then undoes it (the page goes to OneNote's Deleted Pages) | Only `ObsidiNote-Validation`, with `-WriteTest` |
| Check for the answer | Adds a second made-up sentence with a wait of 1 second, so Copilot is still answering and the item waits in the Intake (Copilot is left working, never stopped). Then checks for the answer every 10 seconds (at most 3 minutes) until the page is filed, and undoes it | Only `ObsidiNote-Validation`, with `-WriteTest` |
| Update waits for the answer | Adds the public link `https://example.org/`, updates it with a wait of 1 second so the update waits in the Intake, checks for the answer every 10 seconds (at most 3 minutes) until the update is done, then undoes the link page | Only `ObsidiNote-Validation`, with `-WriteTest` |
| Ask (synthetic) | Asks "What do my notes say about tidal gardens?" against the test vault | No (Ask never writes) |

## Steps

1. Update ObsidiNote (RB-01) and check that `version.txt` shows the release with Add.
   - If not, send this: the version.

2. Open OneNote with your notebooks. Make sure RB-02 works (Copilot connected).

3. Read-only pass. In **Windows PowerShell**:
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\Programs\ObsidiNote\validation\Run-Validation.ps1" -Stage V6
   ```
   - What you should see: `[OK] Vaults  N found`, one `Vault n` line per vault, `Index of Vault n`
     with "pages missing from the index: 0", `Graph of ...` lines with counts, and
     `[OK] Markdown export of Vault n  N pages, 0 unreadable, ... (in memory, not saved)`. No file
     appears in Downloads or anywhere else. The write checks show `[SKIP] write tests not run`.
   - A `[WARN] Markdown export ...` line with unreadable pages > 0: send the files; the export still
     works, those pages get a line saying they could not be read.
   - If not, send this: the two newest Desktop files.

4. Write pass, only in the test vault:
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\Programs\ObsidiNote\validation\Run-Validation.ps1" -Stage V6 -WriteTest
   ```
   - What you should see:
     - `[OK] Dev vault  ObsidiNote-Validation created` (the next time: `continued`)
     - `[OK] Dev vault again  second run created 0 sections; same vault: yes`
     - `[OK] Write guard  refused N of N writes into other notebooks`
     - `[OK] Dev vault index ...`
     - `[OK] Add (synthetic)  status added ...` and `[OK] Undo  status undone ...`
     - `[OK] Check for the answer (waiting)  the item waits in the Intake; request reference given: yes`,
       then one or more `[INFO] Check for the answer (check n)  status still-waiting ...` lines,
       then `[OK] Check for the answer  final status added after n check(s), s s` and
       `[OK] Check for the answer (undo)  status undone`. A `[WARN] ... status added instead of
       waiting` line means Copilot answered within 1 second; run the kit again.
     - In the Copilot window during that check: Copilot keeps answering the second sentence; nothing
       presses Stop. ObsidiNote waits until that answer is done before it types anything else.
     - `[OK] Update waits for the answer (link added)`, `[OK] Update waits for the answer (waiting)`,
       `[INFO] ... (check n)` lines, then `[OK] Update waits for the answer  final status updated`
       (or `unchanged`) and `[OK] Update waits for the answer (undo)  status undone`. A
       `[FAIL] ... final status mismatch` line means Copilot did not repeat the reference or the link
       it read: send the files.
     - `[OK] Ask (synthetic)  status ...; writes 0`
     - In OneNote: a notebook `ObsidiNote-Validation` with the sections `00 Index`, `01 Intake`,
       `Notes` and the other fixed sections. A test vault made before this version had `01 Inbox`:
       it is renamed to `01 Intake` the first time the kit (or ObsidiNote) opens it, and its pages
       stay. After the Undo, the added pages are in that notebook's Deleted Pages.
   - If not, send this: the two newest Desktop files. For `[FAIL] Check for the answer`, also say
     whether the Copilot window showed an answer to the sentence about salt marsh hay.
   - If not, send this: the two newest Desktop files. A `[FAIL] Write guard` line is important:
     stop using the write tests and send the files at once.

5. Open the ObsidiNote window (start ObsidiNote). In the notebook switcher, `ObsidiNote-Validation`
   is listed as a vault. Do not make it your active vault unless you want to; your own vault stays
   as it was.

6. Check for the answer in the window, with your own vault (optional, writes into it): paste a
   SharePoint page link that once gave "Copilot gave no answer". If Copilot needs longer than the
   wait, the result says "Waiting for Copilot" and the item waits in your Intake.
   - What you should see: Copilot keeps working in its window (not stopped). After it has answered,
     press **Check for the answer**: the normal Add result with the page placed in the index. Too
     early: "Still waiting", try again later. The Intake item in OneNote shows `status: waiting`
     until then, `status: linked` after.
   - If not, send this: the two newest Desktop files and which message the window showed.

7. Export as Markdown in the window (reads only): in **Knowledge graph**, open a page and press
   **Export as Markdown**; in **List**, press **Export as Markdown** next to a topic; in the side
   bar, press **Export all as Markdown**.
   - What you should see: each button shows "Exported" for a few seconds and the browser's
     downloads list a `.md` file (a page) or a `... - Markdown.zip` (a topic, everything). Open the
     zip: one folder named after the vault, a folder per topic, one `.md` per page, starting with
     `---` front matter; links between pages read `[[Page title]]`. Delete the files afterwards if
     your organisation asks for that: ObsidiNote keeps no copy.
   - If not, send this: the two newest Desktop files, which button you pressed and the message next
     to it (no file contents).

8. Clean up when asked to (RB-03, "Cleaning up").

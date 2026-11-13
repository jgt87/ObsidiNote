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
| Dev vault | Creates or continues the test vault `ObsidiNote-Validation` (a new notebook next to your first OneDrive notebook), runs it twice, checks that ObsidiNote refuses writes into every other notebook, and writes its index | Only `ObsidiNote-Validation`, with `-WriteTest` |
| Add (synthetic) and Undo | Adds a made-up sentence about tidal gardens to the test vault with Copilot, then undoes it (the page goes to OneNote's Deleted Pages) | Only `ObsidiNote-Validation`, with `-WriteTest` |
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
     with "pages missing from the index: 0", and `Graph of ...` lines with counts. The write
     checks show `[SKIP] write tests not run`.
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
     - `[OK] Ask (synthetic)  status ...; writes 0`
     - In OneNote: a notebook `ObsidiNote-Validation` with the sections `00 Index`, `01 Inbox`,
       `Notes` and the other fixed sections. After the Undo, the added page is in that
       notebook's Deleted Pages.
   - If not, send this: the two newest Desktop files. A `[FAIL] Write guard` line is important:
     stop using the write tests and send the files at once.

5. Open the ObsidiNote window (start ObsidiNote). In the notebook switcher, `ObsidiNote-Validation`
   is listed as a vault. Do not make it your active vault unless you want to; your own vault stays
   as it was.

6. Clean up when asked to (RB-03, "Cleaning up").

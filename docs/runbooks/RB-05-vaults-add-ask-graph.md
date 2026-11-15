# RB-05 Vaults, Add, Ask and the knowledge graph

**Available from the first release with Add (a version after v0.3.0).** Before that version, stage
V6 shows `[SKIP] ... not in this version yet` for every check. That is the expected result, and
you can skip this runbook.

Stage V6 checks the parts of ObsidiNote that write: the vault structure, the central index, the
knowledge graph's data, Add and Ask.

| Check | What it does | Writes? |
|---|---|---|
| Vaults | Lists the ObsidiNote vaults in your open notebooks (counts only) | No |
| Notebook reads, Reads of notebook #n | For each open notebook: whether it is the notebook selected in OneNote, how many sections OneNote lists for it, how many pages its `00 Index` section has, how many of those carry ObsidiNote's page data, and whether the vault's state page is found (counts and yes/no only). It selects nothing in OneNote | No |
| Index of Vault n | Loads each vault's index and checks that every page is listed in it | No |
| Graph of notebook #n | Builds the knowledge graph's data for each open notebook (counts of pages, topics, links) | No |
| Markdown export of Vault n | Builds the Markdown export of each vault in memory and drops it (counts of pages, unreadable pages, size, time); nothing is saved | No |
| Dev vault | Creates or continues the test vault `ObsidiNote-Validation` (a new notebook next to your first OneDrive notebook), runs it twice, checks that ObsidiNote refuses writes into every other notebook, and writes its index | Only `ObsidiNote-Validation`, with `-WriteTest` |
| Add (synthetic) and Undo | Adds a made-up sentence about tidal gardens to the test vault with Copilot, then undoes it (the page goes to OneNote's Deleted Pages) | Only `ObsidiNote-Validation`, with `-WriteTest` |
| Check for the answer | Adds a second made-up sentence with a wait of 1 second, so Copilot is still answering and the item waits in the Intake (Copilot is left working, never stopped). Then checks for the answer every 10 seconds (at most 3 minutes) until the page is filed, and undoes it | Only `ObsidiNote-Validation`, with `-WriteTest` |
| Update waits for the answer | Adds the public link `https://example.org/`, updates it with a wait of 1 second so the update waits in the Intake, checks for the answer every 10 seconds (at most 3 minutes) until the update is done, then undoes the link page | Only `ObsidiNote-Validation`, with `-WriteTest` |
| Upgrade plan of Vault n | Counts the link pages the next start would move to another section (new internal-link rule); moves nothing | No |
| Settings of Vault n | How many of the vault's settings are in OneNote and which are missing (names only, no values); the next start adds the missing ones | No |
| Upgrade move | Makes a made-up link page with a company-tenant address under Web links (as an older version filed it), lets the upgrade move it to Internal links, checks it is found again there, then undoes it | Only `ObsidiNote-Validation`, with `-WriteTest` |
| Link it | Makes two made-up pages in the test vault, links the first to the second as "Link it" does in the window, checks that a second "Link it" writes nothing, then undoes both pages. No Copilot needed | Only `ObsidiNote-Validation`, with `-WriteTest` |
| Undo of a linked page | Makes two made-up pages, the first with a link to the second (in its properties and as a link in its own text), undoes the second, then checks that the first has no link to it left and that its text says "(deleted: ...)" where the link was; then undoes the first. No Copilot needed | Only `ObsidiNote-Validation`, with `-WriteTest` |
| Tags | Makes one made-up page, gives it a tag, reads the page back, renames the tag, removes it, then undoes the page. No Copilot needed; the log holds counts only, never the tag | Only `ObsidiNote-Validation`, with `-WriteTest` |
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
     `[INFO] Settings of Vault n  7 of 7 in OneNote` (before the first start of the version with
     vault settings: `0 of 7 ...; missing: ...`),
     `[OK] Markdown export of Vault n  N pages, 0 unreadable, ... (in memory, not saved)`. No file
     appears in Downloads or anywhere else. The write checks show `[SKIP] write tests not run`.
   - A `[WARN] Markdown export ...` line with unreadable pages > 0: send the files; the export still
     works, those pages get a line saying they could not be read.
   - If not, send this: the two newest Desktop files.

3a. Which notebook is selected in OneNote (read only; for pages of your vault that show "read
   only" in the window while ObsidiNote is the writer). Run the command of step 3 twice: once with
   ANOTHER notebook selected in OneNote (click any other notebook in OneNote's notebook list first),
   and once with the vault's notebook selected. The kit selects nothing itself.
   - What you should see, in both runs: `[INFO] Notebook reads  N notebooks open; the selected
     notebook is one of them`, then one `Reads of notebook #n` line per open notebook. For
     the vault's notebook (the `notebook #n` named in the `Vault n` line):
     `selected: yes` in one run and `no` in the other, the same two section counts in
     both runs, `with obsn Meta` equal to `their pages`, `state page found: yes` and
     `vaults listed in it: 1`.
   - The fault this step looks for: with another notebook selected, the vault's notebook shows
     `[WARN] Reads of notebook #n ... state page found: no` (or `sections: 0`, or
     `with obsn Meta: 0`), and `state page found: yes` once it is selected.
   - `selected: not known` in every line: OneNote did not say which notebook it shows;
     send the files anyway.
   - Send this in every case: the two newest Desktop files of BOTH runs, and which run had which
     notebook selected.

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
     - `[OK] Link it  status linked; backlinks 1; ... ms`, then `[OK] Link it again  status
       already-linked`, then `[OK] Link it (undo)  2 of 2 test pages back out`. Two pages titled
       "Validation link source" and "Validation link target" are then in the test vault's Deleted Pages.
     - `[OK] Undo of a linked page  status undone; unlinked 1; text rewritten on 1 page(s); links left
       in the linking page: 0; its text says deleted: True; ... ms`, then `[OK] Undo of a linked page
       (undo)  1 of 1 test pages back out`. Pages titled "Validation undo target" and "Validation
       undo linker" are then in the test vault's Deleted Pages. A `[FAIL]` line with `links left ...:
       1` or `says deleted: False` means OneNote did not take the change: send the files.
     - `[OK] Tags  status tagged; pages changed 1; tags read back from the page: 1; ... ms`, then
       `[OK] Tags (rename)  status renamed; pages changed 1; the page has the new name: True`, then
       `[OK] Tags (remove)  status tagged; tags left on the page: 0`, then `[OK] Tags (undo)  status
       undone`. The log never shows the tag itself.
     - `[OK] Upgrade move  status done; moved 1 of 1; found again in Internal links: True; ... ms`, then
       `[OK] Upgrade move (undo)  status undone`.
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
   **Export as Markdown**; on its **Topic** tab press **Export topic as Markdown**; in **List**, press
   **Export as Markdown** next to a topic. The side bar has no export button any more.
   - What you should see: each button shows "Exported" for a few seconds and the browser's
     downloads list a `.md` file (a page) or a `... - Markdown.zip` (a topic). Open the
     zip: one folder named after the vault, a folder per topic, one `.md` per page, starting with
     `---` front matter; links between pages read `[[Page title]]`. Delete the files afterwards if
     your organisation asks for that: ObsidiNote keeps no copy.
   - If not, send this: the two newest Desktop files, which button you pressed and the message next
     to it (no file contents).

8. Knowledge graph after an update with the Intake fix and the link upgrade: start ObsidiNote once
   (this rewrites your vault's Index pages and moves link pages the new link rule files elsewhere;
   step 3 showed how many as `Upgrade plan of Vault n`). The console shows
   `[OK] Upgrade  N link page(s) moved ...` when it moved any. Open **Knowledge graph**.
   - Your Workday, ServiceNow and similar company links are now under **Internal links** (type
     link-internal), with your own text on them unchanged; public pages stay under **Web links**.
   - What you should see: each page you added appears once, in its topic. No dot under **Unfiled**
     is titled with a link or text you pasted (those were Add requests from the Intake). Unfiled
     only holds pages without a topic, such as pages you typed in OneNote yourself.
   - If not, send this: the two newest Desktop files and how many Unfiled dots you see.

9. Edit a page in the window (writes into your vault): in **Knowledge graph**, open a page you added,
   press **Edit**, change its title and remove or add one link, press **Save**.
   - What you should see: the form closes and the window shows the new title and links at once. In
     OneNote, the page has the new title and its properties block shows the change; the page you
     linked to lists it under "Linked from"; your own text on the page is unchanged. For a link page,
     **Open link** opens the original address in a browser tab.
   - If not, send this: the two newest Desktop files and the message the form showed.

10. Where pasted text came from (no writes until you press Add): in the window's box, paste in turn
    a few lines from an **Outlook mail** (desktop Outlook and Outlook on the web), a **Teams** chat
    message, a **Word** document and a **web page**. After each paste, look at **From** under the box,
    then empty the box (nothing is added).
    - What you should see: Outlook mail, Teams chat, Word document and Web page in that order. Typed
      text (no paste) shows "Typed in ObsidiNote"; a link alone shows no **From** at all.
    - If a guess is wrong, send this: which app you pasted from and what **From** showed (no text).
    - Then, in **Knowledge graph**, press **Sources**: one area per SharePoint site, OneDrive, Teams,
      company services and web sites, and "ObsidiNote notes". Open a page you added before this
      version, press **Edit**, set **From** to Outlook mail, **Save**: in **Sources** it moves to
      the Outlook area.

11. Vault settings in OneNote (writes only the vault's own settings): start ObsidiNote once.
    - What you should see in the console, the first time: `[OK] Settings  settings added to the vault
      in OneNote with their defaults: internalHosts, graphView, labelsHubsOnly, relatedCount,
      linkStaleDays, askIncludeArchived, graphShowArchived`. The next start shows no Settings line.
      If you had `"internalHosts"` in `config\obsidinote.local.json`, open **Settings** in the side
      bar's menu: your addresses are listed there.
    - In **Knowledge graph**, press **Sources**, close the window and start ObsidiNote again: the
      map opens on **Sources**. Press **Topics** to go back.
    - In **Settings**, add `intranet.example.com`, set "Related pages" to 4, tick "Include archived
      pages" under Ask, **Save**, open it again: all three are still there, and Ask's options show
      "Include archived pages" ticked. Put them back (empty, 3, unticked) and **Save**.
    - In **Settings**, "Related pages" is a list from 1 to 10. Type 1000 in the days field: a marked
      line says "7 to 730 only; it becomes 730 when you leave the field" and **Save** is off; press
      Tab: the field shows 730. Put 90 back and press **Cancel**.
    - Run step 3 again: `[INFO] Settings of Vault n  7 of 7 in OneNote`.
    - If not, send this: the two newest Desktop files and the console's Settings line (no addresses).

12. Add or ask window (writes only when you press Add):
    - The box is two lines high when empty and grows when you paste a long text. Auto / Add / Ask
      sit on the left. "Ask reads" shows only after you type a question or press **Ask**.
    - **Add a file**: pick a short Word document of your own, then a PDF, then drag an Outlook mail
      from desktop Outlook onto the box. Each time the box shows "File: <name>" and the text, and
      **From** says "File you dropped". Press **Add** only if you want to keep it. A scanned PDF or
      a picture shows a marked line saying it cannot be read.
    - Drag a Word file from your **OneDrive** folder in File Explorer (and one from a synced
      SharePoint library) onto the box: the line under the box says "is in your OneDrive or
      SharePoint: the page keeps its link". Press **Add**: the page is under **Internal links**;
      **Open link** on it opens the file in the browser. In **Sources**, it sits under OneDrive or
      its SharePoint site. Say whether the link opened the right file (no names or addresses).
    - Paste a few lines from an Outlook mail, press **Add**, then open the page: its **From** says
      Outlook mail (this was lost before this version).
    - In **Recently changed**, click a title: the knowledge graph opens with that page's window.
    - Open **History**: your recent Adds with Added / Updated / Not added; **Open** shows the page.
      **Undo** on a test page you added: it asks first, then the page is in OneNote's Deleted Pages.
    - If an Add says "Waiting for Copilot", go to another view and back: the item is listed under
      **Waiting for Copilot** with **Check for the answer**.
    - Ask a question whose answer is spread over several of your pages (for example a project and
      its meetings). Above the answer: "Combined from N pages in M topics"; each source says "Used in
      N sentences"; **Also read, not used** lists the other pages it read. Open one of those to see
      whether it should have been used, and say so (no titles needed: "yes, 1 of 3 should have").
      In **Settings**, set "Pages Ask may read" to 50, ask the same question again: say whether the
      answer got better, worse or stayed the same, and how long it took.
    - If not, send this: the two newest Desktop files, which file type (no file), and the message shown.

13. Clean up when asked to (RB-03, "Cleaning up").

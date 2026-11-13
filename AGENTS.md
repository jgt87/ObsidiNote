# AGENTS.md — ObsidiNote

Agent notes for this repo. Only what can't be read from the code: commands, misleading places,
decisions, and anything that had to be corrected twice. Keep it under 200 lines; move long
procedures into a skill and area-only rules into `.claude/rules/<area>.md`.

## What this is
ObsidiNote is a personal wiki that links itself, in the spirit of Obsidian. The user adds anything
(text, links, files, mail excerpts) in a local web app. M365 Copilot (driven in Edge the way
CCBridge/StreamHub does it) classifies each item and proposes links to related pages and topics.
ObsidiNote writes the result as pages into its own OneNote notebook through the desktop OneNote
COM API, keeps its own index, and shows everything as a relevance graph. It runs on Windows
PowerShell 5.1 with no install rights. It is a sister project of CCBridge. The research and
design are in `FEASIBILITY.md`, and the go/no-go probes are in `probes/`.

## Commands
- Run: `Start ObsidiNote.cmd` (= `powershell -NoProfile -ExecutionPolicy Bypass -File obsidinote.ps1`). It ends with the interface: local server on `127.0.0.1:<uiPort>` (8767, `config\obsidinote.json`) and its window in ObsidiNote's Edge, then keeps running until the console closes or Ctrl+C. From an agent session only: `OBSIDINOTE_NO_UPDATE=1 OBSIDINOTE_NO_COPILOT=1 OBSIDINOTE_NO_WINDOW=1 powershell -NoProfile -File obsidinote.ps1` in the background (no Edge window opens), check with `curl -H "X-ObsidiNote: 1" http://127.0.0.1:8767/api/status`, then stop it by command line (`powershell.exe` whose CommandLine matches `obsidinote\.ps1`). Never while the user's own ObsidiNote runs on 8767: use `{ "uiPort": ... }` in a temp copy or the server tests instead.
- Interface source: `ui-src` (React + Vite + TS). `npm install` once, then `npm run typecheck`, `npm test` (vitest, `src/**/*.test.ts`), `npm run build` (writes `ui/`, which is committed and shipped; `ui-src` and `src` are not). After a UI change: rebuild and commit `ui/` in the same change. A running server builds its file allow-list at start: restart it after a rebuild (new hashed file names 404 until then). Dev server: `npm run dev` on port 5190, proxies `/api` to a running ObsidiNote on 8767.
- OneNote probes, from Windows PowerShell 5.1 with OneNote desktop open:
  - `powershell -NoProfile -ExecutionPolicy Bypass -File probes\p1-roundtrip.ps1 [-BasePath <OneDrive Documents URL>]`: write round trip into the ObsidiNote-Probe notebook
  - `probes\p1-find.ps1` (what OneNote search returns), `probes\p1-cleanup.ps1` (close the probe notebook); steps for a business tenant in `probes/README.md`
- Test all: `powershell -NoProfile -File tools/run-tests.ps1` · one file: `powershell -NoProfile -File tools/run-tests.ps1 -Path tests/Core.Tests.ps1`. Never bare `Invoke-Pester` from this pwsh 7 shell: it loads 7's modules; the runner resets the module path.
- Tests are Pester 3.4 syntax (`Should Be`): CI runs Pester 3.4.0 under Windows PowerShell 5.1 on `windows-latest`.
- Lint: `tools/run-tests.ps1` also fails on non-ASCII .ps1/.psm1 files
- Release: `tools/build-release.ps1 -Version vX.Y.Z -NotesFile <notes.md>`
- Update: runs by itself at the top of `obsidinote.ps1` (skip: `-NoUpdate` or `OBSIDINOTE_NO_UPDATE=1`). By hand: `update.cmd` (= `powershell -NoProfile -ExecutionPolicy Bypass -File tools\update.ps1 -Force -Report`); go back: `update.cmd -To vX.Y.Z`; reinstall the installed version: `tools\update.ps1 -Repair`. In this clone it only pulls `main` when the tree is clean.
- Updater tests: `powershell -NoProfile -File tools/run-tests.ps1 -Path tests/Update.Tests.ps1` (no network; state in `%TEMP%` via `OBSIDINOTE_DATA_DIR`).
- Startup order in `obsidinote.ps1`, one `[OK]/[WARN]/[FAIL]` line per step on stderr (`lib/Status.psm1`, shared with the installer): update (`tools\update.ps1 -PassThru` returns the outcome; after an install the script re-runs the new `obsidinote.ps1` with the same arguments and `OBSIDINOTE_UPDATED` set, then exits with its code), install check, checks of this computer (`lib/StartChecks.psm1`; a FAIL exits 1), OneNote (opens the `"notebook"` record, else the exe; `-NoOneNote` skips; exit 2), the vault (`lib/VaultSession.psm1`: open, lease, index completeness; a WARN, never an exit), Microsoft 365 Copilot (`-NoCopilot` or `OBSIDINOTE_NO_COPILOT=1` skips; exit 3), then the interface (`lib/Server.psm1` + `lib/AppWindow.psm1`; exit 4 when the server cannot start; a second start finds the running server via `/api/status` and only opens its window). All output is on stderr. Never run it with Copilot from an agent session: it opens an Edge window and waits up to 300 s for a sign-in on the user's screen.
- Server tests: `tools/run-tests.ps1 -Path tests/Server.Tests.ps1` (pure origin/host/allow-list checks, plus a live server on test port 18767 with fake OneNote/Copilot data via `New-ServerState -FakeStatus/-FakeNotebook`). Windows' HTTP service answers `../` and encoded `..%2F` URLs itself with 403 before the server sees them; the test accepts 403 or 404 there. `tests/Intent.Tests.ps1`, `tests/NotebookView.Tests.ps1` (invented hierarchy XML), `tests/AppWindow.Tests.ps1` (CDP mocked), `tests/Release.Tests.ps1` (ui shipped, ui-src not).
- Single sign-on: `sso-setup.cmd` (= `tools\sso-setup.ps1`, `-Yes` skips the question, `-Off` turns it off; opens ObsidiNote's Edge). Never run it from an agent session: it opens Edge and changes the profile's settings. Its log `<data dir>\logs\ObsidiNote-sso-<date>.txt` is written by the tool, never by `lib/Sso.psm1` (NoContentOnDisk test). Settings: `"signIn"` single-sign-on|private, `"notebook"` (the notebook record, filled at start).
- Start and Edge tests: `tools/run-tests.ps1 -Path tests/EdgeStart.Tests.ps1` (profile in use without the debug port, no second Edge window, sign-in redirect retries, forced browser sign-in), `tests/Sso.Tests.ps1`, `tests/StartChecks.Tests.ps1`. All mock processes, CDP and HTTP; none opens Edge or OneNote.
- Copilot session: own Edge, CDP port `cdpPort` (default 9334, `config\obsidinote.json`, override in `config\obsidinote.local.json`; 9333 = CCBridge's Edge, 3000/3100 reserved, Fetch bad ports refused by `lib/AppConfig.psm1`), profile `%LOCALAPPDATA%\ObsidiNote\edge-profile` (moved by `OBSIDINOTE_DATA_DIR`), send lock mutex `Local\ObsidiNoteCopilot`. Log: `<data dir>\logs\obsidinote.log`, level via `OBSIDINOTE_LOG` (off/info/verbose).
- Bridge tests: `tools/run-tests.ps1 -Path tests/CopilotBridge.Tests.ps1` (no Edge, no network; fixtures in `tests/fixtures` are scrubbed Chathub frames, keep them free of ids, names, tenants and timestamps: this repo is public).
- Validation kit (what the operator runs on the business-tenant PC; ships in the release): `powershell -NoProfile -ExecutionPolicy Bypass -File validation\Run-Validation.ps1 [-Stage V1,V2,V4] [-NoCopilot] [-NoPrompt] [-WriteTest] [-OutDir <dir>]`; from an agent session only with `-NoCopilot` and without `-WriteTest`. Masked log + JSON on the Desktop; masking in `validation/lib/ValidationCore.psm1`, tests `tests/Validation.Tests.ps1`. V6 binds Add/Ask through `$script:StoreBuilders` / `$script:SourceBuilders` in `validation/lib/StageVault.psm1`: keep them in step with `lib/VaultStore.psm1` and `lib/AskSources.psm1`. Every feature that needs a check there gets a stage here and a step in `docs/runbooks/` (RB-00..06).

"Done" means the check commands above pass. Report the command and its output, not just "tests pass".

## Architecture
Built (interface step 1):
- `obsidinote.ps1`: entry point; start sequence, then `Start-UiServer` and the window; waits on the server's runspace, `finally` stops the server and disconnects the Copilot bridge (kept connected while it runs).
- `lib/Server.psm1`: HttpListener on 127.0.0.1/localhost:<uiPort>, request loop in its own STA runspace (OneNote COM). State crossing into the runspace is a synchronized hashtable of plain values (`New-ServerState`), never scriptblocks (session-state affinity). Checks in order: loopback client, exact Host, exact Origin when sent, POST only on `/api/`, `X-ObsidiNote: 1` on every `/api/` call. Static files only from the allow-list built from `ui\` at start (known web types, no dot-folders). API: `GET /api/status`, `GET /api/notebooks` (open notebooks: id, name, vault, active, location; vaults first), `GET /api/notebook[?id=]` (one notebook's sections and recent pages; the active vault without id; 400 for a non-id, 404 for an id that is not an open notebook), `POST /api/active-vault {id}` (opens that vault with its lease and keeps its record as `"vaultId"` + `"notebook"` in `config\obsidinote.local.json`, the only file the server changes; refuses non-vaults with 409), `POST /api/intent`, plus the step 2-5 routes below. All notebook reads go through `Read-NotebookData` (list/view) on `Get-VaultList`/`Get-NotebookList`. Tests feed it `New-ServerState -FakeHierarchyXml` (tests/fixtures/hierarchy.xml, invented, with state pages; read only) or, in process, `-TestAdapter` (FakeOneNote) and `-TestCopilot`. Page CSP: `default-src 'self'`, no inline script or style.
- `lib/Intent.psm1`: the Add-vs-Ask rules (FEASIBILITY.md), pure; the one implementation (the UI asks the server, it does not copy the rules).
- `lib/NotebookView.psm1` (thin, step 1; replaced by the full detection): open notebooks (GetHierarchy hsSections) with a step-1 vault check (a `00 Index` section directly in the notebook, not the name), the active vault (the one on the `"notebook"` record, else the first), one notebook's sections/groups with page counts and the 10 latest pages (GetHierarchy on that notebook, hsPages, + GetHyperlinkToObject), recycle bin left out, only `onenote:` links passed on. An id is only read when it is an open notebook's id. `Find-VaultInHierarchy` is the start's finder (record only when there is one, so a start never switches vault by itself). Never starts OneNote (no COM call when it is not running: COM activation would start it). No OneNote write method anywhere in the interface modules (NoContentOnDisk test).
- `lib/AppWindow.psm1`: with Copilot, `Target.createTarget {newWindow: true}` on ObsidiNote's Edge (an open interface tab is activated instead); with `-NoCopilot`, Edge with the profile and `--app=<url>` (plus the debug port, so a later Copilot start can reuse that Edge), else the default browser.
- `ui-src/`: React + Vite + TS; `src/api.ts` (fetch + types; normalises PS 5.1 one-item/empty arrays; `SubmitResult` = Add | Ask union by `intent`), `src/model/*` pure wording/keys/format/attention/notebooks/handoff (vitest), `src/components/*` with one CSS file each, tokens from `../src/styles/tokens.css`. `src/graph` (knowledge graph, `fetchGraph`), `src/add` (Add result, Undo/Update/Decide), `src/ask` (progress, answer) are the step 3-5 views; `components/HomeView` + `hooks/useHomeFlow` wire the box to them (Save answer = Ask's page spec as Add text, `model/handoff.ts`). Browser storage only in `src/model/preferences.ts`, one key (`VAULT_KEY`: the active vault's switcher id, validated on read); the NoContentOnDisk test fails on storage anywhere else. Classification: active vault id = user preference (localStorage + the `"vaultId"`/`"notebook"` record); shown notebook, mode, text, Ask sources/archived, results = session state in memory. Favicons are emitted from `assets/` by a Vite plugin; the rail icon is `assets/icon.svg` inlined.

Built (steps 2-5, wired 2026-11-13):
- `lib/OneNote.psm1`: the COM adapter (`New-OneNoteComAdapter`) behind the **write guard** (`New-GuardedOneNote`, `Get-OneNoteAdapter`): every write (UpdatePageContent, CreateNewPage, DeleteHierarchy, DeletePageContent, creating OpenHierarchy) must target an id inside the active vault's root (`Set-OneNoteWriteRoot`), else "Write refused". `New-XmlOneNoteAdapter`: read-only stand-in from one hierarchy XML (server fake mode). `tests/FakeOneNote.ps1`: the in-memory stand-in for everything else.
- `lib/NotebookStructure.psm1` (fixed sections, type -> bucket, 500-page rollover, link bucket, URL normalisation), `lib/PageMeta.psm1` (`obsn.*` Meta, ids `p`+base36, owned outlines by `obsn.role`: props, backlinks, summary, index, state, body, checked, notes), `lib/Vault.psm1` (vaults by state page: `00 Index` > `ObsidiNote` with `obsn.indexKey=state` + `obsn.vaultId`; root = notebook or top-level section group; new/open/initialize), `lib/WriterLease.psm1` (lease Meta on the state page).
- `lib/Index.psm1`: the central index in memory (fast load from Index Meta, rebuild scan of the content pages' own Meta, page wins), completeness, generated Index pages, path-based retrieval, the derived model of a connected notebook (`Get-NotebookModel`, edges via `Get-NotebookLinks` in batches).
- `lib/VaultSession.psm1`: the active vault of a session: `Select-StartVault` (vaultId record, else notebook record, else the only vault), `Open-VaultSession` (root, lease, structure as writer, `Update-VaultIndex`), `Update-SessionLease`, `Close-VaultSession`, the start's `Vault` status line. Records crossing into the server runspace are plain hashtables.
- `lib/VaultStore.psm1`: the Ingest store adapter (every name of `Get-IngestStoreContract`) on top of the above; regenerates only the affected Index pages after an index change, then checks completeness. `lib/AskSources.psm1`: Ask source adapters over an index model (short `x<n>` ids for non-obsn pages). `lib/GraphModel.psm1`: index model -> the UI's GraphModel (pure).
- `lib/Ingest.psm1` + `lib/Linker.psm1` + `lib/LinkCapture.psm1` (Add, Undo, link Update; store + Copilot injected), `lib/Ask.psm1` (Invoke-AskRequest; sources + Copilot injected; never writes).
- The start: after OneNote, `obsidinote.ps1` opens the vault with its own guarded adapter, passes the vault/lease records and the index working copy to `New-ServerState`, renews the lease every 60 s (TTL 120 s) under `$state.Lock`, and clears it in `finally`. The server runspace makes its own adapter; vault switch / new vault go through `Switch-ServerVault` (old lease back, new lease, record, `Reset-AskState`).
- Server API added: `GET /api/graph?vault=|notebook=` (active vault without either; connected notebook read only, edges in batches within 15 s, `edgesComplete`), `POST /api/vault/new {name, inNotebook, confirm}` (409 `needsConfirm` without confirm), `POST /api/vault/setup {id, confirm}` (an open, empty notebook set up as a vault in place, `Initialize-EmptyNotebookVault`; 409 `needsConfirm` without confirm, 409 when it holds pages or a vault; the view's `notebook.canSetUp` offers it), `POST /api/submit` (Add or Ask by mode/intent; unclear = Add in auto mode; 503 without Copilot, 409 without a vault), `POST /api/add/undo {undo}`, `POST /api/link/update {id, decision, proposed}`. `/api/notebooks` lists vaults (id = notebook id, or the section group id) with `vaultId`, plus `activeVaultId` and `mode`.
- Exists from before: `lib/CopilotBridge.psm1` + `lib/Cdp.psm1` (vendored from CCBridge at b972eab, see their headers; CCBridge itself is never loaded or changed), `lib/AppConfig.psm1` (settings), `lib/Log.psm1` (bridge log), `lib/OneNoteHost.psm1` (OneNote at startup). `probes/`: one-off feasibility scripts; not part of the app.

Where decisions live (read before changing behaviour or look):
- `FEASIBILITY.md`: product and architecture decisions (central index and path-based Ask, Add-vs-Ask rules, map behaviour, probe results)
- `DESIGN.md` + `src/styles/tokens.css`: visual rules (One Purple accent, Every Dot Is Content, Weight Is Relevance); `PRODUCT.md`: users and principles
- `docs/STATUS.md`: probe and build status
- Interface mock-up: a hosted design canvas; its link is kept outside the repo (ask the operator).

## Invariants (do not relax)
- Write only inside ObsidiNote's own notebook; other notes, mail and files are copied in, never edited. The user's data is read-only.
- On a page, rewrite only the outlines tagged `<one:Meta name="obsn.role">`; never touch other content (P1, 2026-11-12).
- Copilot is a stateless reasoning step: every id it returns is checked against the index before anything is written.
- **OneNote is the only store** (user, 2026-11-12). Content, the index, the inbox and state live in the ObsidiNote notebook; the app only references it. Never write content to disk: no index or cache files, no temp files with page text, logs hold ids/counts/timings only. Local files hold no content: `config\obsidinote.local.json` (settings), and the updater's backups of the app's own files and `update.log` in `%LOCALAPPDATA%\ObsidiNote`. Single writer = a lease Meta tag on the `ObsidiNote` page, not a lock file (FEASIBILITY.md, storage principle).
- **Notebook structure is fixed** (user, 2026-11-12; FEASIBILITY.md, Notebook structure): sections `00 Index`, `01 Inbox`, then one bucket per page type (`Notes`, `Internal links`, `Web links`, `Sources`, `People`, `Projects`, `Meetings`, `Decisions`, `Journal`/<year>, `Files`, `Archive`). A page's section = its `type` from a fixed list (the validator rejects others); topics live only in the index, never as sections. Max 500 pages per section (rollover `<Bucket> 2`); subpages only for parts of one thing; sections and pages the user made are listed, never edited.
- **Archive and delete** (user, 2026-11-12; FEASIBILITY.md, Archive and delete): archive is the default and reversible (move to `Archive / <bucket>`, keep id/links, Restore). Archive AND delete always ask for confirmation first (one page, selection, topic, Tidy up, typed command; no "don't ask again"). Delete covers only ObsidiNote's own pages and goes only through OneNote's Deleted Pages (60 days); it removes index entries and edges and turns links to the page into "(deleted: title)". Never a permanent delete, never automatic (Tidy up only suggests). "archive …"/"delete …" typed in the box opens the same confirmation, never Add/Ask.
- **Links** (user, 2026-11-12; FEASIBILITY.md, Links): a pasted URL becomes one summary page. Internal (Microsoft 365 / `internalHosts`) vs Web by host rule, no model. Copilot reads the source (Work IQ for internal, web grounding for external); store a summary + key facts + link, never the full text; one page per normalized URL (update, never duplicate); the Links index page groups by site/team and domain. **Update** (per link, per site/domain, stale > 90 days) re-reads the source, shows old vs new, keeps the last 3 summaries collapsed on the page, re-runs linking (new links added, outdated ones shown for review, never removed silently), and never touches the page's "Your notes" outline; a hand-edited summary outline is replaced only after asking.
- **Everything is listed in the central index** (user, 2026-11-12): every page id appears in its topic hubs or Unfiled, in By type and in A-Z; on every start and after every write the app compares the hierarchy with the index and adds any missing page to Unfiled. Covered by a test once the index code exists.
- The central index is the way into the data: retrieval walks topic paths (root topics, then branch, then pages, then text), and every page has a topic path. The Index section pages are generated by the harness, never edited by hand, and are a mirror of the content pages' own `obsn.*` Meta: when they disagree the page wins, and a rebuild scan regenerates them.
- The Copilot bridge (`lib/CopilotBridge.psm1`, `lib/Cdp.psm1`) writes no files: no reply frames, prompts, reply text, screenshots or lock files; its log holds ids, counts, timings and states only (no prompt or reply text, page titles, banners, file names or URLs with query strings). Enforced by `tests/NoContentOnDisk.Tests.ps1`; do not widen its allow-list, fix the code. When porting a CCBridge fix, drop its debug dumps.
- Never rely on Copilot's own search over OneNote, or on OneNote `FindPages`, for retrieval; use the ObsidiNote index.
- **Write guard**: every OneNote write goes through the guarded adapter (`$Adapter.` / `$Ctx.Adapter.`), whose root is the active vault; no module but `lib/OneNote.psm1` makes a COM object that writes (`lib/NotebookView.psm1`/`OneNoteHost.psm1` only read). Store writes also need a valid writer lease (`AssertWritable`). Enforced by `tests/NoContentOnDisk.Tests.ps1` and `tests/VaultStore.Tests.ps1`.
- **Vault invariants**: a vault is found by its state page (`obsn.vaultId`), never by name or by `00 Index` alone; exactly one vault is active, switched only by the person; another vault or a connected notebook is read only, always; making a vault inside a notebook ObsidiNote does not own needs the UI's explicit confirm flag; the "Your notes" outline (`notes`) is written once and `Write-ObsnPage` refuses it on an existing page.

## Conventions & gotchas
Each line: rule — reason (incident, YYYY-MM-DD). Append, don't rewrite.
- OneNote COM only from Windows PowerShell 5.1: in pwsh 7, `GetHierarchy` throws "Unexpected HRESULT" (2026-11-12).
- `FindPages` returns *every* page, including recycle-bin pages, while `isIndexed=false` (2026-11-12).
- A function that returns an `XmlNamespaceManager` must `return ,$m`, or PS unrolls it (2026-11-12).
- `UpdatePageContent` error 0x80042000 means malformed XML. Watch `"a" + (...) -join '' + "b"`: `-join` binds looser than `+` (2026-11-12).
- Closures made with `GetNewClosure()` inside a module cannot see that module's imported commands; capture `Get-Command X` first (CCBridge bug, 2026-11-12).
- Copilot's reply passes a citation filter that removes `[x]:` text; ask for JSON, not Markdown links.
- `GetHierarchy` at page scope returns every page's Meta in full (index entries included): it is how the index loads in one call, and why `/api/notebooks` is cached for 3 s (2026-11-13).
- OneNote refuses a Meta value over about 100k characters: split long values at 30k (`Split-ObsnMetaValue`, `obsn.X.n`); `linkSummary` and `history` always carry their `.n` so a shrunk value never leaves stale parts (2026-11-13).
- Making a notebook next to a cloud notebook can fail with 0x80042006: `POST /api/vault/new` falls back to OneNote's default notebook folder (`GetSpecialLocation`) with a `[WARN]` and a warning in the answer (2026-11-13).
- `$pid` (and `$Error`, `$Host`, `$input`) are automatic variables: never use them for a page id or a parameter; the code uses `$pageId`/`$pid2` (2026-11-13).
- `,@()` nesting: a function that returns `, @($x)` hands over one array; wrapping that call again in `, @(...)` makes an array in an array. Wrap call sites in `@()` only (2026-11-13).
- Closures from `GetNewClosure()` in a module (store and Ask source scriptblocks) call one captured command (`Get-Command Invoke-VaultStoreCall`) that dispatches to the module's functions (2026-11-13).
- `Repair-IndexCompleteness` after a rebuild merge finds nothing (the scan has every page): "missing from the index" at start = the merge's `added` plus its `missing` (2026-11-13).

## House rules
- Every user-relevant change gets a line in `CHANGELOG.md` under `Unreleased`, in the same change.
- Never edit or delete user-provided source data; write derived files next to it.
- No assistant or AI-vendor names in code, UI, docs, metadata or commits; no AI attribution trailers.
- Never name the sister projects (StreamHub, CCBridge) in README.md, CHANGELOG.md or release notes (user, 2026-11-12); describe features on their own terms. Provenance comments in code and the design notes in FEASIBILITY.md may name them.
- Local servers: pass the port explicitly; never use 3000 or 3100 (reserved on this machine).
- Keep `docs/STATUS.md` current in the same turn the state changes.
- Before a public push: repo-local noreply git email, grep for `C:\Users\` paths and logs.

## Releasing
1. Move CHANGELOG `Unreleased` to `## [vX.Y.Z] - YYYY-MM-DD` and write the notes file.
2. Commit and push (clean tree).
3. `tools/build-release.ps1 -Version vX.Y.Z -NotesFile notes.md` bumps `version.txt`, runs the tests, tags, builds `release\ObsidiNote-vX.Y.Z.zip` (one `ObsidiNote\` folder with `version.txt` = the tag and `manifest.json`; no tests/probes/dot-folders), writes SHA256SUMS and publishes both with `gh release create`. `tools/update.ps1` depends on that asset name, the single top folder, `manifest.json` and `SHA256SUMS`: change them together. A release must keep `config\` and `tools\update.ps1`.

## Keeping docs in step
- README lists features and commands that exist in code; update both together.
- Version lives in: `version.txt`. Bump all of them together.

<!-- commonshared:begin (managed by __CommonShared/sync; edit it there, not here) -->
## Shared practices
This project follows the generic best practices in `C:/Files/Apps/__CommonShared`. This file
and the project's own DESIGN.md / PRODUCT.md win where they are more specific.
- Conventions: its `docs/` (visual design 01, interaction 02, testing 04, structure and
  release 05, code organisation 08, change management 09, gitignore 11, line endings 12,
  agent workflow 14, lessons learned 15, UI fixes 17).
- Rules: `.claude/rules/commonshared-*.md` are managed copies of its `rules/` (loaded by
  file type; refreshed at session start and by its sync). Do not edit them: put this
  project's own rules in `.claude/rules/project-<area>.md`, which win on conflict.
- Starters: its `templates/` (tokens, gitignore, gitattributes, editorconfig, check scripts,
  design-rule tests). Copy in; do not link.
- Audit: `python -I C:/Files/Apps/__CommonShared/.claude/skills/new-project/scripts/check_project.py .`
- A lesson learned here that would hold in any project goes in `tasks/lessons.md` (rule,
  Why with date, check). It is pulled upstream into the shared lessons, which load at every
  session start through the shared-lessons hook.
<!-- commonshared:end -->

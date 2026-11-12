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
- Run: no app yet (`obsidinote.ps1` is still the scaffold's greeting demo). What runs today are the OneNote probes, from Windows PowerShell 5.1 with OneNote desktop open:
  - `powershell -NoProfile -ExecutionPolicy Bypass -File probes\p1-roundtrip.ps1 [-BasePath <OneDrive Documents URL>]`: write round trip into the ObsidiNote-Probe notebook
  - `probes\p1-find.ps1` (what OneNote search returns), `probes\p1-cleanup.ps1` (close the probe notebook); steps for a business tenant in `probes/README.md`
- Test all: `powershell -NoProfile -File tools/run-tests.ps1` · one file: `powershell -NoProfile -File tools/run-tests.ps1 -Path tests/Core.Tests.ps1`. Never bare `Invoke-Pester` from this pwsh 7 shell: it loads 7's modules; the runner resets the module path.
- Tests are Pester 3.4 syntax (`Should Be`): CI runs Pester 3.4.0 under Windows PowerShell 5.1 on `windows-latest`.
- Lint: `tools/run-tests.ps1` also fails on non-ASCII .ps1/.psm1 files
- Release: `tools/build-release.ps1 -Version vX.Y.Z -NotesFile <notes.md>`
- Update: runs by itself at the top of `obsidinote.ps1` (skip: `-NoUpdate` or `OBSIDINOTE_NO_UPDATE=1`). By hand: `update.cmd` (= `powershell -NoProfile -ExecutionPolicy Bypass -File tools\update.ps1 -Force -Report`); go back: `update.cmd -To vX.Y.Z`; reinstall the installed version: `tools\update.ps1 -Repair`. In this clone it only pulls `main` when the tree is clean.
- Updater tests: `powershell -NoProfile -File tools/run-tests.ps1 -Path tests/Update.Tests.ps1` (no network; state in `%TEMP%` via `OBSIDINOTE_DATA_DIR`).
- Startup order in `obsidinote.ps1`: update, install check, OneNote (`-NoOneNote` skips; exit 2 on failure), Microsoft 365 Copilot (`-NoCopilot` or `OBSIDINOTE_NO_COPILOT=1` skips; exit 3 on failure). A start without either: `OBSIDINOTE_NO_UPDATE=1 OBSIDINOTE_NO_COPILOT=1 powershell -NoProfile -File obsidinote.ps1 -Name T` (prints the OneNote line on stderr and the JSON on stdout). Never run it with Copilot from an agent session: it opens an Edge window and waits up to 300 s for a sign-in on the user's screen.
- Copilot session: own Edge, CDP port `cdpPort` (default 9334, `config\obsidinote.json`, override in `config\obsidinote.local.json`; 9333 = CCBridge's Edge, 3000/3100 reserved, Fetch bad ports refused by `lib/AppConfig.psm1`), profile `%LOCALAPPDATA%\ObsidiNote\edge-profile` (moved by `OBSIDINOTE_DATA_DIR`), send lock mutex `Local\ObsidiNoteCopilot`. Log: `<data dir>\logs\obsidinote.log`, level via `OBSIDINOTE_LOG` (off/info/verbose).
- Bridge tests: `tools/run-tests.ps1 -Path tests/CopilotBridge.Tests.ps1` (no Edge, no network; fixtures in `tests/fixtures` are scrubbed Chathub frames, keep them free of ids, names, tenants and timestamps: this repo is public).

"Done" means the check commands above pass. Report the command and its output, not just "tests pass".

## Architecture
Planned (FEASIBILITY.md section 5); only the scaffold exists yet:
- `obsidinote.ps1`: entry point; local server on 127.0.0.1 serving the prebuilt UI (Add / Ask / Map)
- `lib/OneNote.psm1`: COM reader/writer (hierarchy, page XML, links, outlines that ObsidiNote owns)
- `lib/Index.psm1`: the **central index**: topic tree with paths, pages, edges with strength, stored as the OneNote `Index` section (readable pages + `obsn.*` Meta); loaded into memory at start; full-text lookup reads pages on demand
- `lib/Linker.psm1`: shortlist + Copilot prompt + JSON validation (uses `lib/CopilotBridge.psm1`)
- Exists: `lib/CopilotBridge.psm1` + `lib/Cdp.psm1` (vendored from CCBridge at b972eab, see their headers; CCBridge itself is never loaded or changed), `lib/AppConfig.psm1` (settings), `lib/Log.psm1` (bridge log), `lib/OneNoteHost.psm1` (OneNote at startup)
- `probes/`: one-off feasibility scripts; not part of the app

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

## Conventions & gotchas
Each line: rule — reason (incident, YYYY-MM-DD). Append, don't rewrite.
- OneNote COM only from Windows PowerShell 5.1: in pwsh 7, `GetHierarchy` throws "Unexpected HRESULT" (2026-11-12).
- `FindPages` returns *every* page, including recycle-bin pages, while `isIndexed=false` (2026-11-12).
- A function that returns an `XmlNamespaceManager` must `return ,$m`, or PS unrolls it (2026-11-12).
- `UpdatePageContent` error 0x80042000 means malformed XML. Watch `"a" + (...) -join '' + "b"`: `-join` binds looser than `+` (2026-11-12).
- Closures made with `GetNewClosure()` inside a module cannot see that module's imported commands; capture `Get-Command X` first (CCBridge bug, 2026-11-12).
- Copilot's reply passes a citation filter that removes `[x]:` text; ask for JSON, not Markdown links.

## House rules
- Every user-relevant change gets a line in `CHANGELOG.md` under `Unreleased`, in the same change.
- Never edit or delete user-provided source data; write derived files next to it.
- No assistant or AI-vendor names in code, UI, docs, metadata or commits; no AI attribution trailers.
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

# Changelog

All notable changes to ObsidiNote. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
versions follow [SemVer](https://semver.org/).

## [Unreleased]

Nothing yet.

## [v0.2.3] - 2026-11-12

### Fixed
- The install bootstrap no longer ends with a newline. On machines that run it line by line, that left one "empty string" error after a finished install. `.editorconfig` and a test keep it so.

### Added
- Design: archive and delete. Both always ask for confirmation first. Archive is the default: it moves a page to `Archive / <bucket>`, keeps its id, links and index entries, and can be restored. Delete is explicit: a confirmation dialog, then OneNote's own Deleted Pages, kept 60 days. It removes the page's index entries and turns links to it into "(deleted: title)". Only ObsidiNote's own pages can be removed, never automatically: a "Tidy up" view only suggests. Probe P1c checks links after a move or delete.
- Design: pasted links. A SharePoint, OneDrive, Teams or Loop link goes to `Internal links`, any other URL to `Web links`, decided by host rules. Copilot summarizes each link into a fixed page shape (summary, key facts, where, kind, sensitivity label, date checked), never the full text. A link pasted again updates its page instead of duplicating it, and the central index gets a Links page grouped by site and domain. Probes P7 and P8 cover the internal and external case.
- Design: updating link summaries. An Update button per link, plus "Update all" for a site or domain and "Update stale links" (older than 90 days). Copilot re-reads the source and the result shows old against new. The last 3 summaries stay collapsed on the page, linking runs again (outdated links are shown for review, never removed silently), and the page's "Your notes" outline is never touched.

## [v0.2.2] - 2026-11-12

### Fixed
- The install command (`irm .../install.ps1 | iex`, the same as CCBridge's) failed on machines whose shell hands the script to `iex` line by line: blank lines gave "empty string" errors and multi-line blocks would not parse. `install.ps1` is now a one-line bootstrap that downloads the full installer (`tools/install-main.ps1`) and runs it as a file, so it works either way. A test keeps the bootstrap line-by-line safe.

### Added
- Design: a fixed notebook structure. `00 Index` and `01 Inbox`, then one section per page type (`Notes`, `Sources`, `People`, `Projects`, `Meetings`, `Decisions`, `Journal` by year, `Files`) and an `Archive`, with title rules and a 500-page rollover. Topics live only in the central index.
- Design: the completeness rule. Every page appears in the central index (topic hubs or Unfiled, By type, A-Z), and the app checks this on every start and after every write.

## [v0.2.1] - 2026-11-12

### Changed
- The installer follows the same sequence as CCBridge/StreamHub: a "Before installing" check (Windows PowerShell 5.1, Full Language mode), the install, then a "This computer" check of what ObsidiNote needs (desktop OneNote, Microsoft Edge), then the summary. The README's install steps match CCBridge's Quick start.

### Added
- A test that fails on download-and-run forms antivirus treats as malware (a WebClient download fed straight into a script, encoded commands) in scripts and docs.

## [v0.2.0] - 2026-11-12

### Added
- One-line installer `install.ps1` (latest release into `%LOCALAPPDATA%\Programs\ObsidiNote`, checked against `SHA256SUMS`, with desktop and Start menu shortcuts); the README shows its command instead of the old quick start.
- Startup starts desktop OneNote when it is not running (or runs only in the background), minimised, and waits up to 60 s until its COM API answers; without OneNote the start stops with exit code 2. Skip it with `-NoOneNote` (`lib/OneNoteHost.psm1`).
- Startup connects to Microsoft 365 Copilot after the OneNote step: ObsidiNote opens its own Edge window (profile `%LOCALAPPDATA%\ObsidiNote\edge-profile`, debug port 9334, setting `cdpPort` in `config\obsidinote.json` / `config\obsidinote.local.json`), waits up to 300 s for you to sign in, and stops with exit code 3 when Copilot cannot be reached. Skip it with `-NoCopilot` or `OBSIDINOTE_NO_COPILOT=1`.
- The Copilot bridge (`lib/CopilotBridge.psm1`, `lib/Cdp.psm1`, `config/selectors.json`), copied from CCBridge and adapted: it sends prompts and rebuilds replies, and writes nothing to disk (no reply-frame dumps, screenshots or lock files); its log `%LOCALAPPDATA%\ObsidiNote\logs\obsidinote.log` holds ids, counts, timings and states only.

## [v0.1.2] - 2026-11-12

### Fixed
- Updates computed the wrong file list when the app or temp folder was reached through an 8.3 short name (for example the CI runner's profile folder, `RUNNER~1`): relative paths were cut in the wrong place, so changed, locked and removed files were missed and a rollback could put back the wrong files. Files are now enumerated with the folder exactly as given. This is also why every CI run failed until now.

## [v0.1.1] - 2026-11-12

### Changed
- App icon redrawn as a rock: an irregular outline with uneven facets lit from the top left, instead of seven facets around one centre (which read as an umbrella). All sizes regenerated (`tools/make-icon.py`).

### Added
- README screenshots of the interface mock-ups (home, Add result, Ask answer, knowledge graph, page details) in `docs/screenshots/`.

## [v0.1.0] - 2026-11-12

First public version: feasibility stage. No app yet; the OneNote probes, the design and the
update mechanism are in place.

### Added
- Project scaffold (ps51: Windows PowerShell 5.1 tool (zero-install, ASCII-only, Pester 3.4)) with tests, CI and release script.
- `FEASIBILITY.md`: research on an Obsidian-style self-linking wiki on OneNote or Loop with M365 Copilot, design of the central index (topic paths, path-based retrieval) and the Add / Ask / Map web interface, go/no-go probes.
- Purple accent as the one hue: `--purple-*` raw palette and `--accent` / `--accent-hover` / `--accent-soft` / `--on-accent` / `--ring` roles in `src/styles/tokens.css`, light and dark values (7.1:1 and 6.4:1), and the "One Purple" rule in DESIGN.md. Status soft fills stay neutral.
- App icon: a faceted purple stone with a white N, as `assets/icon.svg`, `obsidinote.ico` (16 to 256 px), `favicon.svg` and `favicon.ico`, generated by `tools/make-icon.py`.
- Storage principle: OneNote is the only store. Content, inbox, central index and state live in the ObsidiNote notebook; on disk the app keeps only files without content (settings, the updater's backups and log) (FEASIBILITY.md section 5).
- Map design rule "Every Dot Is Content": only real notes, files and links are dots, and every topic area has a visible label.
- Automatic updates at every start (`tools/update.ps1`, `update.cmd`): a git clone pulls `main` (fast-forward only); a release install compares `version.txt` with the latest GitHub Release, checks the zip against `SHA256SUMS`, and mirrors it in with a backup that is put back if the copy fails. Files in use hold the update instead of half-copying it; `config\*.local.json` is kept. `update.cmd -To vX.Y.Z` goes back to an earlier release and skips the newer ones; `"autoUpdate": false` in `config\obsidinote.local.json`, `-NoUpdate` or `OBSIDINOTE_NO_UPDATE=1` turn it off. Each start checks the app folder against the release's `manifest.json` and repairs an incomplete install once.
- Releases now ship as `ObsidiNote-vX.Y.Z.zip` (one `ObsidiNote\` folder with `version.txt` and `manifest.json`) plus `SHA256SUMS`.
- `probes/`: OneNote COM probes (P1 round trip, search check, cleanup) and the Copilot grounding prompt (P3).

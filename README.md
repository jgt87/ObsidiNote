# ObsidiNote

<img src="assets/icon-256.png" alt="ObsidiNote icon: a faceted purple stone with a white N" width="96" height="96">

A personal wiki that links itself: add anything, and Microsoft 365 Copilot files it into OneNote, linked to related pages and topics.

Status: feasibility stage. See `FEASIBILITY.md` and `docs/STATUS.md`.

## Install
1. Install (PowerShell, no admin rights):
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/jgt87/ObsidiNote/main/install.ps1 | iex"
   ```
2. Start **ObsidiNote** from the desktop or Start menu. It starts OneNote when OneNote is not running, and opens Copilot Chat in a separate Edge profile: sign in once with your Microsoft 365 account.
3. To update later: just restart ObsidiNote (it updates itself at every start), or double-click `update.cmd`.

Without the installer: download `ObsidiNote-vX.Y.Z.zip` from [Releases](https://github.com/jgt87/ObsidiNote/releases), check it against `SHA256SUMS`, unpack it and start `Start ObsidiNote.cmd`.

The installer puts the latest release into `%LOCALAPPDATA%\Programs\ObsidiNote` and adds an ObsidiNote shortcut to the desktop and Start menu. Run it again any time to update.

## Requirements
- Windows with Windows PowerShell 5.1 (inbox); no install rights needed.
- Desktop OneNote (Microsoft 365). ObsidiNote starts it when it is not running.
- Microsoft Edge and a Microsoft 365 account with Copilot Chat.

## Startup
Each start shows one status line per step (`[OK]`, `[WARN]` or `[FAIL]`):
1. **Update**: checks for a new release. If one is installed, the new version starts at once.
2. **This computer**: Windows PowerShell 5.1, desktop OneNote, Microsoft Edge and its policies, the debug port, ObsidiNote's Edge profile (signed in or not, single sign-on on or off) and GitHub. A `[FAIL]` line says what to fix.
3. **OneNote**: opens the ObsidiNote notebook, which also starts OneNote, and waits until OneNote answers. The first time the notebook is found, its location is saved as `"notebook"` in `config\obsidinote.local.json`.
4. **Copilot**: opens Microsoft 365 Copilot in an Edge window of its own. It has its own profile in `%LOCALAPPDATA%\ObsidiNote\edge-profile`, so your normal Edge is not touched. ObsidiNote waits up to 5 minutes for a sign-in. Later starts reuse it.

- Skip Copilot: start with `-NoCopilot` or set `OBSIDINOTE_NO_COPILOT=1`. Skip OneNote: `-NoOneNote`.
- Exit codes: 1 = a check failed, 2 = OneNote not available, 3 = Copilot could not be reached.
- The Edge window listens on port 9334 on this computer only. Another port: `{ "cdpPort": 9345 }` in `config\obsidinote.local.json` (9333, 3000, 3100 and ports browsers block are refused).
- Sign-in: `{ "signIn": "private" }` in `config\obsidinote.local.json` opens Copilot in a private session instead. You then sign in yourself at every Edge start. The default is `single-sign-on`.

### Single sign-on (work or school account)
On a PC with a Windows work account, run **`sso-setup.cmd`** once (in the ObsidiNote folder). It opens ObsidiNote's Edge window and asks before it changes anything. It turns on Edge's "Allow single sign-on for work or school sites using this profile" for ObsidiNote's own profile only, so Copilot then signs in with your Windows account by itself. No password is stored, and your normal Edge and Edge policies stay as they are. It writes a log with names and yes/no values only to `%LOCALAPPDATA%\ObsidiNote\logs\ObsidiNote-sso-<date>.txt`. `sso-setup.cmd -Off` turns it off again. The start shows whether single sign-on is on (`Edge profile` line), and reminds you to run the setup when it is off.

### When Copilot does not sign in
- **`[WARN] Edge profile ... SSO off`**: run `sso-setup.cmd` once, close ObsidiNote's Edge window, then start ObsidiNote again.
- **"Edge profile is already open in an Edge window ... without its debug port"**: an Edge window with ObsidiNote's profile is open, but ObsidiNote cannot control it. Close every window of ObsidiNote's Edge (also check the taskbar), then start again.
- **"Edge policy BrowserSignin = 2"**: your organisation requires you to sign in to Edge itself first. In the Edge window ObsidiNote opened, sign in to Edge with your work account (Edge's own prompt, or the profile picture at the top left), then start again.
- **"Edge policy RemoteDebuggingAllowed = 0"**: ObsidiNote cannot drive Copilot on that computer. Ask IT to allow it.
- **"Copilot message box never appeared"**: sign in to Copilot in ObsidiNote's Edge window within 5 minutes and choose "Stay signed in", then start again.
- Still stuck: send the last 30 lines of `%LOCALAPPDATA%\ObsidiNote\logs\obsidinote.log`. They hold ids, counts, timings and states only, never your content.

## Features
Planned:
- **Add**: paste text, a link or a file; it becomes a OneNote page with topics, links and backlinks.
- **Ask**: ask a question; the answer cites your own pages, and each citation opens in OneNote.
- **Map**: a graph of everything, clustered by topic, with edges weighted by relevance.

## Screenshots
Design mock-ups of the planned interface, with invented example content.

**Add or ask from one box.** ObsidiNote says what it will do before it does it.
![Home: one input with Auto, Add and Ask modes, the central index in the side bar, recently added pages](docs/screenshots/home.png)

**Add.** The new page's place in the central index, its topics, and every link with its strength and reason.
![Add result: placement in the index, topics, links with strength, anchor and reason](docs/screenshots/add.png)

**Ask.** The answer shows the path it took through the index and cites your own pages.
![Ask answer: path through the index, answer with numbered citations, sources that open in OneNote](docs/screenshots/ask.png)

**Knowledge graph.** Pages are dots, topics are grey areas, and links are lines weighted by relevance. Hovering a page focuses it and its neighbours.
![Knowledge graph: dots in labelled topic areas, the hovered page and its links in purple, a preview card](docs/screenshots/map.png)

**Page details.** Clicking a dot opens the page with its links, backlinks and mentions.
![Page modal: summary, page content from OneNote, links out, linked from, mentions, Open in OneNote](docs/screenshots/page.png)

## Configuration
Copy `.env.example` to `.env` (if present). Every key has a working default; optional keys
switch features off instead of crashing.

## Updates
ObsidiNote checks for an update every time it starts, before anything else loads:
- In a git clone on `main` without local changes it runs `git pull --ff-only`.
- In a folder unpacked from a release it compares `version.txt` with the latest release on GitHub, downloads `ObsidiNote-vX.Y.Z.zip`, checks it against `SHA256SUMS`, and copies it in. Your `config\*.local.json` files stay. If another program has a file open, the update waits and names the file; if the copy fails halfway, the previous version is put back.
- Each start also checks the folder against the release's `manifest.json` and reinstalls the same version once if files are missing or changed.

Problems never stop ObsidiNote; they are reported on stderr and in `%LOCALAPPDATA%\ObsidiNote\logs\update.log`.

- Update now: `update.cmd`
- Go back to an earlier release: `update.cmd -To v0.1.3` (automatic updates then skip the release you left and take the next newer one; remove `skipUpdates` from `config\obsidinote.local.json` to undo)
- Turn automatic updates off: `{ "autoUpdate": false }` in `config\obsidinote.local.json`, or start with `-NoUpdate`, or set `OBSIDINOTE_NO_UPDATE=1`

## Privacy
Everything ObsidiNote knows lives in your own OneNote notebook: your pages, the inbox, the central index and its links. ObsidiNote keeps no copy on disk; it reads the notebook while it runs, so the notebook's own protection (OneDrive or SharePoint, your organisation's labels and retention) covers all of it. Text you add is sent to Microsoft 365 Copilot in your own browser session to classify and link it; nothing goes to any other service. On disk it keeps only files without content: a small settings file, the updater's backups of the app's own files, and logs with ids, counts and timings in `%LOCALAPPDATA%\ObsidiNote`. The Edge window ObsidiNote opens for Copilot keeps its own browser profile there (your sign-in, and whatever Edge itself caches), like any Edge profile.

## Project layout
```
obsidinote.ps1         entry point (parameters, I/O)
lib/Core.psm1        pure functions
lib/Update.psm1      update helpers: versions, files in use, backup, manifest, checksums
lib/OneNoteHost.psm1 open the notebook on record (or start OneNote), wait for its COM API
lib/StartChecks.psm1 the start's checks of this computer; lib/Startup.psm1: start decisions
lib/Status.psm1      [OK]/[WARN]/[FAIL] lines (start and installer)
lib/CopilotBridge.psm1, lib/Cdp.psm1
                     Microsoft 365 Copilot in Edge: connect, send prompts, rebuild replies
lib/Sso.psm1         single sign-on in ObsidiNote's Edge profile (sso-setup.cmd)
lib/AppConfig.psm1   settings (cdpPort, signIn, notebook, Edge profile), lib/Log.psm1: diagnostic log
config/              obsidinote.json (defaults), selectors.json (Copilot page);
                     *.local.json stay local and survive updates
tests/*.Tests.ps1    Pester 3.4 (inbox) syntax: Should Be
tools/               run-tests.ps1, build-release.ps1, update.ps1, sso-setup.ps1
update.cmd           update now (or -To vX.Y.Z to go back)
sso-setup.cmd        single sign-on with the Windows work account for Copilot
```

## Tests
`tools/run-tests.ps1` runs Pester over `tests/` and fails if any script file contains non-ASCII bytes.

## Release
See `AGENTS.md` → Releasing.

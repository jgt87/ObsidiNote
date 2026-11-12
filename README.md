# ObsidiNote

<img src="assets/icon-256.png" alt="ObsidiNote icon: a faceted purple stone with a white N" width="96" height="96">

A personal wiki that links itself: add anything, and Microsoft 365 Copilot files it into OneNote, linked to related pages and topics.

Status: early build. The ObsidiNote window opens and reads your notebook; adding and asking come next. See `FEASIBILITY.md` and `docs/STATUS.md`.

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
3. **OneNote**: opens your ObsidiNote vault, which also starts OneNote, and waits until OneNote answers. This is the vault you last chose in the window. Without one, it looks for a notebook called ObsidiNote or one with a `00 Index` section. The first time the vault is found, its location is saved as `"notebook"` in `config\obsidinote.local.json`.
4. **Copilot**: opens Microsoft 365 Copilot in an Edge window of its own. It has its own profile in `%LOCALAPPDATA%\ObsidiNote\edge-profile`, so your normal Edge is not touched. ObsidiNote waits up to 5 minutes for a sign-in. Later starts reuse it.
5. **ObsidiNote**: opens the ObsidiNote window, a new window of ObsidiNote's Edge, at `http://127.0.0.1:8767`. The console shows `[OK] ObsidiNote  open at http://127.0.0.1:8767`.

ObsidiNote keeps running while its console window is open. **Close that console window (or press Ctrl+C in it) to stop ObsidiNote.** Starting ObsidiNote again while it runs opens the window of the one that is running.

- Skip Copilot: start with `-NoCopilot` or set `OBSIDINOTE_NO_COPILOT=1`. The window then opens in ObsidiNote's Edge profile without Copilot (or in your default browser if Edge cannot start), and the status line says which. Skip OneNote: `-NoOneNote`. Start without opening a window: `-NoWindow` or `OBSIDINOTE_NO_WINDOW=1` (open the address yourself).
- Exit codes: 1 = a check failed, 2 = OneNote not available, 3 = Copilot could not be reached, 4 = the ObsidiNote window's local server could not start (for example, the port is in use).
- The window's local server answers on port 8767, on this computer only. Another port: `{ "uiPort": 8790 }` in `config\obsidinote.local.json`. Ports that are reserved, blocked by browsers or equal to the Edge port are refused.
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
In the ObsidiNote window today:
- **Add or ask** from one box, with Auto, Add and Ask modes (`Ctrl+1` Add, `Ctrl+2` Ask, `Enter` sends, `Shift+Enter` adds a line). In Auto, fixed rules say before you send whether the text will be added or asked, and why. Sending says that Add and Ask come in the next step.
- **Notebook switcher** at the top of the side bar: every notebook open in OneNote. ObsidiNote vaults come first; for now a vault is a notebook with a `00 Index` section, whatever its name. Other notebooks are marked "read only" and are never written to. Choosing a vault makes it the active vault. ObsidiNote remembers it in the window and as `"notebook"` in `config\obsidinote.local.json`, so the next start opens that vault. While a read-only notebook is shown, the box says that an Add still goes to the active vault.
- **The shown notebook** in the side bar: its sections and section groups with their page counts, read from OneNote.
- **Recently changed**: the 10 most recently changed pages of the shown notebook; a title opens the page in OneNote.
- A note in the side bar when OneNote, the notebook or Copilot needs your attention. Nothing is shown when all is well.
- The window only reads your notebooks. It writes nothing to disk except the active vault's location in the settings file, and the browser keeps only the active vault's id, never content.

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
lib/Server.psm1      the window's local server on 127.0.0.1 (prebuilt ui/ and a JSON API)
lib/Intent.psm1      Add or Ask rules; lib/NotebookView.psm1: sections and recent pages (read only)
lib/AppWindow.psm1   opens the ObsidiNote window in ObsidiNote's Edge
ui/                  the built interface (served as is; no Node needed to run ObsidiNote)
ui-src/              its source: React + Vite + TypeScript (npm run build writes ui/)
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
The interface: in `ui-src`, `npm install` once, then `npm run typecheck`, `npm test` and `npm run build` (writes `ui/`, which is committed).

## Release
See `AGENTS.md` → Releasing.

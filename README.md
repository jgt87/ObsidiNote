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
3. **OneNote**: opens the notebook of your ObsidiNote vault, which also starts OneNote, and waits until OneNote answers. This is the vault you last chose in the window. Without one, it looks for a notebook called ObsidiNote or one with a `00 Index` section. The first time the vault is found, its location is saved as `"notebook"` in `config\obsidinote.local.json`.
   **Vault**: continues in the vault you used last (`"vaultId"`), else in the only vault that is open. It takes the vault's writer lease, so this ObsidiNote is the one that writes there (a second one runs read only and says so), and checks the vault's index against the notebook: pages missing from the index are added and counted. No vault open, or several and none chosen: a `[WARN]` line, and you choose or make one in the window.
4. **Copilot**: opens Microsoft 365 Copilot in an Edge window of its own. It has its own profile in `%LOCALAPPDATA%\ObsidiNote\edge-profile`, so your normal Edge is not touched. ObsidiNote waits up to 10 minutes for a sign-in. Later starts reuse it.
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
- **"Copilot message box never appeared"**: sign in to Copilot in ObsidiNote's Edge window within 10 minutes and choose "Stay signed in", then start again.
- Still stuck: send the last 30 lines of `%LOCALAPPDATA%\ObsidiNote\logs\obsidinote.log`. They hold ids, counts, timings and states only, never your content.

## Features
In the ObsidiNote window:
- **Add or ask** from one box, with Auto, Add and Ask modes (`Ctrl+1` Add, `Ctrl+2` Ask, `Enter` sends, `Shift+Enter` adds a line). In Auto, fixed rules say before you send whether the text will be added or asked, and why; when it could be either, Copilot decides and an Add that reads as a question offers "Ask it" instead.
- **Add**: text or a link becomes a OneNote page in the active vault. It lands in the `01 Intake` first, then Copilot picks its type, topics and links, and ObsidiNote writes the page into its bucket (`Notes`, `Meetings`, `Decisions`, ...) with its properties, your text with links to related pages, and "Linked from" on those pages, and updates the central index. The result shows where it sits in the index, its topics and every link with its strength and reason, and related pages you already had. **Undo** moves the page to OneNote's Deleted Pages.
- **Check for the answer**: when Copilot needs longer than about 2 minutes (reading a SharePoint page can take longer), ObsidiNote does not stop it. The result says Copilot is still working and the item waits in your Intake; **Check for the answer** reads Copilot's answer later and files the page. The same goes for updating a link page. Only the answer meant for that item is used (each request carries a short reference Copilot repeats); anything else writes nothing.
- **Export as Markdown**: a copy of one page, a topic or the whole vault as Markdown files for Obsidian or any editor (front matter, `[[links]]` between pages, a folder per topic). From the page window, the topic in List, or **Export all as Markdown** in the side bar. The file goes to your browser's downloads; images and attached files stay in OneNote.
- **Links**: a pasted link becomes one summary page, in `Internal links` (SharePoint, OneDrive, Teams, Loop) or `Web links`. The same link again updates its page; **Update** reads the source again, shows old against new, keeps earlier summaries on the page and never touches your "Your notes" part.
- **Ask**: a question walks the central index (branches, then pages, then their text) and the answer cites your own pages, each opening in OneNote, with the path it took. "Ask reads" adds other vaults and connected notebooks (read only) and archived pages. Ask a follow-up, save the answer as a page, or show its sources on the map. Asking never changes your notebook.
- **Knowledge graph**: the shown vault or notebook as dots in topic areas, with links as lines weighted by strength; hover for a preview, click for the page with its links and "Ask about this", `/` to search, and a list view.
- **Vaults**: a vault is a notebook (or a section group inside one) with ObsidiNote's sections and its own index, recognised by its state page whatever its name. The **notebook switcher** lists vaults first and every other open notebook as read only. Choosing a vault makes it the active vault: ObsidiNote takes its writer lease and remembers it for the next start. **New ObsidiNote vault** makes one.
- **Write guard**: ObsidiNote writes only inside the active vault; every other notebook, and every other vault, is only read.
- **The shown notebook** in the side bar: its sections and section groups with their page counts, and **Recently changed** with its 10 most recently changed pages.
- A note in the side bar when OneNote, the vault or Copilot needs your attention. Nothing is shown when all is well. Without Copilot, Add and Ask say so and the rest works.
- On disk ObsidiNote keeps only the active vault's record (`"vaultId"`, `"notebook"`) in the settings file; the browser keeps only the active vault's id, never content.

### Starting a vault
1. Start ObsidiNote. With no vault open, the console says `[WARN] Vault  no ObsidiNote vault is open`.
2. In the window, choose **New ObsidiNote vault** in the side bar and give it a name. ObsidiNote makes a notebook with that name next to your cloud notebooks (or in OneNote's default notebook folder when that is not possible) with its fixed sections, and makes it the active vault.
3. Or tick **Inside an existing notebook** and choose one: the vault becomes a section group there. ObsidiNote asks before it writes into that notebook; the rest of it stays read only.
4. Next starts continue in that vault. To continue in a vault made elsewhere, open its notebook in OneNote and choose it in the switcher.

Planned:
- Files dropped in the box, Archive and delete, Tidy up, History.

## Screenshots
Design mock-ups of the interface, with invented example content.

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
Everything ObsidiNote knows lives in your own OneNote notebook: your pages, the Intake, the central index and its links. ObsidiNote keeps no copy on disk; it reads the notebook while it runs (an export you ask for is the one exception: it goes to your browser's downloads, and ObsidiNote keeps nothing of it), so the notebook's own protection (OneDrive or SharePoint, your organisation's labels and retention) covers all of it. Text you add is sent to Microsoft 365 Copilot in your own browser session to classify and link it; nothing goes to any other service. On disk it keeps only files without content: a small settings file, the updater's backups of the app's own files, and logs with ids, counts and timings in `%LOCALAPPDATA%\ObsidiNote`. The Edge window ObsidiNote opens for Copilot keeps its own browser profile there (your sign-in, and whatever Edge itself caches), like any Edge profile.

## Project layout
```
obsidinote.ps1         entry point (parameters, I/O)
lib/Server.psm1      the window's local server on 127.0.0.1 (prebuilt ui/ and a JSON API)
lib/Intent.psm1      Add or Ask rules; lib/NotebookView.psm1: sections and recent pages (read only)
lib/OneNote.psm1     OneNote COM adapter and the write guard (writes only inside the active vault)
lib/Vault.psm1, lib/VaultSession.psm1
                     vaults by their state page, new vault, the active vault and its writer lease
lib/NotebookStructure.psm1, lib/PageMeta.psm1, lib/WriterLease.psm1
                     fixed sections and buckets, obsn.* Meta and owned outlines, the lease
lib/Index.psm1       the central index (load, rebuild, completeness, Index pages, connected notebooks)
lib/VaultStore.psm1  what Add writes through; lib/Ingest.psm1, Linker, LinkCapture: Add and links
lib/Ask.psm1, lib/AskSources.psm1
                     Ask over the index; lib/GraphModel.psm1: the knowledge graph's data
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
validation/          Run Validation.cmd: checks with a masked log to send back
docs/runbooks/       step-by-step checks (RB-00 .. RB-06)
update.cmd           update now (or -To vX.Y.Z to go back)
sso-setup.cmd        single sign-on with the Windows work account for Copilot
```

## Tests
`tools/run-tests.ps1` runs Pester over `tests/` and fails if any script file contains non-ASCII bytes.
The interface: in `ui-src`, `npm install` once, then `npm run typecheck`, `npm test` and `npm run build` (writes `ui/`, which is committed).

On the PC where ObsidiNote runs, `validation\Run Validation.cmd` checks this computer, OneNote, Copilot and the window, and writes a log without content to the Desktop (`ObsidiNote-validation-<date>.txt`) that you can send back. The steps are in `docs/runbooks/` (start with RB-00).

## Release
See `AGENTS.md` → Releasing.

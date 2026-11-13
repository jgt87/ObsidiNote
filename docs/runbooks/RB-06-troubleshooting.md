# RB-06 Troubleshooting

The failures seen so far, and what fixes them. When none fits, collect the app log (last section)
and send it with the kit's Desktop files.

## Edge window closes at once

- What you see: ObsidiNote opens an Edge window for Copilot, and it closes right away. The console
  may say "Edge policy BrowserSignin = 2".
- Why: this PC requires every Edge profile to be signed in to Edge itself (Edge policy
  `BrowserSignin = 2`), and ObsidiNote's own profile was not signed in yet.
- Fix: start ObsidiNote (v0.2.5 or later). It shows `[WARN] Edge sign-in  one time: sign in to Edge
  with your work account` and opens Edge's own sign-in. Sign in to Edge with your work account.
  It waits up to 5 minutes and goes on by itself. This is needed once.
- Check: the kit's V3 line `Edge profile  account: work; ...; Edge sign-in required: yes`.

## 'uter' is not recognized, or 'aces' is not recognized

- What you see: during an update, the console prints `'uter' is not recognized as an internal or
  external command` (or `'aces' ...`), and ObsidiNote starts twice.
- Why: an old launcher (from before v0.2.4) was replaced on disk while it ran, and Windows read on
  in the new file. Launchers since v0.2.4 are safe against this.
- Fix: nothing to do. Close the extra console window. It happens once, during that update only.

## Copilot: "Lost the connection"

- What you see: `[FAIL] Copilot  Lost the connection ...` during the first start or sign-in.
- Why: the sign-in replaces Copilot's tab a few times; old versions gave up too early.
- Fix: fixed in v0.2.4. Update (RB-01) and start again.

## Install fails with many errors, one per line

- What you see: the install line from RB-01 prints a red error for almost every line.
- Why: on some PCs `irm ... | iex` runs the installer line by line. Fixed in v0.2.3: the installer
  now works line by line.
- Fix: run the install line from RB-01 again; it fetches the current installer.

## Other messages

- `[WARN] Edge profile ... SSO off`: run `sso-setup.cmd` once (RB-02 step 5).
- "Edge profile is already open in an Edge window ... without its debug port": close every window
  of ObsidiNote's Edge (also check the taskbar), then start again.
- `[FAIL] Edge policies ... RemoteDebuggingAllowed = 0`: ObsidiNote cannot drive Copilot on this PC.
  Send the kit's log; IT has to allow it.
- `[WARN] OneNote running  not running`: open OneNote before stage V2.
- `[FAIL] OneNote COM`: repair Office (desktop OneNote), then run the kit again.
- Kit `[WARN] Copilot  not run: Edge requires a browser sign-in first`: do RB-02, then run the kit
  again.
- Kit `[FAIL] ObsidiNote-Probe  could not open or create`: open a OneDrive notebook in OneNote, or
  run with `-ProbeBasePath` and your OneDrive Documents address.

## Collect the app log

ObsidiNote keeps a diagnostic log at `%LOCALAPPDATA%\ObsidiNote\logs\obsidinote.log`. It holds
ids, counts, timings and states only. Every line is masked before it is written: e-mail addresses,
ids, the query part of web addresses, your user folder, user name and computer name are replaced.

1. Open **Windows PowerShell** and paste:
   ```powershell
   Get-Content "$env:LOCALAPPDATA\ObsidiNote\logs\obsidinote.log" -Tail 200 | Set-Content "$env:USERPROFILE\Desktop\obsidinote-log-tail.txt"
   ```
   - What you should see: no output; a file `obsidinote-log-tail.txt` on your Desktop.
   - If not, send this: the red error text (it may say the log does not exist yet: then start
     ObsidiNote once and try again).

2. Open the file in Notepad and look through it. You should see times, short states and numbers,
   and no page titles or text.

3. Send `obsidinote-log-tail.txt` together with the kit's Desktop files.

Only when asked: `%LOCALAPPDATA%\ObsidiNote\logs\update.log` (the updater) and
`%LOCALAPPDATA%\ObsidiNote\logs\ObsidiNote-sso-<date>.txt` (single sign-on setup; names and yes/no
values only).

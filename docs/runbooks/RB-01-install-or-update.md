# RB-01 Install or update ObsidiNote

Takes about 2 minutes. No admin rights needed.

## First install

1. Open **Windows PowerShell** (Start menu, type `PowerShell`, choose "Windows PowerShell").
   - What you should see: a blue or black window with a prompt that starts with `PS` and ends with `>`.
   - If not, send this: a screenshot of what opened.

2. Copy this one line, paste it into the window (right-click pastes) and press Enter:
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/jgt87/ObsidiNote/main/install.ps1 | iex"
   ```
   - What you should see: a few status lines that start with `[OK]`, a block "This computer",
     and at the end that ObsidiNote was installed in `%LOCALAPPDATA%\Programs\ObsidiNote`.
     An **ObsidiNote** shortcut appears on the Desktop and in the Start menu.
   - If not, send this: a screenshot of the whole window, or copy all text in the window
     (select it with the mouse, press Enter to copy) into a mail. If you see a red line
     about a blocked script or antivirus, say so.

3. Check the version: open `%LOCALAPPDATA%\Programs\ObsidiNote\version.txt` (paste that path into
   the Explorer address bar, then open the file).
   - What you should see: one line like `v0.3.0`.
   - If not, send this: what the file shows, or that it is missing.

## Update

ObsidiNote updates itself every time it starts.

1. Start **ObsidiNote** from the Desktop or the Start menu.
   - What you should see: the first status line is `[OK] Update ...`. After an update it says
     `updated v0.x.y -> v0.x.z`, and the new version starts by itself. Without an update it says
     that the newest version is installed.
   - If not, send this: the `Update` line (a screenshot is fine).

2. Or update without starting: double-click `update.cmd` in `%LOCALAPPDATA%\Programs\ObsidiNote`.
   - What you should see: a line that names the installed and the newest version.
   - If not, send this: a screenshot of the window.

Known once-only glitch: while an update replaces an old launcher (from before v0.2.4) that is still
running, it can print `'uter' is not recognized` or `'aces' is not recognized`, and ObsidiNote
starts twice. That happens once, during that update only. Close the extra window. See RB-06.

## When you are done

Go on with [RB-02 First start and sign-in](RB-02-first-start-and-sign-in.md).

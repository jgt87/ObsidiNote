# RB-02 First start and sign-in

Takes about 5 minutes, once. ObsidiNote opens Microsoft 365 Copilot in an Edge window of its own,
with its own Edge profile. Your normal Edge is not touched.

On this PC, Edge requires that every Edge profile is signed in to Edge itself first (Edge policy
`BrowserSignin = 2`). ObsidiNote's profile is new, so the first start asks you to sign in to Edge
once.

## Steps

1. Open **OneNote** (the desktop app) and wait until it shows your notebooks.
   - What you should see: your notebooks in OneNote's notebook list.
   - If not, send this: a screenshot of OneNote.

2. Start **ObsidiNote** from the Desktop or the Start menu.
   - What you should see: a console window with status lines. Under "This computer" every line
     is `[OK]`, except possibly:
     - `[WARN] Edge profile ... not signed in` with the hint to sign in to Edge (normal the first
       time on this PC).
     - `[WARN] Edge profile ... SSO off` (see step 5).
   - If not, send this: a screenshot of the console window. A `[FAIL]` line says what to fix.

3. When the console shows `[WARN] Edge sign-in  one time: sign in to Edge with your work account`,
   an Edge window opens with Edge's own sign-in.
   - Sign in to Edge with your work account. Use the same account as for Microsoft 365.
   - What you should see: the console then shows `[OK] Edge sign-in ...` by itself (it waits up
     to 10 minutes), and Copilot opens in that Edge window.
   - If the Edge window closes at once and nothing asks you to sign in: see RB-06, "Edge window
     closes at once".

4. If Copilot asks you to sign in, sign in and choose **Stay signed in**.
   - What you should see: `[OK] Copilot  connected in ObsidiNote's Edge window (port 9334)`.
   - If not, send this: the `Copilot` line and its hint (a screenshot is fine), plus the log of
     RB-06, "Collect the app log".

5. Only when the start showed `[WARN] Edge profile ... SSO off`: double-click `sso-setup.cmd` in
   `%LOCALAPPDATA%\Programs\ObsidiNote` and answer `y` when it asks.
   - What you should see: it says single sign-on is on for ObsidiNote's profile. Close
     ObsidiNote's Edge window and start ObsidiNote again; the `Edge profile` line now says `SSO on`.
   - If not, send this: a screenshot, and the file
     `%LOCALAPPDATA%\ObsidiNote\logs\ObsidiNote-sso-<date>.txt` (names and yes/no values only).

6. The ObsidiNote window opens.
   - What you should see: `[OK] ObsidiNote  open at http://127.0.0.1:8767`, and a window with the
     box "Add or ask", and your notebooks in the side bar (ObsidiNote vaults first, the others
     marked "read only").
   - If not, send this: a screenshot of the console and of the window.

7. Leave ObsidiNote running for RB-03, or close its console window to stop it. Both are fine.

## Next time

Later starts reuse the sign-in. You should see only `[OK]` lines and the window.

Go on with [RB-03 Run the validation kit](RB-03-run-validation.md).

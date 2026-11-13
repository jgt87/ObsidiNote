# RB-00 Overview: what to run, in which order

These runbooks walk you through testing ObsidiNote on a managed Windows PC with a Microsoft 365
business account and Copilot. You need no admin rights. Every step says what you should see, and
what to send back if you see something else.

## Which runbook when

Do them in this order. Each one takes a few minutes.

| Order | Runbook | When |
|---|---|---|
| 1 | [RB-01 Install or update](RB-01-install-or-update.md) | First time, or when a new version is out |
| 2 | [RB-02 First start and sign-in](RB-02-first-start-and-sign-in.md) | Once after the install, and when sign-in breaks |
| 3 | [RB-03 Run the validation kit](RB-03-run-validation.md) | After RB-02; again after every update |
| 4 | [RB-04 Grounding probes](RB-04-grounding-probes.md) | With RB-03; then again after 1 hour and after 24 hours |
| 5 | [RB-05 Vaults, Add, Ask, knowledge graph](RB-05-vaults-add-ask-graph.md) | From the first release with Add |
| - | [RB-06 Troubleshooting](RB-06-troubleshooting.md) | Whenever a step does not show what it should |

## How to send the results back

1. The kit writes two files to your Desktop:
   - `ObsidiNote-validation-<date>-<time>.txt` (the log)
   - `ObsidiNote-validation-<date>-<time>.json` (the same summary, for a program to read)
2. Open the `.txt` file in Notepad and read it if you like. It is short.
3. Send both files back (mail or chat attachment).

## What the log holds, and what it never holds

The log holds:
- A header: the date and time, the kit version, the ObsidiNote version, the PowerShell and
  Windows versions, the stages that ran and the options used (for example `-WriteTest`).
- One line per check: `[OK]`, `[WARN]`, `[FAIL]`, `[SKIP]` or `[INFO]`, the name of the check,
  and counts, yes/no answers and timings (for example "12 sections, 340 pages; 850 ms").
- A footer: how many checks had each status, and the total time.

The log never holds:
- Page titles, page text, section names, or the names of your notebooks. Your notebooks are shown
  as "notebook #1", "notebook #2". Only the kit's own test notebooks keep their names:
  `ObsidiNote-Probe` and `ObsidiNote-Validation`.
- What was sent to Copilot, or what Copilot answered. Only the length of the answer and whether it
  had the expected shape.
- Web addresses with a path. Only the site name is kept, and SharePoint site names are hidden too
  (`<tenant>.sharepoint.com`).
- Your user name, e-mail address, the computer name, your organisation's name, tenant ids or other
  ids. Your user folder is shown as `%USERPROFILE%`.

Every line is checked and masked before it is written, as a second line of defence.

## Words used

- **Kit**: the validation scripts in the `validation` folder of ObsidiNote.
- **Stage**: one group of checks, V1 to V6. See RB-03.
- **Write test**: a check that writes into OneNote. The kit writes only into its own throwaway
  notebooks `ObsidiNote-Probe` and `ObsidiNote-Validation`, never into your notebooks.

# Status - ObsidiNote

Updated: 2026-11-13. Status values: `todo` / `done (code)` / `verified` / `unverified live`.

| # | Item | Status | Evidence |
|---|---|---|---|
| 1 | Scaffold builds and tests pass | verified | `tools/run-tests.ps1`, 2026-11-12 |
| 2 | P1 OneNote COM round trip (consumer account) | verified | `probes/p1-roundtrip.ps1` 2026-11-12: all OK, owned-outline rewrite keeps the body |
| 3 | P1 on a Microsoft 365 business tenant | todo | `probes/README.md` |
| 4 | P2 Copilot linking quality (20 dummy notes) | todo | needs a working Copilot connection |
| 5 | P3 Copilot grounding on OneNote (business tenant) | todo | marker prompt in `probes/p3-copilot-prompt.txt` |
| 6 | P4 Copilot grounding on Loop (business tenant) | todo | |
| 7 | Central index in the OneNote Index section (topic tree, obsn.* Meta, path-based Ask) | todo | design in FEASIBILITY.md section 5 (storage principle) |
| 7a | Notebook structure (00 Index, 01 Inbox, type buckets, Archive) + completeness rule (every page listed) | designed | FEASIBILITY.md, Notebook structure and Central index; code todo |
| 7c | Links: Internal links / Web links buckets, summary page shape, dedup by URL, Links index page | designed | FEASIBILITY.md, Links; probes P7 (SharePoint/OneDrive) and P8 (web) todo |
| 7d | Archive (default, restorable) and delete (confirmed, via OneNote Deleted Pages) | designed | FEASIBILITY.md, Archive and delete; probe P1c (links after a move or delete) todo |
| 7b | P1b: Meta value size limit, Index load time at 100 / 1,000 / 5,000 pages | todo | decides how the catalogue is split over topic pages |
| 8 | Web UI step 1: ObsidiNote window (server on 127.0.0.1:8767, home with Add/Ask box and live intent, notebook switcher with vaults first and read-only notebooks, real sections and recent pages, attention notes; graph and history empty) | done (code); unverified live with Copilot | 2026-11-13: `tools/run-tests.ps1` 246 passed; `ui-src` typecheck, 24 vitest tests, build OK; local run without Copilot answered `/`, `/api/status`, `/api/notebooks`, `/api/notebook?id=` (real OneNote, read only), `/api/intent` (403 on a bad Origin). Not yet seen: the window opening in ObsidiNote's Edge next to Copilot, and a real vault (none open on the test PC) |
| 8c | Connected notebooks and several vaults: full structure detection (state page, obsn.vaultId, vaults in section groups), write guard | todo | FEASIBILITY.md "Connected notebooks", "Several ObsidiNote vaults"; step 1 has the thin read-only part (`00 Index` check) |
| 8b | Web UI: Add / Ask / Map behaviour | todo | design in FEASIBILITY.md section 5; submit answers 501 until then |
| 9a | Build order (user, 2026-11-13): 1 window (v0.3.0), 2 structure + vaults + index, 3 knowledge graph, 4 Add, 5 Ask | in progress | steps 2-5 built in parallel in worktrees ObsidiNote-step2..5 (branches step2-index, step3-graph, step4-add, step5-ask); step 5 done on its branch; merged one by one with full tests between |
| 9 | Auto-update on start | verified | 2026-11-12: a v0.1.0 install updated itself to v0.1.1 at start ("updated v0.1.0 -> v0.1.1"); the second start was silent |
| 11 | Startup: start OneNote when not running, wait for COM | verified | `lib/OneNoteHost.psm1` + 9 tests; live 2026-11-12: "OneNote is running and ready." |
| 12 | Startup: open Copilot in own Edge profile (port 9334), wait for sign-in | verified | Business-tenant test 2026-11-12 (v0.2.5): one-time Edge sign-in (BrowserSignin = 2) then "[OK] Copilot connected in ObsidiNote's Edge window (port 9334)"; profile now "signed in with a work account; SSO on". The double run with "'aces' is not recognized" was the one-time old-launcher glitch of that update. |
| 10 | Public repo, releases | verified | github.com/jgt87/ObsidiNote; v0.1.0 and v0.1.1 with zip + SHA256SUMS |

Current blocker: P3 and P4 need a business tenant with a Copilot licence.

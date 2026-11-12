# Status - ObsidiNote

Updated: 2026-11-12. Status values: `todo` / `done (code)` / `verified` / `unverified live`.

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
| 8 | Web UI: Add / Ask / Map | todo | design in FEASIBILITY.md section 5 |
| 9 | Auto-update on start | verified | 2026-11-12: a v0.1.0 install updated itself to v0.1.1 at start ("updated v0.1.0 -> v0.1.1"); the second start was silent |
| 11 | Startup: start OneNote when not running, wait for COM | verified | `lib/OneNoteHost.psm1` + 9 tests; live 2026-11-12: "OneNote is running and ready." |
| 12 | Startup: open Copilot in own Edge profile (port 9334), wait for sign-in | unverified live (fix done (code)) | Business-tenant test 2026-11-12 (v0.2.3): failed fast with "Lost the connection to the Copilot tab". Fixed in code: no navigating a sign-in page back to Copilot, retries bounded by the 300 s sign-in time (not 15 attempts), no second Edge window (profile in use without the debug port stops with "close that Edge window"), forced browser sign-in (BrowserSignin = 2) and blocked debug port named, single sign-on setup (`sso-setup.cmd`, `lib/Sso.psm1`), `"signIn"` setting, status-line start (update + relaunch, checks, notebook record). 154 tests pass 2026-11-12; `-NoCopilot` smoke run OK. Needs a live start on a business tenant: start lines, `sso-setup.cmd`, "[OK] Copilot connected". |
| 10 | Public repo, releases | verified | github.com/jgt87/ObsidiNote; v0.1.0 and v0.1.1 with zip + SHA256SUMS |

Current blocker: P3 and P4 need a business tenant with a Copilot licence.

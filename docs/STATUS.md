# Status - ObsidiNote

Updated: 2026-11-12. Status values: `todo` / `done (code)` / `verified` / `unverified live`.

| # | Item | Status | Evidence |
|---|---|---|---|
| 1 | Scaffold builds and tests pass | verified | `tools/run-tests.ps1`, 2026-11-12 |
| 2 | P1 OneNote COM round trip (consumer account) | verified | `probes/p1-roundtrip.ps1` 2026-11-12: all OK, owned-outline rewrite keeps the body |
| 3 | P1 on a Microsoft 365 business tenant | todo | `probes/README.md` |
| 4 | P2 Copilot linking quality (20 dummy notes) | todo | needs a working CCBridge MCP connection |
| 5 | P3 Copilot grounding on OneNote (business tenant) | todo | marker prompt in `probes/p3-copilot-prompt.txt` |
| 6 | P4 Copilot grounding on Loop (business tenant) | todo | |
| 7 | Central index in the OneNote Index section (topic tree, obsn.* Meta, path-based Ask) | todo | design in FEASIBILITY.md section 5 (storage principle) |
| 7b | P1b: Meta value size limit, Index load time at 100 / 1,000 / 5,000 pages | todo | decides how the catalogue is split over topic pages |
| 8 | Web UI: Add / Ask / Map | todo | design in FEASIBILITY.md section 5 |
| 9 | Auto-update on start (ported from CCBridge) | in progress | |

Current blocker: P3 and P4 need a business tenant with a Copilot licence.

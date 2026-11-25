# Decisions

The settled decisions of ObsidiNote, one entry each: what the operator decided, and every
deviation from a CommonShared rule. Append; never rewrite an entry. A change of mind is a new
entry that replaces the old one (set the old one's status to `replaced` and add `Replaced by`).
Elsewhere, cite the id (`# D-001`, `/* design: D-001 */`, "(D-001)" after a line in DESIGN.md or
AGENTS.md) instead of restating the decision.
Format and checks: CommonShared docs/09 §8, `templates/scripts/decisions.mjs`.

- **By:** `operator`, or `agent` for a call the operator has not confirmed yet.
- **Rule:** the shared rule it is about, as `<rule file id>:<slug>` (the audit's key) with
  `follows` or `deviates`; left out when no shared rule covers it.
- **Intent** is the goal, worded so another solution could meet it; **Decision** is the
  solution chosen.

Entries D-001 to D-124 were moved here on 2026-11-25 from "(operator, <date>)" stamps in the
docs, code comments and test names, and from DESIGN.md's accepted deviations; each keeps the
date it was first recorded. Quotes are the operator's words.

## D-001 Never name the reference note app or the sister projects — active
- Date: 2026-11-12
- By: operator (2026-11-12 and 2026-11-13)
- Intent: the project stands on its own; nothing in it points at the product its ideas came from or at the author's other projects
- Decision: those names appear nowhere tracked (code, comments, UI, docs, tests, config, commits, release notes); features are described on their own terms; the only allowed spelling is Microsoft's Copilot endpoint path in URL patterns; `tests/NoReferenceName.Tests.ps1` enforces it

## D-002 Existing data follows a changed rule — active
- Date: 2026-11-13
- By: operator ("think of a way how fixes can be applied to the relevant existing knowledge")
- Intent: a change of a filing, indexing or page-shape rule also holds for the pages filed before it
- Decision: an upgrade step in `lib/Upgrade.psm1` that runs at the next start (writer only, idempotent, counts in the status line, refused writes reported, never a delete), or a stated reason why none is needed; named in the CHANGELOG line and tested on old-shaped data

## D-003 The Add result is as wide as the box — active
- Date: 2026-11-13
- By: operator
- Intent: the box and the result under it line up
- Decision: the result takes the page's own width, like the box above it; no `max-width` of its own

## D-004 The side bar stays in view — active
- Date: 2026-11-13
- By: operator (sticky on 2026-11-13; what scrolls on 2026-11-14)
- Intent: the logo, the navigation and the footer (notes, counts, theme) are always visible
- Decision: the side bar is `position: sticky`; only its section list scrolls, inside its own box

## D-005 Send the person to the real source, OneNote as little as possible — active
- Date: 2026-11-13
- By: operator ("use OneNote as little as possible as the interface")
- Intent: a link leads where the thing really lives; OneNote is the store, not the way in
- Decision: a link page opens its own address first and OneNote second; an address in an answer opens itself

## D-006 Page labels on the map sit on a pill — active
- Date: 2026-11-13
- By: operator ("more readable, maybe with a pill/cell element around the text")
- Intent: links and dots never run through a page name
- Decision: each page label sits on a small solid pill

## D-007 A page is edited in the page window — active
- Date: 2026-11-13
- By: operator ("adjust the title, adjust/replace/update links, page details")
- Intent: a page's title, links and details can be changed without opening OneNote
- Decision: an Edit form in the page window (`graph/editModel.ts`, `POST /api/page/edit`)

## D-008 The box keeps its text only when nothing was sent — active
- Date: 2026-11-13
- By: operator
- Intent: what was typed is never lost, and never sent twice by accident
- Decision: the box empties once the server has processed the text (any answer, also failed or waiting: the text is then on the result and in the Intake); it keeps the text only when the call itself failed

## D-009 Never share a local port with another tool — active
- Date: 2026-11-14
- By: operator
- Rule: security:give-each-app-a-fixed-documented — follows
- Intent: two programs on one computer never drive each other's browser or window
- Decision: ObsidiNote's own ports (`uiPort` 8767, `cdpPort` 9334); the other local tool's 9333 and 8765/8766, the reserved 3000/3100 and the Fetch bad ports are refused by `lib/AppConfig.psm1`

## D-010 Vault settings live in the vault — active
- Date: 2026-11-14
- By: operator ("a central settings modal accessible from the menu")
- Intent: a vault's settings follow it to every PC; settings of one PC stay on that PC
- Decision: one `obsn.settings` Meta on the state page (`lib/VaultSettings.psm1`), missing keys added at start, existing values never set back; the menu's Settings dialog edits them; the port, sign-in, notebook record and theme stay local

## D-011 Ask reads up to 50 pages, 20 by default — active
- Date: 2026-11-14
- By: operator
- Intent: the person decides how much of the wiki one answer may read
- Decision: vault setting `askMaxPages`, 1 to 50, default 20 (was fixed at 8); the text budget is shared, so more pages means less text each

## D-012 Export as Markdown is not in the side bar — active
- Date: 2026-11-14
- By: operator
- Intent: export is offered where the pages it exports are shown
- Decision: the export buttons sit in the page window and the List (per page and per topic), not in the side bar

## D-013 Waiting for Copilot and History come from the Intake — active
- Date: 2026-11-14
- By: operator
- Intent: the person sees what ObsidiNote did and what still waits, without a log or cache on disk
- Decision: `lib/Activity.psm1` reads the vault's `01 Intake` items into the home page's "Waiting for Copilot" (Check for the answer, Remove) and History (Undo); edits and "Link it" make no Intake item and are not listed

## D-014 The map can be grouped by source — active
- Date: 2026-11-14
- By: operator ("switch from topic areas to data sources: SharePoint is one source, OneDrive another")
- Intent: the person can see where the pages come from as well as what they are about
- Decision: a Sources grouping: one area per Microsoft 365 app (SharePoint per site), company service and public web site, by host rule (`Get-LinkSource`, `graph/sourceView.ts`)

## D-015 A page without an address records where it came from — active
- Date: 2026-11-14
- By: operator ("record where new items come from")
- Intent: a page that is not a link still says which app it came from
- Decision: `obsn.origin`, guessed from the pasted HTML and shown as "From:" before Add, changeable in Edit; one origin table on the server, pinned by `tests/fixtures/origins.json`

## D-016 A dropped file in a synced folder becomes its link page — active
- Date: 2026-11-14
- By: operator ("If the file is from OneDrive then the link to the original file should be stored")
- Intent: a file that lives online is filed under its online address
- Decision: the window sends the file's name, size and time; `lib/SyncedFiles.psm1` finds it in the folders OneDrive syncs and the Add becomes that address's link page, summarized from the file's text

## D-017 Ask shows what its answer was made from — active
- Date: 2026-11-14
- By: operator ("a bar ... how much of the answer came from each source"; show that nothing relevant was skipped)
- Intent: the person can judge an answer by its sources
- Decision: the answer card lists the pages and topics it used, a share bar per source, the sentences per page, and the pages read but not cited (`unused`)

## D-018 Ask's sources are quiet until pointed at — active
- Date: 2026-11-14
- By: operator ("only do the accent color on hover")
- Intent: the answer reads calmly; the link between a source and its sentences shows on demand
- Decision: the accent only for the source under the pointer or keyboard focus, whose sentences in the answer turn to the accent too

## D-019 Dot size is the page's link weight, on one smooth scale — active
- Date: 2026-11-14
- By: operator (being linked to is what makes a page matter)
- Intent: a dot's size says how much the page matters, with no jumps
- Decision: the strengths of the links to the page plus half of its own (`graph/weights.ts`), one smooth radius scale; a hub gets a thicker outline, not a bigger size

## D-020 One line per pair of topics, few at rest — active
- Date: 2026-11-14
- By: operator (page-to-page links across topics crossed the whole map)
- Intent: the map at rest is a calm picture; the detail is there on demand
- Decision: one line per pair of topic areas, as wide as their summed links; at rest the 8 heaviest, all of them from 1.5x the fitted zoom, all of a topic's when one of its pages is focused

## D-021 A topic line never passes under another topic — active
- Date: 2026-11-14
- By: operator
- Intent: a line never reads as joining a topic it does not join
- Decision: the areas are placed so linked topics sit next to each other (a cost per line that would pass another area), and a line that still meets a third area bends round it through the middle of the gap

## D-022 A topic's name sits in the middle of its own area — active
- Date: 2026-11-14
- By: operator (names above or below an area sat in the gaps where the lines run)
- Rule: design:a-label-over-data-marks-gets — follows
- Intent: a topic name never meets a line or covers the pages it names
- Decision: the name is centred on its area in room the layout keeps free of dots, and gives way while the pointer is over the area or one of its pages is focused

## D-023 Fit to screen fills the frame for a small vault — active
- Date: 2026-11-14
- By: operator (25 pages used a third of the frame)
- Intent: a small map is shown at a readable size
- Decision: "Fit to screen" zooms in up to a fixed limit; labels are screen pixels, so they keep their size

## D-024 The hover card covers the fewest linked pages — active
- Date: 2026-11-14
- By: operator (the card hid the very links it was about)
- Intent: the preview card never hides what it describes
- Decision: the card takes the corner beside the dot that stays on the stage and covers the fewest linked pages

## D-025 "Link it" writes a related link — active
- Date: 2026-11-14
- By: operator
- Intent: a link the person makes by hand counts as the person's own decision on the map
- Decision: "Link it" writes strength 2 (related); older links of strength 1 are raised by upgrade step `link-strength`

## D-026 Recently changed rows open the page window — active
- Date: 2026-11-14
- By: operator
- Intent: a page listed on the home page opens where it is read in ObsidiNote
- Decision: each row carries its graph key and type and opens the page window

## D-027 Ask's options show only when the text will be asked — active
- Date: 2026-11-14
- By: operator
- Intent: the box shows only the choices that apply to what will happen
- Decision: what Ask reads (sources, archived) is shown under the box only when the text will be asked

## D-028 The side bar's order and groups — active
- Date: 2026-11-14
- By: operator
- Intent: the side bar reads as distinct groups in a fixed order
- Decision: logo, menu, notebook switcher, sections, footer; each group after the first starts with a divider with the same space above and below

## D-029 Probe whether Copilot can read meetings — active
- Date: 2026-11-14
- By: operator ("In many meetings, Copilot is used to transcribe or use facilitator to create action lists and meeting notes")
- Intent: know whether meeting notes can come into ObsidiNote before building it
- Decision: kit probe P10: Copilot, with the person's own access, lists recent meetings with a transcript, recap or notes, and turns one into structured notes

## D-030 The code-index tool is never named — active
- Date: 2026-11-14
- By: operator
- Intent: a tool used while building leaves no trace in the project
- Decision: never named in code, docs or config; its local folder is ignored through `.git/info/exclude`; on the list of `tests/NoReferenceName.Tests.ps1`

## D-031 The Ask answer fills its card — active
- Date: 2026-11-15
- By: operator ("Answer doesn't use the full width")
- Rule: ui:long-lists-and-menus-scroll-inside — deviates
- Intent: the answer uses the room of its card, like the blocks under it
- Decision: no 72ch reading measure on the answer

## D-032 One ObsidiNote per computer: a new start replaces the running one — active
- Date: 2026-11-15
- By: operator
- Intent: a start always ends with the version just started, and two copies never fight over the vault
- Decision: the start asks the running one to stop (`POST /api/shutdown`, which gives its lease back) and, when it does not, stops leftover starts of the same script (`Invoke-ReplaceRunning`)

## D-033 A lease is taken over only from this computer — active
- Date: 2026-11-15
- By: operator
- Intent: a vault held by another PC is never taken from it; a stale hold of this PC does not block the start
- Decision: the lease carries a machine mark (`m`, a hash of the computer name); a lease that has not run out is taken over only when its mark is this computer's and the start has just found no other ObsidiNote here; otherwise wait for it to run out

## D-034 Tags are set by hand only — active
- Date: 2026-11-15
- By: operator
- Intent: tags group what nothing else relates, by the person's own judgement
- Decision: Add, link Update and Copilot never read or write `obsn.tags`; one normal form (`ConvertTo-TagList`, pinned by `tests/fixtures/tags.json`); the page's Meta wins over the index

## D-035 The active vault is kept — active
- Date: 2026-11-15
- By: operator (another notebook was the selected one in OneNote, and the vault's pages showed read only)
- Intent: a vault that was opened stays the active vault until the person switches or its notebook closes
- Decision: `Get-VaultData` puts the active vault back (`Join-ActiveVault`) when a detection misses it while its notebook is open; at start a missed vault's notebook is selected once and read again; kit V6 shows what OneNote returns per notebook

## D-036 "Check again" tries to take the vault now — active
- Date: 2026-11-15
- By: operator ("Check again doesn't seem to clear the message")
- Intent: the button does what it says and shows what came of it
- Decision: `POST /api/vault/check-lease` runs the lease renewal at once (only a free or run-out lease); the note says when the holder's lease runs out; when the window becomes the writer, the map is read again

## D-037 A lease state is worded as likely — active
- Date: 2026-11-15
- By: operator ("this currently isn't confirmed so the statement must be adjusted to make it probable/possible")
- Rule: design:a-state-the-interface-infers-is — follows
- Intent: the window never states as fact what it only infers from a record
- Decision: the read-only note says what may be the case and what happens next (`model/attention.ts`)

## D-038 Archive, restore, delete and stale links — active
- Date: 2026-11-15
- By: operator ("Do 1, 3 and 4")
- Intent: pages can be retired safely and stale link summaries refreshed
- Decision: archive, restore and delete routes that always ask first (409 `needsConfirm` with the plan); archive moves to `Archive/<bucket>`, restore moves back, delete goes through the one removal path; "Update summaries" runs link updates one page at a time

## D-039 "Hubs only" keeps only the area names — active
- Date: 2026-11-15
- By: operator ("only the hubs labels visible, in the bold text ... hide any labels of the topics within that blob unless hovered")
- Intent: the switch keeps the names the person calls hubs: the bold names of the areas
- Decision: with "hubs only" no page is named at rest; the area names stay

## D-040 A focused page's linked names come first — active
- Date: 2026-11-15
- By: operator
- Intent: while a page is focused, its own neighbourhood is what reads
- Decision: the names of the page and its linked pages are placed first; a faded topic or group name they would meet is hidden

## D-041 An area's page count sits beside its name — active
- Date: 2026-11-15
- By: operator
- Intent: an area says how big it is without a second line on its dots
- Decision: the count, small and muted, on the same line as the name, inside the name's room

## D-042 A search highlights, and every dot stays reachable — active
- Date: 2026-11-15
- By: operator ("I'm not able to select any other dots than the searched item"; after leaving every item, "the focused view should go back again on the item in the searchbar until it is cleared")
- Intent: a search never takes the rest of the map away from the pointer
- Decision: what is highlighted and what can be pointed at are two sets; off every dot the focus returns to the search's result until the search is cleared (`graph/searchFocus.ts`, rendered check rule 19)

## D-043 Pointing at a page lays one veil over the map — active
- Date: 2026-11-15
- By: operator
- Intent: the page pointed at and its links stand out from everything else
- Decision: one veil in the stage colour over the whole map, areas and names included; the focus layer draws the page, its linked pages and their lines above it

## D-044 The typing area is its own, bigger area — active
- Date: 2026-11-15
- By: operator ("make the typing area bigger, and make the text input field a more distinct own area")
- Rule: design:every-text-field-is-its-own — follows
- Intent: the box reads as a place to type and has room to write
- Decision: the text has its own well inside the card (sunken fill, strong edge); it starts at four lines and grows to about twelve, then scrolls

## D-045 Every control of the box in one row under the text — active
- Date: 2026-11-15
- By: operator ("move the auto/add/ask buttons into the bottom part as well, so all buttons are in the same row ... and then the paperclip button next to those buttons")
- Intent: the box has one row of controls
- Decision: the mode switch, the shortcut help and the paperclip at the left, Send at the right

## D-046 A citation opens the page or its address — active
- Date: 2026-11-15
- By: operator ("a reference like [1] being clicked should open that topic card or direct link, whichever is most relevant")
- Intent: a citation leads to the most useful view of its source
- Decision: a link page opens its own http(s) address; a page of the active vault opens in the page window

## D-047 Settings shows the version beside its title — active
- Date: 2026-11-15
- By: operator
- Intent: the running version is easy to find
- Decision: the app's version in the top right of the Settings dialog, beside the title

## D-048 The graph search has its own clear button — active
- Date: 2026-11-15
- By: operator (the browser's own "x" only shows while the pointer is over the field)
- Intent: a search can always be cleared in one click
- Decision: a clear button shown whenever the field holds text

## D-049 The map can be grouped by tag — active
- Date: 2026-11-15
- By: operator ("there's a Topics/Sources switch, add tags in there ... select from the available tags")
- Intent: the person can see their own groupings on the map
- Decision: a third grouping, Topics | Sources | Tags: one area per chosen tag, only tagged pages, a page under its rarest shown tag (`graph/tagView.ts`)

## D-050 Zoomed circles stay sharp — active
- Date: 2026-11-15
- By: operator ("while scrolling in on a topic, the circle becomes pixelated")
- Intent: the map looks sharp at every zoom
- Decision: the drawing is redrawn at the zoom it rests at, not scaled up from a smaller one

## D-051 A copied titled link is one link — active
- Date: 2026-11-15
- By: operator (a SharePoint address copied from the browser was filed as "Web page")
- Intent: a link copied from the browser is filed as the link it is
- Decision: a bare address or a single Markdown link "[title](address)" counts as one link and nothing else

## D-052 The meeting probe reads a full day — active
- Date: 2026-11-15
- By: operator ("fetch all meeting notes from a full day ... from multiple meetings")
- Intent: know whether a whole day of meetings can be read, not only one
- Decision: after the list of the last 7 days, P10 asks for every meeting of one day and the notes of several of them

## D-053 One launcher per probe still to run — active
- Date: 2026-11-15
- By: operator ("provide cmd files for them as well")
- Intent: every check on the target machine starts with a double-click
- Decision: a `.cmd` per probe or stage, which runs exactly that one and never writes

## D-054 The OneNote API catalogue lists every method — active
- Date: 2026-11-16
- By: operator
- Intent: one place says what each OneNote API method does and how ObsidiNote uses it
- Decision: FEASIBILITY.md "OneNote's API, every method", mirrored by the catalogue in `validation/lib/ApiProbe.psm1` and kept in step by `tests/OneNoteApi.Tests.ps1`

## D-055 A link page is filed by its address, never as a note — active
- Date: 2026-11-16
- By: operator ("putting items in ObsidiNote notes should be minimized. Web links should be listed as such, and not as notes")
- Intent: a link is always listed as a link
- Decision: a link page without a source goes by its host, then by its link type; never under Notes

## D-056 Pages the person made are listed, never changed — active
- Date: 2026-11-16
- By: operator (Delete was offered on such a page and failed)
- Intent: ObsidiNote never changes what the person wrote in OneNote themselves
- Decision: such pages show without Archive or Delete and with Edit unavailable, with the reason (`graph/readOnly.ts`); the server refuses them as "not a page of this map"

## D-057 No guiding text beside the zoom buttons — active
- Date: 2026-11-16
- By: operator
- Intent: the map's chrome stays quiet
- Decision: no visible help next to the zoom buttons; the map's help stays for screen readers (`aria-describedby`)

## D-058 The page window gives the page itself the room — active
- Date: 2026-11-16
- By: operator ("the left side items should utilize the available space")
- Rule: ui:long-lists-and-menus-scroll-inside — deviates
- Intent: what is read (summary, tags, page text) gets the most room
- Decision: a bigger window when the screen has room (still 16px from each side of a small one); the page column 65% and the links 35%; its text fills the column with no 70-character measure; the tag field takes the rest of its row

## D-059 The meeting probe can ask for today — active
- Date: 2026-11-16
- By: operator (a Microsoft 365 outage left the busiest day of the week without meetings)
- Intent: the probe can be pointed at a day that surely has meetings
- Decision: `-MeetingDay today` takes this computer's date

## D-060 The journal is one page per day — active
- Date: 2026-11-17
- By: operator ("one page per day"; feature list items 4, 6 and 7: "build 3 and 4 first ... then 6 and 7")
- Intent: a day's journal entries are read together, and the journal can be searched by topic
- Decision: a journal Add goes into the day page "yyyy-MM-dd" in Journal/<year> as one entry (`lib/Journal.psm1`, `obsn.entries`); the Journal view lists the days and searches a topic across everything, with its decisions

## D-061 Meeting pages show in the Journal on the day they were added — active
- Date: 2026-11-17
- By: operator ("the meetings are imported, they are by default not visible under journal")
- Intent: imported meetings are part of the journal
- Decision: meeting pages are listed on the day they were added, without a time

## D-062 Web links open in the default browser — active
- Date: 2026-11-17
- By: operator
- Intent: a web link opens where the person browses, not in ObsidiNote's own Edge window
- Decision: every web link is `components/WebLink`: a real link whose plain click asks the server (`POST /api/open`, http(s) only) to have Windows open it; the window opens it itself when the server cannot

## D-063 Possible duplicates are shown, not silently refused — active
- Date: 2026-11-17
- By: operator (feature list item 6, with D-060 and D-062)
- Intent: the person decides about a possible duplicate
- Decision: Add's duplicate refusal names the existing page (`duplicateOf`) with "Open it" and "Add anyway"; the map's Filter has "Possible duplicates"

## D-064 Today's meetings — active
- Date: 2026-11-17
- By: operator ("build as suggested", after kit P10 on the target machine)
- Intent: the day's meetings come into the wiki with a tick each
- Decision: the home page's "Today's meetings": Copilot lists the day's Teams meetings (each question in a new chat with Work IQ on, as P10), the person ticks some, each becomes a meeting page through the normal Add (`lib/Meetings.psm1`, `src/meetings/`)

## D-065 Ask answers only from the pages it sends — active
- Date: 2026-11-17
- By: operator ("it only fetches information from those daily meetings, and not other sources")
- Intent: an Ask answer comes from the wiki, not from the person's mail, chats or files
- Decision: every Ask chat switches Work IQ off (`Start-AskChat`); Today's meetings switches it on for its own questions

## D-066 A company link with your own words becomes its link page — active
- Date: 2026-11-17
- By: operator ("for SharePoint sites, I also want to fetch a Copilot summary of the content of that page; right now only my own notes are added")
- Intent: a pasted company link is summarized like any link, and the person's words around it are kept
- Decision: one internal http(s) address with other words (`Get-LinkWithNotes`): the link Add, with the words in the new page's "Your notes"

## D-067 One launcher for the checks still open — active
- Date: 2026-11-17
- By: operator ("if there are items still to be confirmed then create a new scoped cmd for them")
- Intent: what a kit run left open is run again in one go
- Decision: `Run Open Checks.cmd`: only the open checks, asking nothing; the one probe launcher that writes, only into the test notebooks

## D-068 A daily meeting is one series of pages — active
- Date: 2026-11-18
- By: operator ("implement both a and b"; fetched several times a day, a meeting is merged, never duplicated)
- Intent: the occurrences of one meeting are kept together and never doubled
- Decision: `obsn.series` and `obsn.meetingAt` written by ObsidiNote, never Copilot, from the meeting text; one page per occurrence (same series, day and time) updated in place; each links the previous one; two meetings of a series on one day stay two pages

## D-069 Ask within one meeting series — active
- Date: 2026-11-18
- By: operator ("it only fetches information from those daily meetings, and not other sources")
- Intent: a question about a series is answered from that series only
- Decision: Ask with `series` reads the active vault's meeting pages of that series, newest first, and nothing else; no topic step

## D-070 Attendees are the people who joined, with name and address — active
- Date: 2026-11-18
- By: operator ("previously it captured everyone who joined, now it lists all of the invitees"; "store the display name as well as the e-mail address")
- Intent: a meeting page names who was there and how to reach them
- Decision: the prompt asks only for the people who joined, with the address as the invitation has it; one person per address; a name alone stays a name

## D-071 Copilot's yes is read leniently — active
- Date: 2026-11-18
- By: operator (a transcribed meeting was listed as having nothing to read)
- Intent: a meeting with notes is never shown as having none because of how Copilot spelled yes
- Decision: true, "yes", "available" and 1 all mean yes

## D-072 A meeting page's icon is two people — active
- Date: 2026-11-18
- By: operator
- Intent: a meeting is never read as the Journal
- Decision: the `meeting` icon shows two people, not a calendar

## D-073 One overview page per series — active
- Date: 2026-11-19
- By: operator ("create b, and yes a summary"; "the same meeting but many occurrences")
- Intent: a series can be read as a whole
- Decision: a series page "<series> (series)" written after each import of the series: Copilot's summary of the latest meetings (kept when unanswered), the latest meeting, decisions and actions by date, links to every meeting

## D-074 One topic per series — active
- Date: 2026-11-19
- By: operator
- Intent: all meetings of a series sit in the same place on the map
- Decision: every meeting of a series and the series page carry the series page's topics, whatever Copilot proposed

## D-075 Duplicate meetings of a series are merged — active
- Date: 2026-11-19
- By: operator ("merge existing items if they are from the same meeting series")
- Intent: copies of one occurrence made by different versions or imports become one page
- Decision: upgrade step `meeting-join` first, then "Merge duplicates (n)" on the series page, which always asks first; the kept copy takes the other's notes and links, the other goes to the Archive

## D-076 No real names of people or companies — active
- Date: 2026-11-19
- By: operator ("make sure that no existing names of people or companies are being used")
- Rule: testing:fixtures-are-recorded-or-synthetic-and — follows
- Intent: the public repo holds no name from the operator's data, and no real company, product brand or book
- Decision: invented names in tests, examples and screenshot data; real names seen in the data go into the gitignored `tasks/private-names.txt`, which `tests/NoReferenceName.Tests.ps1` reads

## D-077 A series is one dot on the map — active
- Date: 2026-11-20
- By: operator ("I want a series to show up as one dot instead of each meeting in a series to have its own dot")
- Intent: a series reads as one thing on the map, not as meetings told apart by date
- Decision: always on: the map draws a copy folded by `seriesKey` (the series page, else the newest meeting, with the meeting count); a one-meeting series is a dot too; the List, search and page window keep every meeting

## D-078 Meetings of other days are fetched from the box — active
- Date: 2026-11-20
- By: operator ("through the input field, fetch meetings from other days ... or from multiple days, for example for a daily meeting all occurrences for that series within a given week")
- Intent: any day's meetings, or a series' meetings over a week, can be fetched with a short sentence
- Decision: `lib/MeetingRequest.psm1` (EN and NL) reads days and a series; `Get-Intent` rule 5 answers intent `meetings`; the panel asks one day at a time, oldest first; weeks are Monday to Friday, at most 14 days

## D-079 Fetch, Get or Import also start a meetings command — active
- Date: 2026-11-20
- By: operator ("also on Fetch, Get or Import")
- Intent: the natural verbs work without the word "meetings"
- Decision: a verb at the start plus a time of past days; the rest must read as a meeting title, so a note such as "Get milk tomorrow" stays a note

## D-080 A named series without a time takes the past 7 workdays — active
- Date: 2026-11-20
- By: operator (a series fetched on a day it does not meet came back empty)
- Intent: naming a series without a day still finds its meetings
- Decision: a named series without a time takes its meetings of the past 7 days (workdays); no series and no time is today

## D-081 Meetings the person was invited to and did not join are listed too — active
- Date: 2026-11-20
- By: operator ("I didn't join, but because I was invited I do have access to the transcript and Copilot summary")
- Intent: every meeting whose notes the person can read can be fetched
- Decision: the day prompt also asks for meetings invited to but not joined (`joined` flag, "you did not join" in the list); the notes prompt says the person may not have joined

## D-082 No ESLint: the dependency-free code-size reader — active
- Date: 2026-11-24
- By: operator
- Intent: the code-size ratchet runs without installing a linter
- Decision: `ui-src/scripts/check-code-size.mjs` measures with `code-size-reader.mjs`, copied unedited from CommonShared; fixes go there, never into the copy

## D-083 A busy button keeps its width — active
- Date: 2026-11-24
- By: operator
- Rule: ui:loading-14-16px-spinner-role-status — follows
- Intent: nothing moves when a button starts or stops working
- Decision: `<BusyLabel />`: the label and "ring + busy text" share one grid cell, so the button is as wide as the wider of the two; `aria-busy` and unavailable while busy; the side bar's Copilot retry turns its icon instead

## D-084 An error already there is a status, a new one an alert — active
- Date: 2026-11-24
- By: operator
- Rule: ui:generated-controls-get-names-with-row — deviates
- Intent: a screen reader announces an error when it appears, and reads one that was already there with the view
- Decision: an error box present when a view opens is `role="status"`; one that appears later is `role="alert"` (`components/Notice.tsx`, `ViewOpening`)

## D-085 A filtered List that is empty says why — active
- Date: 2026-11-24
- By: operator
- Intent: an empty List never looks like an empty vault
- Decision: the one row names what narrows it (the search, the focus on a page, the filters) and offers "Clear filters"

## D-086 One icon set, one component — active
- Date: 2026-11-24
- By: operator (inline icons had drifted to three stroke widths)
- Rule: design:no-emoji-or-mixed-icon-styles — follows
- Intent: every icon has the same look
- Decision: `<Icon name="..." />` from `components/icons.tsx` only: outline on a 16 px grid, 1.5 px round stroke, `currentColor`, decorative; a new icon is added there, never drawn inline

## D-087 Tag chips are 24px — active
- Date: 2026-11-24
- By: operator (it was 26)
- Rule: el-badge:height-18-20px-for-counts-and — follows
- Intent: a tag chip has the shared chip size
- Decision: 24px outside, border included

## D-088 The Edit form's "Why" field has a hidden label — active
- Date: 2026-11-24
- By: operator
- Rule: el-text-field:visible-label-for-above-11-12px — deviates
- Intent: each link's reason field is named for a screen reader without a label line per row
- Decision: a real `<label>`, visually hidden; the placeholder "Why" is what shows

## D-089 Backspace never removes a tag — active
- Date: 2026-11-24
- By: operator (DESIGN.md accepted deviations)
- Rule: el-tag-input:enter-or-comma-adds-the-trimmed — deviates
- Intent: a key pressed to correct a typo never takes a tag off
- Decision: removing a tag writes to OneNote at once, with no undo in the field, so only each tag's own remove button removes it

## D-090 The graph's title spans the full width — active
- Date: 2026-11-24
- By: operator (DESIGN.md accepted deviations)
- Intent: the map uses the window's width
- Decision: the knowledge graph's title starts at the left of the full-width view, not on the 880 px column of Add or ask and History

## D-091 The Add or ask box is labelled by its heading — active
- Date: 2026-11-24
- By: operator (DESIGN.md accepted deviations)
- Rule: el-text-field:visible-label-for-above-11-12px — deviates
- Intent: the box stays on the first screen at 720 and 390 px, with no label that repeats the heading
- Decision: the view's `h1` names the box (`aria-labelledby`); the placeholder says what may go in

## D-092 Spacing tokens stay px — active
- Date: 2026-11-24
- By: operator (DESIGN.md accepted deviations)
- Rule: ui:spacing-on-4px-steps-2-4 — deviates
- Intent: the 4 px grid holds; the reader's zoom is carried by the text sizes
- Decision: `--space-*` in px, because the root font size is 13 px and rem steps would shrink every space by a fifth

## D-093 The theme is a segmented control — active
- Date: 2026-11-24
- By: operator (DESIGN.md accepted deviations)
- Rule: el-theme-toggle:a-square-icon-button-in-the — deviates
- Intent: System stays a choice, and either/or keeps one look (One Look Per Choice)
- Decision: System / Light / Dark as the `.seg` in the side bar's footer; the app has no header bar

## D-094 The small dialogs close from their footer — active
- Date: 2026-11-24
- By: operator (DESIGN.md accepted deviations)
- Rule: el-dialog:title-18-20px-600-in-a — deviates
- Intent: a short confirm or form has one way out where its actions are
- Decision: no Close button in the header of the small dialogs (new vault, set up, Settings, Archive/Delete/Merge); Cancel in the footer and Esc close them; the page window keeps its own Close

## D-095 Dialog widths stay as they are — active
- Date: 2026-11-24
- By: operator (DESIGN.md accepted deviations)
- Rule: el-dialog:width-min-680px-100vw-32px-centred — deviates
- Intent: each dialog is as wide as its content needs
- Decision: the form dialogs about 560 px, the page window wider for its columns; vertically centred

## D-096 Map options stay in the map's header — active
- Date: 2026-11-24
- By: operator (DESIGN.md accepted deviations)
- Rule: design:a-bar-holds-actions-and-navigation — deviates
- Intent: what the areas are is switched often and in one move; Filter is for hiding pages
- Decision: "Group the map by" (Topics / Sources / Tags) and the Tags bar sit in the graph's header

## D-097 Loading is a status line — active
- Date: 2026-11-24
- By: operator (DESIGN.md accepted deviations; the map's no-placeholder decision of 2026-11-13)
- Rule: el-spinner:spinner-for-a-control-or-an — deviates
- Intent: a loading state never promises a layout the content may not have
- Decision: cards and lists (recent pages, History, the map and List) show one status line while they load, no skeletons

## D-098 Tags on the map have one way — active
- Date: 2026-11-15
- By: operator (design round 2, "Plan all 8", item A)
- Rule: design:one-way-per-question-a-second — follows
- Intent: tagged pages are seen on the map in one way, and each still shows what it is about
- Decision: the Tags grouping only; the tag picker and the dashed lines that joined tagged pages are gone; inside a tag area the pages of one topic lie together under that topic's name (`graph/tagView.ts`, `layout.ts` `groupLabels`)

## D-099 What the map shows is chosen in the Filter — active
- Date: 2026-11-15
- By: operator (design round 2, "Plan all 8", item B)
- Rule: design:a-bar-holds-actions-and-navigation — follows
- Intent: the bar above the map stays short and holds what is used to move around
- Decision: links, mentions and "Labels: hubs only" sit in the Filter panel under "Show on the map"; the bar keeps the grouping, Filter, search and Graph/List (the grouping itself stays there, D-096)

## D-100 The page window shows the page's text — active
- Date: 2026-11-15
- By: operator (design round 2, "Plan all 8", item C)
- Intent: a page can be read in ObsidiNote without opening OneNote
- Decision: the page window shows the page's text, read only, from `GET /api/page/body` (the export's converter, in memory, cut at 20,000 characters); "Open in OneNote" stays the way to change the text

## D-101 Title and summary are changed where they stand — active
- Date: 2026-11-15
- By: operator (design round 2, "Plan all 8", item D; "How can I edit a card like this one, for example if I'd like to adjust the title")
- Intent: a small correction of a page needs no form
- Decision: the title and the summary in the page window are buttons that turn into a field (`graph/InlineText.tsx`); Enter saves through `POST /api/page/edit`, Esc puts the text back; the Edit form keeps the other fields

## D-102 One banner says why the window cannot write — active
- Date: 2026-11-15
- By: operator (design round 2, "Plan all 8", item E; pages of the main vault showed "read only" with no reason)
- Rule: design:a-state-is-explained-once-in — follows
- Intent: when pages cannot be changed, the person reads why, once, and what to do
- Decision: `components/ReadOnlyBanner` is the one place: the app shell's banner from `model/attention.ts` `vaultNote`, the graph's for its source from `graph/readOnly.ts`; no side bar note or badges

## D-103 A choice that is on is neutral — active
- Date: 2026-11-15
- By: operator (design round 2, "Plan all 8", item F)
- Intent: purple on a screen always points at the next action
- Decision: a pressed toggle, chosen segment, current menu item, selected row, tab or tick box takes the neutral `--pressed` fill; the accent only for the primary action, focus and the focused page on the map (DESIGN.md "One Purple")

## D-104 After a send the home view shows the result alone — active
- Date: 2026-11-15
- By: operator (design round 2, "Plan all 8", item G)
- Intent: the result of what was just sent is what reads
- Decision: after a send only the result shows; "Waiting for Copilot" and "Recently changed" show while nothing was sent, and in History

## D-105 Every Add prompt carries a request reference — active
- Date: 2026-11-13
- By: operator
- Intent: an answer is never filed for a request it does not belong to
- Decision: each Add prompt (classify/link, link summary) carries `ref` (`New-RequestRef`, no content) and asks Copilot to repeat it, the link summary also the link as `source`; a live answer with another `ref` is refused, an answer read later from the chat is used only when its `ref` (and, for a link, `source`) is the Intake item's

## D-106 Add never stops a slow answer — active
- Date: 2026-11-13
- By: operator (a SharePoint link came back "NoAnswer"; "about 2 minutes" is how long the window stays busy)
- Intent: a slow Copilot answer is never lost, and the window is not blocked for long
- Decision: Add waits 2 minutes and never presses Stop (`-LeaveRunning`); then its Intake item waits with "Check for the answer", nothing else written; a slow link Update waits the same way as an "Update: ..." item

## D-107 OneNote is the only store — active
- Date: 2026-11-12
- By: operator
- Intent: the person's content lives in one place they own, never in files on this computer
- Decision: content, the index, the Intake and state live in the ObsidiNote notebook; no index, cache or temp files with page text; logs hold ids, counts and timings; one writer by a lease Meta on the state page, not a lock file; enforced by `tests/NoContentOnDisk.Tests.ps1`

## D-108 Export as Markdown is the one way content leaves OneNote — active
- Date: 2026-11-13
- By: operator
- Intent: the person can take their pages with them without ObsidiNote keeping a copy
- Decision: a download the person asks for (one page `.md`, a topic or everything `.zip` with `[[wikilinks]]`), built in memory (`lib/MarkdownExport.psm1`, `New-ZipBytes` on a MemoryStream) and sent to the browser; read only, no temp file, the log gets counts only

## D-109 The notebook structure is fixed — active
- Date: 2026-11-12
- By: operator (2026-11-12; the request section renamed `01 Intake` on 2026-11-13)
- Intent: every page has one predictable place, and topics never become folders
- Decision: sections `00 Index`, `01 Intake`, then one bucket per page type (`Notes` ... `Archive`); a page's section is its type from a fixed list; topics only in the index; at most 500 pages a section (rollover `<Bucket> 2`); an old root-level `01 Inbox` is renamed once; sections and pages the person made are listed, never edited

## D-110 Archive by default, delete only through Deleted Pages, both asked — active
- Date: 2026-11-12
- By: operator
- Intent: nothing is lost by one click, and what is removed can still be brought back
- Decision: archive is the default and reversible (`Archive / <bucket>`, Restore); Archive and Delete always ask first, with no "don't ask again"; delete covers only ObsidiNote's own pages, through OneNote's Deleted Pages (60 days), and turns links to the page into "(deleted: title)"; never a permanent or automatic delete

## D-111 A pasted link becomes one summary page — active
- Date: 2026-11-12
- By: operator
- Intent: a link is kept as what it says, without copying the source
- Decision: one page per normalized address (updated, never doubled) with a summary, key facts and the link, never the full text; Copilot reads the source; Update re-reads it, keeps the last 3 summaries and never touches "Your notes"

## D-112 Internal or web by fixed host rules — active
- Date: 2026-11-13
- By: operator ("Workday where a timesheet can be hosted, or internal vacancies are published")
- Intent: company data is filed as internal wherever it is hosted, the same way every time
- Decision: `Get-LinkBucket` decides by the host, no model: Microsoft 365, `internalHosts`, a company's SaaS tenant and the company's name in another domain's subdomain are Internal links; public job boards and hosting, the company's own public site and the rest are Web links

## D-113 Every page is listed in the central index — active
- Date: 2026-11-12
- By: operator
- Intent: no page is ever out of reach of the index, also one typed in OneNote
- Decision: every page id is in its topic hubs or Unfiled, in By type and in A-Z; at every start and after every write the hierarchy is compared with the index and a missing page goes to Unfiled; `00 Index` and the Intake requests are not listed

## D-114 Every dot is content — active
- Date: 2026-11-12
- By: operator ("other than actual content there shouldn't be any other visual dots")
- Intent: everything drawn on the map stands for something real
- Decision: each dot is a note, file or link and each grey area a topic with its name and count; no decorative dots, specks, particles or background patterns (DESIGN.md "Every Dot Is Content")

## D-115 A Copilot sign-in may take 10 minutes — active
- Date: 2026-11-13
- By: operator (5 minutes was too short for a slow tenant sign-in)
- Intent: a slow sign-in at start is not cut off
- Decision: `Connect-Copilot` waits up to 600 s for a sign-in at start; the side bar's refresh waits 15 s

## D-116 Markdown becomes OneNote formatting — active
- Date: 2026-11-13
- By: operator (OneNote has no Markdown)
- Intent: text written or pasted in Markdown reads as formatted text in OneNote
- Decision: headings, lists, emphasis, links, code and tables become real OneNote formatting (`lib/MarkdownLines.psm1`, `ConvertTo-BodyLines`); other text stays one plain line per line

## D-117 An empty notebook can be set up as a vault in place — active
- Date: 2026-11-13
- By: operator
- Intent: a notebook made for ObsidiNote can be used as it is
- Decision: an open notebook with no pages, no section groups and no vault can be set up as a vault ("Set up ObsidiNote in this notebook", `POST /api/vault/setup`); it always asks first, since ObsidiNote does not own it yet

## D-118 The Copilot note has a refresh button — active
- Date: 2026-11-14
- By: operator
- Intent: Copilot can be connected again without a restart
- Decision: the side bar's "Copilot is not connected" note has a refresh button: one try (`POST /api/copilot/reconnect`, 15 s sign-in wait) that says what came of it

## D-119 No focus ring around the Add box — active
- Date: 2026-11-13
- By: operator ("do not show the outline on the textbox whenever it is selected")
- Rule: ui:one-global-focus-visible-2px-solid — deviates
- Intent: the page's one input looks calm while it is typed in, and its focus still shows
- Decision: no outline on the box's text; focus shows as the well's fill and stronger edge, the card's border (`:focus-within`) and the caret

## D-120 The side bar's buttons look alike — active
- Date: 2026-11-13
- By: operator
- Rule: ui:one-height-per-bar-and-per — follows
- Intent: the side bar reads as one set of controls
- Decision: the switcher's full width, one height, one line and the same secondary style for every side bar button; the box's Send stays the one primary

## D-121 Citation markers sit on the text line — active
- Date: 2026-11-13
- By: operator
- Intent: a citation in an answer reads as part of its sentence
- Decision: the markers are not raised like a superscript; they sit on the text line

## D-122 A page window opened by a click leaves no card behind — active
- Date: 2026-11-13
- By: operator (a card stayed after the window closed and no click closed it)
- Intent: closing the page window returns to a calm map, whatever opened it
- Decision: opened with a click, closing leaves no page focused and no preview card; opened with the keyboard, the focus goes back to the map

## D-123 A type of another section moves the page — active
- Date: 2026-11-15
- By: operator
- Intent: changing a page's type also puts it where pages of that type live
- Decision: Edit's type, saved, moves the page to that type's section (`Edit-Page`, store `MovePage`); a link page's type follows its address, and an archived page stays in the Archive until Restore

## D-124 A number setting outside its range moves to its nearest end — active
- Date: 2026-11-14
- By: operator ("mentions 1 to 10 but the setting is 12")
- Intent: a setting never shows a value it will not use
- Decision: when the field is left, a number outside its range becomes the nearest end of the range (`settleNumber` in `model/vaultSettings.ts`)

## Records, not decisions
- `docs/STATUS.md` — build and probe history: when work was asked for, built and verified

# Changelog

All notable changes to ObsidiNote. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
versions follow [SemVer](https://semver.org/).

## [Unreleased]

## [v0.10.1] - 2026-11-15

### Changed
- A citation number in an Ask answer opens the page itself: a page of your vault in its page window, a link page at its own address, a page of another notebook in OneNote. It used to jump to the list of sources.
- The typing area of the Add or ask box is bigger (four lines to start, up to about twelve as you type) and has its own field inside the box, so it stands out from the controls.
- The Add or ask box has all its controls in one row under the text: Auto / Add / Ask, the shortcuts, a paperclip for **Add a file**, and Send. What the text will do stays on its own line above them.

### Fixed
- The Ask answer uses the full width of its box, like the sources under it, instead of a narrow column on a wide screen.
- The interface's speed tests no longer fail on a slow build machine: they compare how the work grows from 500 to 5,000 pages instead of holding a time limit (the v0.10.0 release build failed on three of them; the release itself was not affected).

## [v0.10.0] - 2026-11-15

### Added
- The page window shows the page's own text (headings, lists, tables, links; a link to another page opens that page). It is read from OneNote when the window opens and never stored; a long page is shown up to 20,000 characters, with a note to open OneNote for the rest. Text is still changed in OneNote.
- The title and the summary of a page can be changed where they stand in the page window: click the text, type, **Enter** saves, **Esc** puts the old text back. The Edit form stays for type, topics, aliases, address and links.

### Changed
- Tags on the map work one way: the **Tags** view of the Topics / Sources / Tags switch. Inside a tag's area the pages of one topic sit together under that topic's name, so you see which topics a tag connects. A tag in the page window or in the List opens that view with the tag alone. The tag picker above the map and its dashed joining lines are gone.
- The bar above the map is shorter: grouping, Filter, search and Graph/List. **Links**, **Mentions, not linked** and **Labels: hubs only** are now in the Filter panel under "Show on the map".
- Why a vault or notebook is read only is said in one place, a banner above the content, with **Check again** where waiting helps. The note in the side bar and the "read only" badges are gone; the page window keeps the line under its disabled Edit.
- Purple now only means "do this" (the main button), keyboard focus, and the page you are on in the map. A choice that is on (a pressed switch, the chosen segment, the current menu item, a selected row or tab, a ticked box) is neutral.
- The README is written for installing and using ObsidiNote, with screenshots of the current window.
- After a send, the home view shows the result alone; "Waiting for Copilot" and "Recently changed" show while nothing was sent, and in History.

### Fixed
- Pages of your vault no longer show as "read only" when another notebook is the selected one in OneNote: ObsidiNote keeps the vault it opened as the active vault, and at start it selects the vault's notebook in OneNote once when its pages cannot be read otherwise. No upgrade step is needed: nothing stored changes. The validation kit (stage V6, runbook RB-05 step 3a) records what OneNote returns for each open notebook, selected or not.

## [v0.9.0] - 2026-11-15

### Added
- Validation kit, stage V5: probe P10 checks whether Copilot can list your recent Teams meetings and turn one with a transcript, recap or notes into structured meeting notes (attendees, decisions, actions with owner and due date). Read only; the log holds counts only. It decides whether ObsidiNote gets an "Add a meeting" step (runbook RB-04). Double-click **Run Meeting Probe.cmd** in the `validation` folder to run only this probe (`-Probe P10`).
- **Tags**, set by hand, to group pages that nothing else relates. Add or remove them in the page window, or tick several rows in the List and tag them together; existing tags are offered while you type. The map's Topics/Sources switch has a third choice, **Tags**: one area per tag, holding only the tagged pages, with a chip per tag to choose which tags are shown. In the Topics and Sources views, pick a tag above the map and its pages light up wherever they are, joined into one group by thin dashed lines; `tag:name` works in the search and in Ctrl+K, and the Filter panel has a Tag group. Rename a tag, merge two, or take one off every page under Settings. Copilot never sets or changes tags. Up to 12 per page; they are kept on the page in OneNote and in the index and go into the Markdown export. Existing pages need no change (a page without tags has none, so there is no upgrade step).

### Changed
- A new start of ObsidiNote replaces one that is still running on this PC, and takes over the vault at once when the earlier run on this PC did not give it back. The earlier one is asked to stop and hands the vault over; if it does not, it is closed. After a PC was switched off mid-run, the next start on that PC can write straight away instead of waiting up to two minutes. A vault that an ObsidiNote on another PC is writing in is never taken.
- A page that cannot be changed says why: the side bar and the page window name the reason (another PC is writing since a given time, an earlier run on this PC, not the active vault, a connected notebook), and **Edit** shows disabled with that reason instead of being absent.
- A most linked page is called that ("most linked"), no longer "hub": "hub" only means an area of the map.
- In a narrow window (half a screen, or a phone) the side bar is now a short bar at the top: name and theme, the menu, the notebook, and the section list behind **Show**. The Add box is on the first screen again.
- Ask shows the answer first, in larger text, with **Ask a follow-up**, **Save answer as a page** and **Show on map** right under it. The sources follow; how the answer was found is one folded line at the end.
- The Add result shows **Done**, **Update** and **Undo** right under its heading, and one card with where the page was filed and what you added. Links show the three strongest, with **Show all** for the rest. **Undo** asks first, as in History.
- While Copilot works, Add and Ask show one line with the time waited instead of steps that never moved.
- Messages about something that went wrong look like it (a warning icon, a tinted box) and say what to do next: **Try again** after an Ask that failed, **Connect Copilot again** when Copilot was the reason. When Copilot is not connected or ObsidiNote is not running, the box itself says so.
- A section in the side bar opens the List with that section's pages.
- In the page window a linked page opens by clicking its name or its line (the small "open" link is gone); **Export as Markdown** and **Focus on this page** sit apart on the right.
- On the map a topic name no longer lies on its own pages: the dots keep clear of it. The line with the page count and subjects is no longer drawn on the map (it is in the List and in the page window's Topic tab).
- Topics/Sources and Graph/List look like the Auto/Add/Ask switch; Links, Mentions and Labels show a check box, so a choice between two and an on/off switch no longer look the same.
- The List names page types as the rest of the window does ("web link", not "link-web").
- Links to your personal OneDrive are filed under Internal links, the same place the Sources view shows them. Pages filed under Web links before are moved at the next start (upgrade step link-bucket).
- In the Sources view, "Other company sites" is its own kind of area.
- After an Add, **Done**, **Update** and **Undo** are plain buttons: **Send** stays the one highlighted button of the page.
- The search on the knowledge graph shows its "x" whenever it holds text, not only while the pointer is over it.
- **Labels: hubs only** on the map now does what it says: only the bold topic names stay, and a page shows its name while you point at it. Before, it also kept the names of the most linked pages.
- The shortcut card of the box lists Ctrl+K (find a page or topic).

### Fixed
- Undo now also tidies the text of pages that linked to the removed page: where the link was, the page says "(deleted: title)". Your own notes on a page are never changed.
- Settings: when the settings stored in a vault cannot be read, the Settings window says so and does not offer to save, instead of failing on Save.
- A request that is not a proper form (a bare number, text or list) is refused instead of being half-accepted.
- Undo, Remove and "Check for the answer" in History are refused when the item belongs to another vault than the one that is open, instead of being applied to the wrong vault. History also empties at once when you switch vault.
- Undo from History now also takes out the links other pages had to the removed page, so the map no longer shows a line to a page that is gone. (A link in another page's own text still points at the removed page.)
- When the settings stored in a vault cannot be read, ObsidiNote leaves them exactly as they are, says so at the start and uses the defaults for that session; it no longer writes the defaults over them.
- A file dropped from a synchronised SharePoint library whose name contains a space or an accented letter now gets a working address.
- Editing the text of a dropped OneDrive or SharePoint file no longer drops its link without a word; the link is kept while the box still holds that file's text, and the box says so when it is not.
- A file let go beside the box no longer makes the window open that file in place of ObsidiNote.
- A file lookup that answers after the box was sent or emptied no longer writes its note over the box.
- "Try again" after a failed follow-up question repeats that follow-up, in the same conversation.
- A section in the side bar opens its own pages: sections in a group (Journal by year) and second sections ("Notes 2") opened an empty list.
- The "From" choice survives an edit of the pasted text's first line, and comes back with the text after an undo.
- "Waiting for Copilot" is read again after "Check for the answer" and after an Update that has to wait.
- When Copilot is reported off, the box keeps its reading of your text and the "Add instead / Ask instead" link beside the warning.
- On a map of a few hundred pages or more, a topic name no longer lies on its own pages (the room kept for it follows the zoom the map is fitted to).
- The "Link steps" choice of a focused page looks like the other either/or controls again.
- The History list and removing an Intake item read only the Intake section, not the whole vault, so they are quicker in a large vault.
- The upgrade's status line at the start counts the pages that were really changed.
- The map of another vault or a connected notebook groups its link pages by that vault's own internal sites and company name, not the active vault's.
- A question is never refused because of the "From" choice.
- Validation kit: a meeting without a title no longer stops the meetings probe; a mistyped `-Probe` name gives a line that lists the probes.
- A link copied from the browser and pasted in the box is taken as a link again. Edge's "Copy link" pastes a titled link ("[title](address)"), which was read as "a link and other text": it was not added as that address's link page, and "From" said "Web page" for a SharePoint address.
- Zooming in on the map with the wheel keeps the circles and names sharp while you scroll; they used to turn to coarse pixels until the wheel rested.
- The knowledge graph no longer makes the whole page scroll by a few pixels.
- The page no longer shifts sideways when it becomes long enough to scroll.
- On a touch screen every control is at least 44 px high (the menu, tabs, the mode and theme switches, the search box and the List's headers were smaller).
- "Waiting for Copilot" is no longer written in the accent colour, and a list of waiting items no longer shows a row of purple buttons.
- On a phone, tapping a field no longer zooms the page: fields are 16 px on a touch screen (the rule for it was written in a place where it never applied).
- A failed connection to ObsidiNote reads "ObsidiNote did not answer..." instead of the browser's "Failed to fetch".

## [v0.8.4] - 2026-11-14

### Added
- Add a file: drop a file on the box, or press **Add a file**. Its text is read in the window, in memory (Word, PowerPoint, Excel, PDF with text, Outlook .msg, .eml, text and web pages; up to 10 MB, 60,000 characters), put in the box to check, and added like pasted text with "From: File you dropped". The file itself is not stored. Scanned PDFs, images and old .doc/.xls files get a message saying what to do instead.
- A dropped file that is in your OneDrive or SharePoint (a folder OneDrive syncs on this PC) keeps its link: the page becomes that file's link page (under Internal links, and under its OneDrive or SharePoint site in Sources), summarized from the text read in the window; dropping it again updates that page. ObsidiNote finds the file by name, size and date only. A link dragged in from a browser tab is added like a pasted link.
- Ask shows what an answer was made from: "Combined from 5 pages in 3 topics" above it; per source a bar with its share of the answer ("50% of the answer, 2 sentences"; a sentence citing two pages counts half for each; pointing at a source turns its bar and the sentences that came from it purple); and **Also read, not used** for pages it read that the answer does not cite.
- **Waiting for Copilot** on the home page: every item still waiting for Copilot, how long it has waited, **Check for the answer** and **Remove**, so it is not lost once its result is gone.
- **History** lists what Add and link Update did in your vault (added, updated, waiting, not added, undone), newest first, read from the vault's Intake; **Open** shows the page, **Undo** and **Remove** ask first and send the page to OneNote's Deleted Pages.
- **Settings** in the side bar's menu, kept in the vault in OneNote so every PC that opens it uses the same: company addresses that count as internal links, after how many days Ask offers Update for a link page (was fixed at 90), how many related pages Add links a new page to (was fixed at 3), whether Ask includes archived pages, and how the knowledge graph opens (Topics or Sources, "Labels: hubs only", archived pages shown). Topics/Sources and "Labels: hubs only" are also saved when you change them on the map. At every start ObsidiNote adds any missing setting with its default and never sets an existing one back. A read-only window shows them without changing them. The theme stays per PC.

### Changed
- Ask reads up to 20 pages for an answer (was 8), from more topics when needed; **Settings** sets it from 1 to 50. With more pages each page is read more briefly (at 50 about 1,500 characters each), so the request to Copilot keeps its size.
- `"internalHosts"` in `config\obsidinote.local.json` is copied into the vault once, at the first start of this version, when the vault has no list yet; after that, change it under **Settings**.
- The Add or ask box: Auto / Add / Ask sit on the left with the shortcut help next to them; the box starts at two lines and grows with its text up to six; "Ask reads" shows only when the text will be asked.
- Recently changed: a title opens the page window (summary, links, Edit, Export), with **OneNote** next to it; each row shows the page type and section. It lists your pages only: the vault's generated Index pages and Intake requests, which every start rewrites, filled the list before.
- Side bar: the menu (Add or ask, Knowledge graph, History, Settings) is at the top, under the name; the notebook switcher comes after it.
- Export as Markdown is no longer in the side bar: export a page from its window (**Export as Markdown**), a topic from the page window's Topic tab or from List.

### Fixed
- Add: the **From** choice (Outlook mail, Teams chat, ...) is now really sent with the Add; since v0.8.2 the window left it out, so every page was stored as typed in ObsidiNote. Pages added since then can be corrected with **Edit**.

## [v0.8.3] - 2026-11-14

### Fixed
- Knowledge graph, Sources: company sites that ObsidiNote files under Internal links (your `internalHosts`, the company's name on another host, company tenants) now show as company sites, no longer as public web sites; small ones together as "Other company sites". Derived at load, so existing pages follow without an upgrade step.
- Knowledge graph: a topic name wider than its area is shortened with "…" so it no longer covers the neighbouring areas; on a very small area the name is left out when even a short one would.
- Knowledge graph: placing the areas is faster on large maps (about 4 times on 200 areas).
- Add: "From" now resets when the pasted text is replaced (select all and type over) or when "Save answer" fills the box, so a saved answer is no longer filed as "Teams" or "Outlook".
- Add: an unknown "From" value is refused with a message, as in Edit; an empty one counts as typed.
- Start: the "Link it" upgrade also repairs the index when only the index still had the old strength, so it no longer comes back at every start; the status line counts pages, not steps.

## [v0.8.2] - 2026-11-14

### Added
- **Topics | Sources** on the knowledge graph: switch the map from topic areas to where your pages come from. Each SharePoint site, OneDrive, Teams, Loop, each company service (ServiceNow, Workday, ...) and each web site gets its own area; web sites with one or two pages share "Other web sites", and pages you typed or pasted are in "ObsidiNote notes". Links between sources show as lines, like between topics. The page window, filters and List keep the topics.
- **From** under the box: when you paste text, ObsidiNote recognises where it came from (Outlook mail, Teams chat, Word document, a web page) and files the page with it, so it lands in that source on the map. Change it before you add if the guess is wrong; typed text stays "Typed in ObsidiNote". A page you added earlier has no recorded origin and stays in "ObsidiNote notes" until you set **From** in its Edit form.

### Changed
- Dot sizes on the knowledge graph now show how much a page matters:
  - A page grows with the links *to* it, and strong links count more than loose ones. Its own links count half, so a new page with many proposed links no longer looks important on its first day.
  - Sizes change smoothly: one link more is a little bigger, not a jump.
  - Hubs are the most linked-to pages of your vault (about the top 5%, linked to by at least 3 pages) instead of every page with 5 links, so a small vault has hubs too and a big one is not crowded with them.
- Lines between topics are wider when their links are stronger, not only when there are more of them.
- Lines between topics are calmer and easier to follow:
  - Topics with links between them are placed next to each other, the strongest first, so their lines are short and straight. Where that is not possible, a line bends around the topic in its way instead of running over or under it.
  - With nothing selected, only the 8 strongest show. Zoom in to see all of them, or point at a page to see every line of its topic.
  - Each line leaves its area on the side facing the other topic, and lines that leave at the same spot are spread apart.
- A topic's name now sits in the middle of its area, in bold, and fades out while your pointer is over that area, so it never hides the pages.
- Two pages that link each other show as one line and count as one link.
- **Link it** now saves the link as "related" instead of "loose", since you made it yourself. Links you made before are set to "related" at the next start (the start says so on its upgrade line).

## [v0.8.1] - 2026-11-14

### Changed
- The knowledge graph is easier to read:
  - A small vault fills the frame instead of a third of it, and every page is named when there are up to 60 pages, or when you zoom in.
  - Links between topics show as one line per pair of topics, thicker when more pages are linked; the page-to-page lines show when you point at a page.
  - Topic names never lie on another topic: each sits above, inside the top of, or below its own area.
  - The Unfiled area is only as big as its pages need, and sits at the edge.
  - The preview card opens on the side away from the page's linked pages.
  - The picture no longer runs under the zoom buttons and the legend.

## [v0.8.0] - 2026-11-14

### Added
- **Edit** a page in the page window: its title, type (within its section), topics, aliases, summary, a link page's address, and its links to other pages (add, remove, strength, reason). Saving writes straight into the OneNote page and the index; the pages it links to get their "Linked from" updated. Your own text on the page is never changed. Replaces the inactive "Edit links" and "Move in index" buttons.
- When the side bar says Copilot is not connected, a **refresh button** next to it tries to connect again (it opens ObsidiNote's Edge window when that was closed). If Copilot first wants you to sign in, the note says so; sign in there and press the button again.
- `validation\Run Validation with write tests.cmd`: double-click to run the validation kit with its write tests.

### Changed
- ObsidiNote sends you to OneNote less: a cited link page (the [1] in an answer, or its source) opens the link itself; a source that is not a link shows on the map; the page window of a link page has **Open link** first. "OneNote" stays as a small second link.
- Web addresses in an answer are clickable and underlined, and the [1] markers sit on the text line.
- Links to company data count as internal, also outside Microsoft 365: your company's Workday, ServiceNow, Atlassian, Okta and similar tenants, and sites with your company's name in their address. Public pages (job boards, your company's public web site, everything else) stay web links. Link pages you added before are brought in line too: at the next start ObsidiNote moves each one to the right section (Internal links or Web links) with the matching type, keeps its text and its links, and updates the index; the start shows how many it moved.
- The side menu stays in place while the page scrolls. The logo, the notebook switcher and the menu at the top and the notes, Export and the theme switch at the bottom are always visible; only the list of sections scrolls, inside its own area. In a very short window the whole side menu scrolls, so nothing is cut off. The side menu is split into clear parts with a thin line between them: the logo, the notebook, the menu, the sections, and at the bottom the notebook's counts with Export and, on its own, the theme switch.
- Page names on the knowledge graph sit on small pills, so lines and dots no longer run through them; the page under the pointer gets a larger pill with a purple edge.
- The link in an Add result is clickable.
- ObsidiNote refuses ports 8765 and 8766 for its window, so it never shares a local port with the other Copilot helper on this computer (its window uses 8765, or 8766 when that is taken). The defaults (8767 for the window, 9334 for Edge) did not change.

### Fixed
- After an update, the window stayed white when the older ObsidiNote was still running: the new start opened the old one's window, which could not serve the new interface files. The start now says that an older version still runs and asks you to close its console window first. (Until you have this version: close every ObsidiNote console window, then start ObsidiNote again.)
- The validation kit's write tests stopped at "Dev vault" with "Send-CopilotPrompt is not recognized"; Add, "Check for the answer" and Ask run again.
- Buttons in one row now have one height: "Open in OneNote" and "Open link" were 2 px taller than the buttons next to them, and in the page window's Edit form "Remove" and "Add link" were lower than the fields beside them.
- The `internalHosts` setting was read nowhere; it now counts.
- After you closed a page window opened by clicking a dot, the dot's small card stayed on the map and a click did not close it. The card now goes away with the window, and a click on an empty spot (or outside the map) closes any card.

## [v0.7.0] - 2026-11-13

### Added
- **Find**: press Ctrl+K anywhere to jump to a page or topic of your vault. The knowledge graph's search also takes filters (`type:`, `topic:`, `site:`, `after:`, `before:`, `is:archived`, `is:hub`, `is:unlinked`) and "quoted phrases", shows the active filters as chips you can remove, and ignores case and accents.
- **Filter** the knowledge graph by page type and topic, or show only pages without links. Archived pages are hidden unless you ask for them; the header says how many. **Focus on this page** (in the page window, or F on a dot) shows a page and its linked pages one or two steps away. The List shows the same pages.
- The page window has **Back** and **Forward** (Alt+Left / Alt+Right) for the pages you visited in it.
- **Mentions, not linked**: the knowledge graph shows pages that name each other by title or alias without a link, and **Link it** in the page window links them in one step.
- Text you paste from a web page, Word or a mail keeps its structure: headings, lists, tables, bold, strikethrough, code and links come into the box as Markdown, which ObsidiNote turns into OneNote formatting. Images are left out with a note. Ctrl+Shift+V pastes plain text.
- After an update, the window shows "Updated to vX.Y.Z" with what is new in that version. Dismiss hides it until the next start.

### Changed
- The box is cleared once your text has been processed (the result or answer shows below it). It keeps your text only when it could not be sent.
- The knowledge graph's List is now one table of all pages (Page, Type, Topics, Site, Links, Changed): sort by any column, group by topic, type, site or year (or not at all), and fold groups. Long lists show 500 rows at a time.

### Fixed
- The Add result below the box is as wide as the box again, instead of a narrower column in the middle.
- Every page you added showed twice on the knowledge graph: once in its topic and once under Unfiled, titled with the text or link you pasted. That second dot was the Add request in your Intake; Intake requests are no longer listed in the index or on the map. Index pages written earlier are cleaned up at the next start.

## [v0.6.1] - 2026-11-13

### Changed
- The knowledge graph looks like the picture in this README: larger grey topic areas spread over the whole graph (it now fills the window down to the bottom), small bold topic names above them, slightly clearer grey links, and thicker purple links to the pages around the one under the pointer. The topic areas stay grey while you hover, and the other pages fade less. A vault with only a few pages no longer shows giant dots. On a phone, topic areas show only their name.

## [v0.6.0] - 2026-11-13

### Added
- **Export as Markdown.** A copy of your notes as Markdown files that open in any Markdown editor: one page from its window in the knowledge graph (**Export as Markdown**), a topic with its subtopics (in the page window's Topic tab, or next to the topic in List), or everything from the side bar (**Export all as Markdown**). Each page gets front matter (id, type, title, topics, aliases, link, summary, links), its text with headings, lists, tables and styles, and `[[links]]` to the other pages; topics become folders. The file goes to your browser's downloads; ObsidiNote keeps no copy. Images, drawings and attached files stay in OneNote; a line says where they were.
- Updating a link page no longer ends in "did not answer in time" when Copilot is slow: the update waits in your Intake as "Update: ..." and **Check for the answer** finishes it later, the same way as for new items. This also holds for a link you paste again.

### Changed
- An Add now shows "waiting" with **Check for the answer** after about 2 minutes, instead of keeping the window busy for up to 15 minutes. Copilot keeps working on it either way.

## [v0.5.0] - 2026-11-13

### Added
- **Markdown becomes OneNote formatting.** OneNote has no Markdown format, so text you add in Markdown is turned into real formatting on the page: headings, bold, italic, strikethrough, inline code and code blocks (monospace), links, bullet and numbered lists (nested), quotes and tables. Text without Markdown is added as before.
- **Colour theme:** System / Light / Dark at the bottom of the side bar. System (the default) follows Windows' light or dark setting; the choice is kept in this browser only.
- **Check for the answer.** When Copilot needs longer than the wait to answer an Add (reading a SharePoint page can take minutes), ObsidiNote no longer stops it. The result says Copilot is still working and the item waits in your Intake; press **Check for the answer** later to file the page from Copilot's answer. Every request carries a short reference that Copilot repeats (and, for a link, the link it read), and only the answer with that reference is used; an answer for something else, or one that does not fit, writes nothing.

### Changed
- Add and Ask wait longer for Copilot: up to 10 minutes, and up to 15 while Copilot still shows it is working. A silent Copilot (for example while it reads a SharePoint page) is no longer stopped after 90 seconds, but after 5 minutes.
- While the knowledge graph loads it shows only "Reading the map…", no grey placeholder areas; an empty vault shows "No pages yet".
- Inbox is now called Intake, so it no longer reads like ObsidiNote pulls mail. An existing vault's `01 Inbox` section is renamed to `01 Intake` the next time ObsidiNote opens the vault; its pages and links stay.
- ObsidiNote waits while Copilot is still answering before it sends the next item, instead of typing over a running answer.

### Fixed
- Pasting a SharePoint link no longer ends in "Not added - Copilot gave no answer (NoAnswer)" when Copilot is only slow: the item waits for **Check for the answer** instead.

## [v0.4.2] - 2026-11-13

### Changed
- ObsidiNote waits up to 10 minutes (was 5) for the sign-in to Edge and to Microsoft 365 Copilot.
- The text box is about twice as high (six lines). The side bar's buttons ("Set up this notebook", "New ObsidiNote vault") look alike: as wide as the notebook list, one line, the same style.

## [v0.4.1] - 2026-11-13

### Added
- **Set up ObsidiNote in this notebook.** When the notebook shown is empty (no pages), the side bar offers to set it up as your vault. After you confirm, ObsidiNote adds its sections to it and makes it the active vault. A notebook with pages of yours is never set up this way.

### Fixed
- The window said "Copilot is not open in ObsidiNote's Edge window" while Copilot was connected. It now trusts ObsidiNote's own connection to Copilot.

### Changed
- No focus outline around the text box when you click or type in it.
- The note for a missing vault says what to do in the window, instead of asking you to open a notebook in OneNote.
- The Auto / Add / Ask switch sits centred at the top of the box; the keyboard shortcuts moved behind an (i) button in its top right corner (shown on hover or keyboard focus).

## [v0.4.0] - 2026-11-13

### Added
- **Vaults.** An ObsidiNote vault is now recognised by its state page (the `ObsidiNote` page in `00 Index`, with the vault's own id), not by a section name. A vault can be a whole notebook or a section group inside a notebook, and there can be several. The start continues in the vault you used last (kept as `"vaultId"` and `"notebook"` in `config\obsidinote.local.json`), else in the only one that is open; with several and none on record, you choose one in the window. The console shows a `Vault` line: which vault, how many pages and topics, and whether the index was complete.
- **New ObsidiNote vault** in the side bar: give it a name and ObsidiNote makes a notebook with its fixed sections (`00 Index`, `01 Inbox`, the buckets, `Journal`, `Archive`) and makes it the active vault. You can also put a vault inside an existing notebook as a section group; ObsidiNote asks first, because that writes into a notebook it does not own yet. When OneNote cannot make the notebook next to your cloud notebooks, it goes to OneNote's default notebook folder on this PC and the window says so.
- **Write guard.** ObsidiNote writes only inside the active vault. Every write is checked first, and anything aimed at another vault, another notebook or outside the vault is refused. Switching vault is always your own choice in the switcher.
- **One writer per vault.** The ObsidiNote that opens a vault takes its writer lease (on the vault's state page, no lock file) and renews it while it runs. A second ObsidiNote on the same vault runs read only and says so; it gives the lease back when it closes. Two PCs can work in two different vaults at the same time.
- **Central index.** Each vault keeps its index in `00 Index`: a root page, By type, A-Z, Unfiled, Links, Archive, Other sections and one page per topic, readable in OneNote and generated by ObsidiNote. On every start and after every change the notebook is checked against the index; pages missing from it are added (on Unfiled when they have no topic) and the start reports how many.
- **Connected notebooks.** Any other open notebook can be shown read only: its sections become topic areas in the knowledge graph, its pages dots and its OneNote links lines. Ask can read it too. Nothing is ever written to it.
- **Knowledge graph.** The Knowledge graph page now shows the shown vault or notebook: pages as dots grouped in soft topic areas, links as curved lines whose weight is their strength, a list view, search with `/`, and a page dialog with "Open in OneNote" and "Ask about this", which puts a question about that page in the box.
- **Add.** Sending text or a link files it: an Inbox page first, then Copilot picks the type, topics and links, and ObsidiNote writes the page into its bucket with its properties, the text with links to related pages, and "Linked from" on those pages, then updates the index. The result shows where the page sits in the index, its topics and links with their strength and reason, and related pages you already had. **Undo** moves the page to OneNote's Deleted Pages and takes it out again.
- **Link buckets.** A pasted link becomes one summary page: Microsoft 365 links (SharePoint, OneDrive, Teams, Loop) go to `Internal links`, all others to `Web links`. Pasting the same link again updates its page instead of making a second one. **Update** reads the source again and shows old against new; earlier summaries are kept on the page, and your "Your notes" part is never touched. If you edited the summary yourself, ObsidiNote asks before replacing it.
- **Ask.** A question walks the central index: Copilot first picks branches, then pages, and answers only from the text of those pages, with numbered sources that open in OneNote and the path it took. Ask can also read other vaults and connected notebooks (chosen under "Ask reads"), and archived pages when you switch them on. Ask a follow-up, save the answer as a page (through Add), or show its sources on the map. When nothing answers it, you can save the question as an Open question. Asking never changes your notebook.
- **Validation kit.** `validation\Run Validation.cmd` checks this computer, OneNote, Copilot, the window, Copilot's reach into OneNote, Loop, SharePoint, OneDrive and the web, and the vaults with Add and Ask. It writes a log and a short summary to the Desktop that hold only results, counts and timings (no names, text, answers, links or ids), so they can be sent back. Write tests (`-WriteTest`) only touch the notebooks `ObsidiNote-Probe` and `ObsidiNote-Validation`. Step-by-step runbooks are in `docs/runbooks/` (start with RB-00).
- Without Copilot (started with `-NoCopilot`, or not signed in) Add and Ask say that Copilot is not connected; the notebooks, the knowledge graph and Undo still work.

### Changed
- Sending in the box now adds or asks instead of saying that this comes in the next step.
- With several vaults open and none chosen, the window no longer makes the first one active by itself.

## [v0.3.0] - 2026-11-13

### Added
- The ObsidiNote window. After the Copilot step, ObsidiNote starts a local server on `http://127.0.0.1:8767` (this computer only) and opens its window as a new window of ObsidiNote's own Edge. The console shows `[OK] ObsidiNote  open at http://127.0.0.1:8767` and ObsidiNote keeps running until you close that console window or press Ctrl+C; Copilot stays connected meanwhile. Starting ObsidiNote again while it runs opens the window of the running one.
- In the window: one box to add something or ask your wiki, with Auto, Add and Ask modes (`Ctrl+1`, `Ctrl+2`). In Auto, fixed rules show before you send whether the text will be added or asked, and why (a question word or question mark on short text asks; a link on its own, longer text, a pasted mail or meeting, or a statement such as "We decided" adds). Sending says that adding and asking come in the next step.
- The side bar lists the sections and section groups of the shown notebook with page counts, and "Recently changed" lists its 10 most recently changed pages; a title opens the page in OneNote. Both are read from OneNote and never written to disk.
- Notebook switcher at the top of the side bar with every notebook open in OneNote. ObsidiNote vaults come first; for now a vault is a notebook with a `00 Index` section, whatever its name. Other notebooks are marked "read only". Choosing a vault makes it the active vault: the window remembers it, and the start opens it next time (`"notebook"` in `config\obsidinote.local.json`). A read-only notebook is only shown, and the box says that an Add goes to the active vault. No notebook is written to.
- A note in the side bar when OneNote is not running, no vault is open, or Copilot is not available. Nothing is shown when all is well.
- Knowledge graph and History pages that say they come in a later step.
- Setting `"uiPort"` (default 8767) in `config\obsidinote.json`; override it in `config\obsidinote.local.json`. Reserved ports, ports that browsers block and the Edge port are refused.
- `-NoWindow` (or `OBSIDINOTE_NO_WINDOW=1`) starts ObsidiNote without opening its window. With `-NoCopilot` the window opens in ObsidiNote's Edge profile, or in the default browser when Edge cannot start.
- Exit code 4: the window's local server could not start (for example, the port is in use).

### Changed
- The start no longer prints the "ready; no interface yet" line and the sample JSON line; the scaffold's `-Name` and `-DryRun` parameters are gone.
- The start opens the vault on record, the last one chosen in the window. Without a record, it looks for a notebook called ObsidiNote or one with a `00 Index` section. It no longer replaces the record with another notebook that happens to be called ObsidiNote.

### Security
- The local server answers only this computer, checks the Host and Origin headers exactly (127.0.0.1, localhost or [::1] with its port), requires the header `X-ObsidiNote: 1` on every API call, and serves only the built files of the window from a fixed list.

## [v0.2.5] - 2026-11-12

### Fixed
- When Edge requires signing in to the browser (policy BrowserSignin = 2), the Edge window ObsidiNote opened closed at once, so there was no chance to sign in. ObsidiNote now runs a one-time Edge sign-in step first. It opens Edge for its profile the plain way, so Edge can show its own sign-in, waits up to 5 minutes until the profile is signed in with a work account, then closes that window and opens Copilot.
- An update that replaced `Start ObsidiNote.cmd` while it was running made Windows read on in the new file ("'uter' is not recognized") and start ObsidiNote twice. Every launcher (`Start ObsidiNote.cmd`, `update.cmd`, `sso-setup.cmd`) is now one block that Windows reads in full before running it, and a test keeps it that way.

## [v0.2.4] - 2026-11-12

### Fixed
- Copilot no longer keeps failing to open on a managed PC. Before, each attempt could send a sign-in page back to Copilot, which restarted the sign-in, and after 15 quick attempts the start gave up with "Lost the connection to the Copilot tab". Now a sign-in page is left alone, and ObsidiNote keeps attaching to the current Copilot tab until the 5-minute sign-in time is up.
- ObsidiNote never opens a second Edge window for its profile. When its Edge window is still starting, the start waits for it (up to 45 s) instead of starting Edge again. When that Edge profile is already open in a window without ObsidiNote's debug port, the start stops and says to close that window.
- When Edge policy requires signing in to the browser itself (BrowserSignin = 2) and ObsidiNote's Edge profile is not signed in yet, Edge closes the Copilot window. The start now says so: sign in to Edge with your work account in that window, then start again.
- When Edge policy blocks the debug port, the start stops at once and says to ask IT, instead of retrying.

### Added
- Single sign-on setup: `sso-setup.cmd` turns on Edge's "Allow single sign-on for work or school sites using this profile" in ObsidiNote's own Edge profile, after you confirm, so Copilot signs in with your Windows work account by itself. It changes nothing else: your normal Edge profile and Edge policies stay as they are. It writes a log with names and yes/no values only to `%LOCALAPPDATA%\ObsidiNote\logs`. `-Off` turns it off again.
- Setting `"signIn"` in `config\obsidinote.json`: `single-sign-on` (default, ObsidiNote's own Edge profile) or `private` (a private session: you sign in yourself at every Edge start).
- The start shows each step as a status line (`[OK]`, `[WARN]` or `[FAIL]`), with the same helper the installer uses:
  - Update: "up to date (vX.Y.Z)", why it did not update (for example a git clone with local changes), or the update it installed. After an update, the new version starts at once with the same arguments, and the old one ends.
  - This computer: Windows PowerShell 5.1, Full Language mode, desktop OneNote, Microsoft Edge, Edge policies (debug port, forced browser sign-in), the debug port (free or ObsidiNote's own Edge), the Edge profile (signed in with a work account, a personal account or none; single sign-on on, off or unavailable) and GitHub (for updates). If the PC has a work account and single sign-on is off, the start says to run `sso-setup.cmd` once. A FAIL ends the start with what to do (exit code 1).
  - OneNote: opens ObsidiNote's notebook, which starts OneNote with that notebook open, and waits until it answers. Where the notebook is gets saved in the `"notebook"` setting in `config\obsidinote.local.json` the first time it is found. Until then the start opens OneNote itself and says so.
  - Copilot: when Copilot cannot be reached, the line says what to do for that cause.
- `Start ObsidiNote.cmd` starts in its own folder and runs Windows PowerShell (`powershell.exe`) explicitly.

## [v0.2.3] - 2026-11-12

### Fixed
- The install bootstrap no longer ends with a newline. On machines that run it line by line, that left one "empty string" error after a finished install. `.editorconfig` and a test keep it so.

### Added
- Design: archive and delete. Both always ask for confirmation first. Archive is the default: it moves a page to `Archive / <bucket>`, keeps its id, links and index entries, and can be restored. Delete is explicit: a confirmation dialog, then OneNote's own Deleted Pages, kept 60 days. It removes the page's index entries and turns links to it into "(deleted: title)". Only ObsidiNote's own pages can be removed, never automatically: a "Tidy up" view only suggests. Probe P1c checks links after a move or delete.
- Design: pasted links. A SharePoint, OneDrive, Teams or Loop link goes to `Internal links`, any other URL to `Web links`, decided by host rules. Copilot summarizes each link into a fixed page shape (summary, key facts, where, kind, sensitivity label, date checked), never the full text. A link pasted again updates its page instead of duplicating it, and the central index gets a Links page grouped by site and domain. Probes P7 and P8 cover the internal and external case.
- Design: updating link summaries. An Update button per link, plus "Update all" for a site or domain and "Update stale links" (older than 90 days). Copilot re-reads the source and the result shows old against new. The last 3 summaries stay collapsed on the page, linking runs again (outdated links are shown for review, never removed silently), and the page's "Your notes" outline is never touched.

## [v0.2.2] - 2026-11-12

### Fixed
- The install command (`irm .../install.ps1 | iex`) failed on machines whose shell hands the script to `iex` line by line: blank lines gave "empty string" errors and multi-line blocks would not parse. `install.ps1` is now a one-line bootstrap that downloads the full installer (`tools/install-main.ps1`) and runs it as a file, so it works either way. A test keeps the bootstrap line-by-line safe.

### Added
- Design: a fixed notebook structure. `00 Index` and `01 Inbox`, then one section per page type (`Notes`, `Sources`, `People`, `Projects`, `Meetings`, `Decisions`, `Journal` by year, `Files`) and an `Archive`, with title rules and a 500-page rollover. Topics live only in the central index.
- Design: the completeness rule. Every page appears in the central index (topic hubs or Unfiled, By type, A-Z), and the app checks this on every start and after every write.

## [v0.2.1] - 2026-11-12

### Changed
- The installer runs in clear steps: a "Before installing" check (Windows PowerShell 5.1, Full Language mode), the install, then a "This computer" check of what ObsidiNote needs (desktop OneNote, Microsoft Edge), then the summary. The README's install section is a three-step quick start.

### Added
- A test that fails on download-and-run forms antivirus treats as malware (a WebClient download fed straight into a script, encoded commands) in scripts and docs.

## [v0.2.0] - 2026-11-12

### Added
- One-line installer `install.ps1` (latest release into `%LOCALAPPDATA%\Programs\ObsidiNote`, checked against `SHA256SUMS`, with desktop and Start menu shortcuts); the README shows its command instead of the old quick start.
- Startup starts desktop OneNote when it is not running (or runs only in the background), minimised, and waits up to 60 s until its COM API answers; without OneNote the start stops with exit code 2. Skip it with `-NoOneNote` (`lib/OneNoteHost.psm1`).
- Startup connects to Microsoft 365 Copilot after the OneNote step: ObsidiNote opens its own Edge window (profile `%LOCALAPPDATA%\ObsidiNote\edge-profile`, debug port 9334, setting `cdpPort` in `config\obsidinote.json` / `config\obsidinote.local.json`), waits up to 300 s for you to sign in, and stops with exit code 3 when Copilot cannot be reached. Skip it with `-NoCopilot` or `OBSIDINOTE_NO_COPILOT=1`.
- The Copilot bridge (`lib/CopilotBridge.psm1`, `lib/Cdp.psm1`, `config/selectors.json`): it sends prompts and rebuilds replies, and writes nothing to disk (no reply-frame dumps, screenshots or lock files); its log `%LOCALAPPDATA%\ObsidiNote\logs\obsidinote.log` holds ids, counts, timings and states only.

## [v0.1.2] - 2026-11-12

### Fixed
- Updates computed the wrong file list when the app or temp folder was reached through an 8.3 short name (for example the CI runner's profile folder, `RUNNER~1`): relative paths were cut in the wrong place, so changed, locked and removed files were missed and a rollback could put back the wrong files. Files are now enumerated with the folder exactly as given. This is also why every CI run failed until now.

## [v0.1.1] - 2026-11-12

### Changed
- App icon redrawn as a rock: an irregular outline with uneven facets lit from the top left, instead of seven facets around one centre (which read as an umbrella). All sizes regenerated (`tools/make-icon.py`).

### Added
- README screenshots of the interface mock-ups (home, Add result, Ask answer, knowledge graph, page details) in `docs/screenshots/`.

## [v0.1.0] - 2026-11-12

First public version: feasibility stage. No app yet; the OneNote probes, the design and the
update mechanism are in place.

### Added
- Project scaffold (ps51: Windows PowerShell 5.1 tool (zero-install, ASCII-only, Pester 3.4)) with tests, CI and release script.
- `FEASIBILITY.md`: research on a self-linking wiki on OneNote or Loop with M365 Copilot, design of the central index (topic paths, path-based retrieval) and the Add / Ask / Map web interface, go/no-go probes.
- Purple accent as the one hue: `--purple-*` raw palette and `--accent` / `--accent-hover` / `--accent-soft` / `--on-accent` / `--ring` roles in `src/styles/tokens.css`, light and dark values (7.1:1 and 6.4:1), and the "One Purple" rule in DESIGN.md. Status soft fills stay neutral.
- App icon: a faceted purple stone with a white N, as `assets/icon.svg`, `obsidinote.ico` (16 to 256 px), `favicon.svg` and `favicon.ico`, generated by `tools/make-icon.py`.
- Storage principle: OneNote is the only store. Content, inbox, central index and state live in the ObsidiNote notebook; on disk the app keeps only files without content (settings, the updater's backups and log) (FEASIBILITY.md section 5).
- Map design rule "Every Dot Is Content": only real notes, files and links are dots, and every topic area has a visible label.
- Automatic updates at every start (`tools/update.ps1`, `update.cmd`): a git clone pulls `main` (fast-forward only); a release install compares `version.txt` with the latest GitHub Release, checks the zip against `SHA256SUMS`, and mirrors it in with a backup that is put back if the copy fails. Files in use hold the update instead of half-copying it; `config\*.local.json` is kept. `update.cmd -To vX.Y.Z` goes back to an earlier release and skips the newer ones; `"autoUpdate": false` in `config\obsidinote.local.json`, `-NoUpdate` or `OBSIDINOTE_NO_UPDATE=1` turn it off. Each start checks the app folder against the release's `manifest.json` and repairs an incomplete install once.
- Releases now ship as `ObsidiNote-vX.Y.Z.zip` (one `ObsidiNote\` folder with `version.txt` and `manifest.json`) plus `SHA256SUMS`.
- `probes/`: OneNote COM probes (P1 round trip, search check, cleanup) and the Copilot grounding prompt (P3).

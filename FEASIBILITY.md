# ObsidiNote: feasibility study

Question: can we build a self-linking personal wiki, in the style of Markdown note apps,
where anything you add is indexed and linked to related topics automatically, with
M365 Copilot as the only reasoning layer and OneNote or Loop as the repository?

**Short answer: yes with OneNote, mostly no with Loop.** OneNote can be read and written
locally through the desktop COM API from PowerShell 5.1, with no install. Loop has no public
read or write API, so the only way to write to it would be driving the Loop web editor, which
breaks easily. Copilot does the classifying and linking. The harness owns the index, the links
and every write, because Copilot cannot write into either app and its search over OneNote is
unreliable.

Status: research only (2026-11-12). Nothing built yet.

---

## 1. What a Markdown note app actually is (and what it is not)

| Concept | What it does | Notes |
|---|---|---|
| Vault | A folder of plain Markdown files; local-first | The files are the database |
| `[[Wikilinks]]` | Link to a note by title; you can link to a note that does not exist yet (it gets created later) | Links are typed **by the user** |
| Backlinks | Each note lists the notes that link to it | Computed from the files |
| Unlinked mentions | Notes that mention this title in text but don't link it | A plain text search; the user confirms each one |
| Tags and properties | `#tag` and a YAML front-matter block (type, date, aliases, ...) | Can be queried (Dataview plugin) |
| Graph view | Notes as nodes, links as edges; global and local graphs | Rendered from the link index |
| MOCs / hub notes | Hand-written "map of content" notes that index a topic | A convention, not a feature |
| Daily notes, templates, Canvas | Capture flow and visual boards | |
| AI plugins | Use embeddings to suggest "related notes" | Plugins only. The core app links **nothing** by itself |

The point for us: **such apps do no automatic linking.** Their value comes from cheap links,
backlinks and the graph; the user does the thinking. ObsidiNote has to supply what they
leave to the user: classifying, linking, and keeping hub notes up to date. Copilot does that.

## 2. Mapping onto OneNote

| Markdown note app | OneNote equivalent | How (COM API) |
|---|---|---|
| Vault | One dedicated notebook on OneDrive (e.g. `ObsidiNote`) | `OpenHierarchy` / `CreateNewPage` |
| Folder | Section / section group (e.g. `Intake`, `Notes`, `Topics`, `Sources`) | `GetHierarchy` |
| Note | Page | `GetPageContent` / `UpdatePageContent` (page XML) |
| `[[link]]` | `onenote:` hyperlink to a page or paragraph | `GetHyperlinkToObject` |
| Backlinks | A "Linked from" outline at the bottom of each page that **the harness owns** and rewrites | `UpdatePageContent` on that one outline |
| Properties / tags | A small properties outline at the top of each page (type, topics, source, date, id) | Page XML |
| Unlinked mentions | OneNote's own search index | `FindPages` (uses Windows Search) |
| MOC / hub note | Auto-generated topic hub pages in `Topics`, rebuilt after each ingest | Harness |
| Graph view | Rendered by the harness web UI from its local index | Not in OneNote |

**Verified (2026-11-12, consumer account):** `OneNote.Application` (desktop OneNote 16.0.20326)
is registered and `GetHierarchy` works from **Windows PowerShell 5.1**. In PowerShell 7 the same
call threw an "Unexpected HRESULT" COM error, so stay on 5.1, which the Copilot bridge requires
anyway. No notebooks were open, so we have not yet tested writing.

**P1 result (2026-11-12, `probes/p1-roundtrip.ps1`): PASS.** The script created a cloud
notebook on OneDrive through COM (`OpenHierarchy` with an `https://d.docs.live.net/...` path
takes about 6 s the first time and under 1 s after that). It then created a section and two
pages, linked A to B with `GetHyperlinkToObject`, and wrote a properties outline, a body and a
backlinks outline. Each `UpdatePageContent` took 20 to 40 ms. Results:
- `<one:Meta>` tags on the page and on each outline survive the round trip, so the tool can find
  its own outlines by tag (`obsn.role=backlinks`) without parsing text.
- Rewriting one outline by its `objectID` leaves the rest of the page untouched.
- **`FindPages` is not usable as a search engine.** New pages stay `isIndexed=false`. Until
  Windows Search indexes them, `FindPages` returns *every* page, including deleted pages in the
  recycle bin, whatever the search term. The tool must keep its **own full-text index**. That is
  easy, because the tool writes every page itself. Skip pages marked `isInRecycleBin`.
- PS 5.1 quirk: a function that returns an `XmlNamespaceManager` must use `,$m`, or PowerShell
  unrolls it.
- Writing error `0x80042000` means malformed XML: check element order and string building first.

Requirements and limits:
- The machine needs desktop OneNote (Microsoft 365 version), not the old Store app. It must be
  installed on the target machine too; check this first (probe P1).
- COM works only on notebooks that OneNote desktop has open and synced.
- Page XML follows the OneNote 2013 schema. Rich text, tables and images work; ink and embedded
  files are awkward.
- Alternative: the Microsoft Graph OneNote API. It needs an Entra app registration and token,
  which goes against the zero-install / no-admin goal. Keep it as a fallback only.

## 3. Loop as a repository

- **No public API to read or write Loop pages.** A Microsoft Q&A thread from Feb 2026 asks for
  one; the only answer points to the Feedback Portal. Loop pages are Fluid documents in
  SharePoint Embedded or OneDrive (`.loop`, Copilot Pages are `.page`).
- **Writing** would mean driving `loop.cloud.microsoft` in Edge over CDP, the same way the
  bridge drives Copilot. But Loop's editor is a collaborative Fluid editor. Typing structured content
  and page links into it through synthetic input is much harder to get right than one chat box,
  and it breaks whenever the UI changes.
- **Reading by Copilot:** `.loop` and `.page` are supported reference types in Copilot Notebooks.
- Verdict: **not suitable as the main store.** At most it could be a read-only "published" copy,
  or the home of a Copilot Notebook that points at the OneNote vault.

## 4. Copilot's role

Copilot has no memory between chats, cannot write to OneNote or Loop, and on the work tenant is
limited to about 80k characters per prompt and about 30 messages per chat (measured with the
earlier Copilot bridge). So we use it as a **stateless reasoning function**. The harness does everything else.

**Ingest / link call.** Input: the new item, plus a shortlist of existing pages (id, title,
aliases, one-line summary). Output: strict JSON, for example
```json
{ "title": "...", "summary": "...", "type": "concept|source|person|project|log",
  "topics": [{"id": "t12"}, {"new": "Zero-trust networking"}],
  "links":  [{"target": "p87", "anchor": "exact phrase in the text", "strength": 2, "why": "..."}],
  "aliases": ["..."] }
```
- The harness checks every id Copilot returns against the index, so invented targets are
  dropped.
- Shortlist first, then reason: a local pre-filter (OneNote `FindPages`, keyword and alias
  overlap) picks about 30 to 60 candidate pages. That keeps prompts small no matter how large
  the vault gets.
- Use JSON, not Markdown links, because Copilot's citation filter removes `[x]:` text. The bridge
  already rebuilds the raw reply around this.
- Batch several items per call; the daily Copilot limit is the scarcest resource.

**Hub refresh call.** Given a topic and the summaries of its pages, write or update the topic's
hub page (MOC).

**"Ask my wiki"**, two routes:
1. *Harness retrieval* (reliable): find matching pages with `FindPages` and the index, send their
   text to Copilot, and get an answer back with `onenote:` links.
2. *Copilot's own grounding*: Copilot Notebooks accept OneNote pages as references. Forum
   reports from mid-2026 describe references being ignored until fixes in August, and a limit of
   20 to 50 references depending on license. Whether plain Copilot Chat can search OneNote pages
   is not documented, so it has to be tested (probe P3). Build route 1; treat route 2 as a bonus.

## 5. Proposed architecture

### Storage principle: OneNote is the only store (user requirement, 2026-11-12)

All content, all index data and all state live **inside the ObsidiNote notebook in OneNote**,
protected by whatever protects that notebook: OneDrive/SharePoint storage, the tenant's
encryption at rest, sensitivity labels, retention and access control. The ObsidiNote app is a
**client that references that notebook**. It never keeps its own copy.

| Lives in the notebook | Section | How |
|---|---|---|
| Captured items, before and after processing | `01 Intake` | one page per item; status in `obsn.status` Meta (new, waiting, linked, failed + reason); `obsn.requestRef`/`obsn.requestKind` (the request reference Copilot repeats), and while waiting `obsn.waitingSince` and `obsn.chatUrl` (the Copilot chat's address, no query) |
| Content pages | the type buckets (`Notes`, `Sources`, `People`, `Projects`, `Meetings`, `Decisions`, `Journal`, `Files`; see Notebook structure) | body + properties outline + `obsn.*` Meta: `id`, `type`, `topics` (paths), `aliases`, `summary`, `links` (target id, strength, why; compact JSON in a Meta value) |
| The central index (topic tree, catalogue, edges) | `00 Index` | root page, By type, A-Z, Unfiled, and one hub page per topic; each topic page lists its subtopics and pages (readable), and carries the same data in `obsn.*` Meta (machine form) |
| Notebook-level state | `00 Index` › page `ObsidiNote` | schema version, id counter, writer lease |

What the app may keep outside the notebook: **no content**.
- Only an **in-memory working copy** while it runs, built at start by reading the Index section
  (small: one page per topic). Page text is read on demand by page id. On exit it is gone.
- `config\obsidinote.local.json`: settings only (auto-update, notebook name), never content.
- The updater's backups of the app's own files and its `update.log` in
  `%LOCALAPPDATA%\ObsidiNote`: program files and update messages, never content.
- Logs: ids, counts and timings only, never page text, titles or prompts.
- No `index.json`, no cache, no temp files with content. COM page XML stays in memory.

Consequences:
- **Copilot** receives page text in prompts. That is processing inside the user's own M365
  tenant, not storage by ObsidiNote. Note that M365 keeps Copilot chat history in the user's
  mailbox under the tenant's retention.
- **Edge profile.** ObsidiNote drives Copilot in its own Edge profile
  (`%LOCALAPPDATA%\ObsidiNote\edge-profile`, remote debugging on port 9334). That is browser
  state, not ObsidiNote data, but Edge's cache can hold parts of the Copilot pages (and so of the
  chat text) like any browser. The sign-in cookies live there too. Clearing the profile means
  signing in again; ObsidiNote never reads or writes it directly.
- **Startup order:** update check, install check, OneNote (start when it is not running, wait
  until COM answers; stop with exit code 2 if it does not), then Copilot (open the Edge profile,
  wait for sign-in until the message box is ready; stop with exit code 3 if it is not).
- **Concurrency.** A single writer is enforced by a lease Meta tag on the `ObsidiNote` page
  (session id + expiry, renewed while running). There is no lock file on disk. A second
  instance starts read-only.
- **Rebuildable index.** Each content page carries its own `obsn.*` Meta (source of truth for
  its topics and links). The Index pages are a mirror for fast loading, and a "rebuild index"
  scan regenerates them from the pages. When they disagree, the page wins.
- **No password-protected sections**: COM cannot read locked sections. Protect with the
  notebook's sharing and the tenant's labels instead.
- **Probe P1b (new):** how long a `obsn.*` Meta value may be (catalogue size per topic page),
  and the start time to load the Index section at 100, 1,000 and 5,000 pages.

```
 capture (web UI / MCP / hotkey / clipboard / file drop)
        |
        v
  Intake section in OneNote (one page per item, obsn.status)
        |
        v
  Shortlist  -- in-memory index (loaded from the Index section) -->  candidates
        |
        v
  Copilot (via the bridge)    -->  JSON: title, topics, links, aliases
        |
        v
  Validator  (ids exist, anchors appear in the text, no duplicate page)
        |
        v
  OneNote writer (COM, PS 5.1)
     - move the Intake page's content to a page in Notes (properties outline, body with links,
       obsn.* Meta)
     - rewrite "Linked from" outline on target pages
     - update the topic pages in the Index section (readable list + obsn.* Meta)
        |
        v
  in-memory working copy (refreshed from the Index section)  -->  graph view in web UI
```

- Reuse from the author's earlier Copilot bridge: `CopilotBridge.psm1` (Edge CDP, reply rebuild, Copilot mutex), the
  server and UI shell (React + Kokonut UI, monochrome), and the MCP pattern so a coding agent
  can drop items into the Intake.
- **Source data is read-only.** ObsidiNote writes only inside its own notebook. Existing
  OneNote notes, mail and files are copied in, never edited where they are.
- Everything the harness wrote is marked (properties outline, "Linked from" outline), so it can
  be rebuilt or undone without touching what the user typed.

### Notebook structure: sections, pages and buckets (user requirement, 2026-11-12)

One notebook, **ObsidiNote**, with a fixed set of sections that the app creates on first start
and never renames. The one exception: the Intake was called `01 Inbox` until 2026-11-13 (user:
"Inbox" reads like ObsidiNote pulls mail from Outlook); opening a vault renames its own `01 Inbox`
directly in the vault root to `01 Intake` once (pages keep their ids and links). When both exist,
`01 Intake` is the Intake and `01 Inbox` is listed as a section the user made, never edited. **A page's section is its type; its topics live in the central index.** A page
has exactly one home but can sit under many topics, and reorganising topics never moves a page.

```
ObsidiNote (notebook)
|-- 00 Index          the central index: Index (root), By type, A-Z, Topics/<topic> hubs,
|                     Unfiled, Open questions, and the ObsidiNote state page
|-- 01 Intake         one page per captured item until it is filed (obsn.status: new / waiting /
|                     linked / failed; obsn.requestRef ties a Copilot answer to the item)
|-- Notes             your own notes and concepts (evergreen; most pages land here)
|-- Internal links    one page per pasted Microsoft 365 link: SharePoint site, page, list or
|                     document, OneDrive file, Teams channel or message, Loop page, intranet
|-- Web links         one page per pasted external URL: article, documentation, tool, video
|-- Sources           sources without a link: books, talks, papers, pasted text
|-- People            one page per person (role, how you know them, related pages)
|-- Projects          one page per project; its parts as subpages (page level 2)
|-- Meetings          meeting notes, one page per meeting, titled "yyyy-mm-dd <subject>"
|-- Decisions         decision records: context, options, decision, date, owner
|-- Journal           section group: one section per year ("2026"), one page per day
|-- Files             one page per file you drop in (not a link): what it is, its summary, and the
|                     file embedded when small. A pasted link to a OneDrive or SharePoint file
|                     goes to Internal links instead.
|-- Archive           section group: pages that are no longer current, one section per original
|                     bucket (Archive / Notes, Archive / Web links, ...); restorable
```

| Bucket (type) | Goes there when Copilot's `type` is | Title rule |
|---|---|---|
| `Notes` | `concept`, `note`, `howto` | the subject in plain words |
| `Internal links` | `link-internal` (a Microsoft 365 / intranet URL) | the item's own title (site, page or file name) |
| `Web links` | `link-web` (any other URL) | the page's own title |
| `Sources` | `source` (book, talk, paper, pasted text; no link) | the source's own title |
| `People` | `person` | "Name (role)" |
| `Projects` | `project`, `project-part` (subpage) | the project name |
| `Meetings` | `meeting` | "yyyy-mm-dd subject" |
| `Decisions` | `decision` | "Decision: subject" |
| `Journal` / year | `log` (a day's entries) | "yyyy-mm-dd" |
| `Files` | `file` | the file name without extension |
| `01 Intake` | not filed yet, or failed | the first line of the item |

Rules:
- **Fixed type list.** Copilot must return one of the types above, and the validator rejects
  anything else. A new bucket is a design change, not something Copilot invents.
- **Size.** A section holds at most 500 pages, because OneNote gets slow with very large
  sections. A full bucket rolls over to `<Bucket> 2`, and `Journal` already splits by year. The
  index hides the split: you navigate by topic and type, not by section.
- **Subpages** (page levels 2 and 3) only for parts of one thing, such as a project's plan,
  risks and meetings. They are never used for topics.
- **Your own sections and pages.** If you add a section or page in the ObsidiNote notebook
  yourself, the app lists it in the index (under "Other sections") but never edits or moves it.
  The read-only rule for your data holds here too.
- **Archive by default, delete on request**: an archived page keeps its id, links and index
  entries, marked "archived". Deleting is explicit and confirmed, and goes through OneNote's
  Deleted Pages (see Archive and delete).

### Links: internal and external (user requirement, 2026-11-12)

Paste just a link, and ObsidiNote files a **summary page** for it, so you can find what the link
is about later without opening it again.

**Which bucket.** The app decides by the URL's host, with fixed rules and no model:
- **Internal** (`Internal links`): company data, wherever it is hosted (user, 2026-11-13):
  - Microsoft 365: `*.sharepoint.com` (including `-my.sharepoint.com` for OneDrive),
    `teams.microsoft.com`, `*.loop.cloud.microsoft` and `loop.microsoft.com`, `*.office.com`,
    `m365.cloud.microsoft`, plus any intranet hosts listed in the setting `internalHosts`;
  - a SaaS host that is the company's own tenant (Workday `*.myworkday.com`, ServiceNow
    `*.service-now.com`, Atlassian, Okta, Salesforce, SuccessFactors, Slack, Zendesk, Webex,
    Zoom and a few more; `NotebookStructure.psm1` `TenantSaasRules`), except the vendor's public
    pages (`www.`, `docs.`, `community.` ...);
  - any host with the company's name in a subdomain of someone else's domain (a service run for
    the company). The name comes from the vault's own OneDrive/SharePoint address at run time
    (`contoso-my.sharepoint.com` -> `contoso`), never from a file.
- **External** (`Web links`): obvious public pages: public job boards (`*.myworkdayjobs.com`),
  public site hosting (`*.github.io` ...), the company's own public domain, and everything else.

**How the summary is made.** Copilot does the reading:
- **Internal:** Copilot opens it with the user's own Microsoft 365 permissions (Work IQ / work
  grounding). The prompt holds the URL and asks for the fixed summary shape below. Copilot can
  read only what the user can open, and ObsidiNote never fetches SharePoint itself.
- **External:** Copilot's web grounding reads the page. If the tenant turns web grounding off,
  the app reads the page's text through its own Edge session and sends that text to Copilot
  instead. That text stays in memory, never on disk.

**Slow answers: check for the answer later** (user, 2026-11-13). Reading a SharePoint source can
keep Copilot silent for minutes. Pressing Copilot's Stop cancels its answer, so Add never stops a
slow answer: at the end of the wait the bridge returns `Pending` and leaves Copilot working, the
Intake item becomes `waiting` with its request reference (`ref`, a short code with no content that
every Add prompt asks Copilot to repeat; the link summary also repeats the link as `source`) and
the chat's address. **Check for the answer** (`POST /api/add/fetch`) reads that chat and takes only
the answer whose `ref` is the item's (and whose `source` normalizes to the item's link), checks it
exactly like a live answer and continues the Add from it; anything else writes nothing. Before any
new prompt, ObsidiNote waits while Copilot still shows it is answering, rather than typing over it.

**Fixed page shape** (one page per link, the same for both buckets):

| Part | Internal link | Web link |
|---|---|---|
| Title | the site, page or file name | the page title |
| Link | the URL, clickable (tracking parameters removed) | the URL |
| Where | site / library / owner, or team / channel | domain |
| Kind | site, page, document, list, file, channel, message, Loop page | article, docs, tool, video, other |
| Summary | 3 to 5 sentences: what it is and why it matters | the same |
| Key facts | up to 8 bullets: names, dates, numbers, decisions, contacts | key points |
| Use it for | one line: when you would come back to this | the same |
| Sensitivity | the source's label as Copilot reports it (shown, never copied) | n/a |
| Checked | date summarized; **Update** refreshes it | the same |
| Your notes | your own outline; the app never edits it | the same |
| Earlier summaries | collapsed, the last 3 with dates | the same |

The properties outline and `obsn.*` Meta hold `type`, `url` (normalized), `host`, `kind`,
`summarizedAt` and `topics`, so the index and search can use them.

Rules:
- **A summary, not a copy.** Never the full text of an internal document or a web page, only the
  summary and key facts plus the link back. The source stays where it is, under its own
  permissions and labels.
- **One page per link.** Pasting the same link again (compared without tracking parameters or
  fragments) updates its page: a new summary if the content changed, and "seen again" with the
  date. It never creates a duplicate.
- **Updating a link's summary** (user requirement, 2026-11-12):
  - **Where:** an **Update** button on every link page (the page modal, the Add result, and
    "check again" on the page itself), plus bulk options: **Update all** for a site, team or
    domain on the Links index page, and **Update stale links** (summarized more than 90 days
    ago). Ask also offers it when it cites a link summary older than 90 days.
  - **What it does:** Copilot reads the source again and writes a new summary in the same
    fixed shape. The app then re-runs linking on the new text, so new topics or links are added
    and ones that no longer fit are shown for review (never removed silently). It also updates
    the index entries (summary line, `summarizedAt`, Links page).
  - **What changed:** the result shows old and new side by side: summary, key facts added or
    removed, kind or title changed. If nothing changed, it says "No changes since <date>" and
    only the date is updated.
  - **History:** the previous summary moves into a collapsed "Earlier summaries" outline on the
    same page (the last 3, with their dates), so an update never loses what you saw before.
  - **Your own notes are safe:** each link page has a **Your notes** outline that the app never
    touches. If you edited the app's summary outline yourself (its content hash no longer
    matches), Update asks before replacing it and offers to keep your text under Your notes.
  - **Source gone or no access:** the old summary stays, marked "could not be updated on
    <date>: no access / not found", and the page appears in Tidy up.
- **Stale summaries.** A page shows "summarized N days ago", so you can see when it was last read.
- **No access:** if Copilot cannot open an internal link (no permission, deleted), the page keeps
  the link with "could not be read on <date>", and it stays Unfiled until it is checked again.
- **Index:** besides topics, By type and A-Z, the central index has a **Links** page:
  internal links grouped by site or team, and web links grouped by domain.
- **Probes:**
  - P7: on a business tenant, paste a SharePoint page URL and a OneDrive document URL into
    Copilot Chat with the summary prompt, and check that it returns the fixed shape from the
    real content.
  - P8: the same for a public web URL, with web grounding on and off.

### Archive and delete (user requirement, 2026-11-12)

Two ways to take information out of the way. **Archive is the default and fully reversible;
delete removes the page.** Both **always ask for confirmation** first: no exceptions, no "don't
ask again", the same for one page, a selection, a whole topic, Tidy up, and commands typed in
the box.

| | Archive | Delete |
|---|---|---|
| What happens | The page moves to the `Archive` section group (a section per original bucket, e.g. `Archive / Web links`). Its id, links and backlinks stay; `obsn.status = archived`, `obsn.archivedFrom` and the date are recorded on the page | The page goes to OneNote's own **Deleted Pages** (OneNote's recycle bin), which keeps it for 60 days. ObsidiNote removes its index entries and edges, and turns links to it on other pages into plain text: "(deleted: title)" |
| In the index | Listed on an **Archive** index page and in A-Z (marked archived); in topic hubs under a collapsed "Archived" group | Removed. The `ObsidiNote` state page keeps a **Recently deleted** list (title, bucket, date) for 60 days, matching the recycle bin |
| Ask and Map | Left out of Ask by default ("include archived" switch); faded in the map, behind a filter | Gone |
| Undo | **Restore** moves it back to its original bucket, with everything as it was | Within 60 days: restore it in OneNote (Deleted Pages); the next start's completeness check finds it and puts it back in the index. After that it is gone |
| Confirmation | **Always** (user, 2026-11-12): a dialog naming the page(s), their bucket and where they go (`Archive / <bucket>`), "You can restore it later". Primary button "Archive"; afterwards an "Archived · Undo" notice | **Always**: a dialog naming the page(s), the bucket, how many links point to them, and "OneNote keeps deleted pages for 60 days". Primary button "Delete" |

Rules:
- **Only ObsidiNote's own pages** can be archived or deleted by the app. Pages and sections you
  made yourself are listed but never moved or deleted (read-only rule); the app says "delete it
  in OneNote yourself".
- **Intake items**: "Discard" deletes them the same way (to OneNote's Deleted Pages).
- **Several at once**: select in the list or the map, or "Archive all pages of a topic". The app
  always shows the list first; a topic hub itself is never deleted while pages still use it.
- **Links and summaries**: archiving a link page keeps its summary. Deleting it also forgets the
  URL, so pasting it again makes a new page.
- **Suggestions, never automatic**: a "Tidy up" view lists pages that look stale (no links in or
  out, not opened or cited in 12 months, link summaries that could not be read for 90 days).
  You choose Archive or Delete per page; nothing moves by itself.
- **From the input box**: "archive …" or "delete …" is never treated as Add or Ask. It opens the
  same confirmation as the buttons, with the matching pages listed.
- **No permanent delete in ObsidiNote.** Emptying OneNote's Deleted Pages stays a OneNote action.
- **Probe P1c**: does an `onenote:` link still open the page after the page moves to another
  section (archive), and what does a link to a deleted page do? This decides whether archiving
  must also rewrite links.

### Connected notebooks (user requirement, 2026-11-13)

Besides its own notebook, ObsidiNote can **connect to any other OneNote notebook**, detect how it
is organised, and load it into the interface.

- **Which notebooks:** every notebook open in OneNote shows in a notebook switcher in the side
  rail. "Connect another" takes a OneNote link or a local `.onetoc2` path and opens it in
  OneNote first. The list of connected notebooks (name and location only, no content) is kept in
  `config\obsidinote.local.json`.
- **Detecting the structure (read only):**
  - ObsidiNote reads the hierarchy: section groups, sections, pages and page levels (subpages).
  - A notebook with `00 Index` and `obsn.*` Meta is **ObsidiNote-structured** and loads from its
    own index.
  - Any other notebook is **foreign**. ObsidiNote derives an index for it in memory:
    - topic paths from section groups and sections (`Group / Section`), with subpages as children;
    - the page list (title, section, modified date, onenote: link);
    - edges from the onenote: hyperlinks between its pages, read in the background.
- **In the interface:** the side rail and the knowledge graph show the connected notebook's own
  structure (sections as topic areas, its pages as dots, its links as lines), with "Recently
  changed". Ask can search it with the same path-based method, and Copilot reads page text in
  memory only.
- **Never written:** a connected notebook without an ObsidiNote vault is read only, always. A
  write guard in the OneNote adapter refuses every write (`UpdatePageContent`, `CreateNewPage`,
  `DeleteHierarchy`, moves) whose target is not inside the active vault (see Several ObsidiNote
  vaults), and a test enforces it. Its derived index lives
  in memory only, rebuilt each time it loads (OneNote is the only store, and ObsidiNote may not
  write an index into someone else's notebook).
- **Taking content over:** "Add to ObsidiNote" on a page of a connected notebook runs the normal
  Add flow. It creates a page in ObsidiNote's own notebook with a summary and a link back to the
  original page, never a move or a copy of the whole page. *(Comes with step 3, Add.)*
- **Size:** structure and titles load first, and page text loads on demand. A notebook with
  thousands of pages shows its structure in seconds; link edges fill in as they are read.

### Several ObsidiNote vaults (user requirement, 2026-11-13)

There can be **more than one ObsidiNote**, each in its own OneNote notebook file (for example one
per team or per project). ObsidiNote recognises a vault by its structure, not by the notebook's
name, and **continues in any vault it finds**.

- **What a vault is:** a structure root that holds `00 Index` with the `ObsidiNote` state page,
  whose Meta carries `obsn.schema` and a unique `obsn.vaultId`. The root is normally a whole
  notebook. It can also be one section group inside a larger notebook, so a vault can live inside
  an existing team notebook.
- **Detection:** at start, and whenever a notebook is opened or connected, ObsidiNote scans the
  open notebooks (and their top-level section groups) for state pages. Each vault found joins
  the switcher as writable, with its name, location, page and topic counts. Opening a notebook
  file that contains a vault is enough to continue in it: index, ids and links carry on from its
  state page.
- **The active vault:** exactly one vault is active at a time; the start reopens the last one used.
  - Add, Update, Archive and Delete write only into the active vault.
  - Ask and the knowledge graph read the active vault, and can include other vaults and
    connected notebooks as read-only sources.
  - Switching vault is a deliberate action in the switcher, and the window always shows which
    vault is active.
- **Write guard:** every write checks that its target lies inside the **active vault's root**
  (notebook or section group). Writes to another vault, to a foreign notebook, or outside the
  root are refused, and a test enforces it.
- **The writer lease** is per vault, on its own state page, so two PCs can work in two different
  vaults at the same time.
- **Records:** `config\obsidinote.local.json` keeps the known vaults (vault id, name, location as
  a OneNote link or `.onetoc2` path) and the last active one. These are not content, and the vault
  itself stays the only store.
- **New vault:** "New ObsidiNote vault" creates a new notebook with the fixed structure. To place
  a vault inside an existing notebook as a section group, ObsidiNote asks for confirmation first,
  because that writes into a notebook it does not own yet. After that, the section group is the
  vault root and the rest of that notebook stays read only.
- **Moved or renamed notebook:** the vault id stays the same. If its recorded location no longer
  opens, the start says so and finds the vault again by id in the open notebooks.

### Central index (user requirement, 2026-11-12)

The repository has **one central index**. Information is found by following **paths** through
the index, like a library catalogue, not by searching all pages.

- **Topic tree.** Every page hangs under one or more topic paths, e.g.
  `Security / Networking / Zero trust`. Topics have a parent, so each page has a full path, plus
  its location in OneNote (`Notebook > Section > Page`) and its `onenote:` link.
- **The index lives in OneNote, in the `Index` section** (see the storage principle above),
  written only by the harness. One root page "Index" lists the top-level topics and their paths.
  One page per topic lists its subtopics and pages with one-line summaries and links; these are
  the hub pages (MOCs). Each Index page carries the same data in `obsn.*` Meta tags (topic id,
  parent, children; per page: id, title, OneNote page id, link, summary, aliases, updated;
  edges with strength and why), so one document serves people, Copilot and the app. There is
  no separate index file.
- **Path-based retrieval (Ask).** Step 1: Copilot gets only the top levels of the topic tree
  (small) and the question, and picks the branches to open. Step 2: the harness sends those
  branches' subtopics and page summaries, and Copilot picks pages. Step 3: the harness sends
  the full text of those pages and Copilot answers with citations. Every prompt stays small,
  however large the vault grows, and each answer can show the path it took
  (`Index > Security > Networking > Zero trust > page`).
- **Ingest uses the same tree.** The shortlist for a new item is its likely branches plus
  keyword hits from the index. Copilot places the item at an existing path or proposes a new
  subtopic. The validator checks the path exists or that its parent does.
- **The index is also Copilot's map in OneNote.** If Copilot can read OneNote pages (probe P3),
  the Index pages let it work through the wiki from a single reference. That matters because
  Copilot Notebooks take only 20 to 300 references. Add to P3: give Copilot only the root
  Index page, then ask a question whose answer is two levels down.
- **Everything is listed (completeness rule, user requirement 2026-11-12).** Every page in the
  notebook appears in the index, with no exceptions:
  - in its **topic hubs** (one or more topic paths);
  - on **By type**: one list per bucket, so every page of `Sources` is listed even if it has no
    topic yet;
  - on **A-Z**: every page title alphabetically, with its bucket and topics;
  - on **Links**: every internal link by site or team, and every web link by domain;
  - on **Archive**: every archived page, by original bucket (deleted pages leave the index; the
    state page keeps a 60-day "Recently deleted" list);
  - on **Unfiled**: pages without a topic path, including your own pages, until they are placed.
    Intake pages are not listed: they are Add requests, not content (a filed one has become its
    own page; a waiting or failed one shows in the window's Intake card). Listing them made every
    Add show twice on the map (2026-11-13);
  - under **Other sections**: sections you made yourself, listed per section.

  The root **Index** page links to all of these, plus counts (pages per bucket, topics, links,
  unfiled). After every write, and on every start, the app checks the hierarchy against the
  index: any page id missing from the index is added to Unfiled, and the count of missing pages
  is reported. "Nothing outside the index" is a test.
- **Rebuildable.** The index can always be rebuilt from the notebook, because each page carries
  its id, topic paths and links in its own `obsn.*` Meta tags. If the Index pages are damaged or
  out of date, a scan of the content pages recreates them.

### Interface (user requirement, 2026-11-12)

The product is a **local web app**: a PS 5.1 server on 127.0.0.1
serving a prebuilt React UI, so nothing is installed at runtime. Three views:

| View | What the user does | What happens |
|---|---|---|
| **Add** | Paste text, a link, a file or a mail excerpt; optional hint (topic, type) | Intake → shortlist → Copilot → validate → write to OneNote; the result card shows the new page, its topics and links, with *undo* and *edit links* |
| **Ask** | Ask a question in plain words | Harness retrieval from its own index → Copilot answers with citations; each citation opens the OneNote page (`onenote:` link) |
| **Map** | Explore everything that has been added | Graph of all pages and topics; edges weighted by relevance; clusters = topics |

**Add or Ask from one input.** One box with a mode switch: Auto (the default), Add, Ask.
(See the interface mock-up; its link is kept outside the repo.) Auto decides in fixed, tested rules
(no model), in order:
1. Explicit choice wins: the button, `Ctrl+1` / `Ctrl+2`, a `+` or `?` prefix, or a dropped file
   (which means Add).
2. Ask when the input ends with `?` or starts with a question word (EN + NL list), and is short:
   one paragraph, under 300 characters, no link.
3. Add when the input is a link on its own, a file or image, longer text (over 300 characters
   or several paragraphs), pasted mail or meeting headers, or a statement prefix ("We
   decided", "Note:", "TODO").
4. Otherwise it is unclear. Copilot's reply starts with `intent: add|ask|both` inside the same
   call, so there is no extra round trip. The app shows its pick and the reason, and waits for
   Enter. The user's correction is kept as an example.

The chosen mode is always shown before sending ("Will ask your wiki: reads as a question"),
with a one-key flip. A wrong guess costs little:
- Every Add also lists the related pages you already had.
- Ask never writes.
- Add can be undone.
- An unanswered question can be saved as an "Open question" page.

Map details (the user's spec, 2026-11-12): a **Knowledge graph** of dots, with no large cards.
- **Dots** are pages; dot size = number of links. Pages with no links yet are hollow dashed dots.
- **Blobs** are topics: a soft grey area around each topic's dots, labelled with the topic
  name.
- **Lines** are links; line weight and opacity = link strength (1 to 3, the `strength` field
  in the link JSON). A filter can add "mentions, not linked" as faint lines.
- **Look and feel of the clustering** (the user's reference images, 2026-11-12, adapted to the
  light monochrome look):
  - Many small dots; clusters emerge from link density and show as soft grey areas (no glow),
    labelled "Topic · N pages".
  - Hubs (index or MOC pages, high centrality) are bigger.
  - **Every dot is content** (a note, file or link). No decorative dots, specks or dust
    (user, 2026-11-12).
  - Each topic area has a visible label: the topic name, then "N pages · main subjects".
  - Links are curved.
- **Focus and context on hover.** The hovered dot turns solid. It and its directly linked pages
  stay sharp and get labels, with the links to them drawn stronger. Everything else fades to
  about 20%. With nothing focused, only hub labels show.
- **Hover a dot** to see a preview card: index path, title, a one-line summary, link and
  backlink counts, when it was added, and "Click to open". Keyboard focus shows the same
  preview.
- **Click a dot** to open a large modal (native `<dialog>`: Esc closes, focus returns to the
  dot):
  - header: the index path, title, type and counts;
  - tabs: Page, Topic, Neighbourhood;
  - body: summary and page content from OneNote, links out with strength and reason, linked-from
    list, and mentions with "link it";
  - footer: Open in OneNote (primary), Ask about this, Edit links, Move in index;
  - ← and → step to the previous or next linked page.
- Zoom and pan with a small toolbar and hints; search with the "/" key; a legend for line
  weight, hollow dots and areas. Topic areas are placed from the index tree so they stay put;
  dots settle inside their area. Everything is grey except the purple accent, which marks only
  the focused dot and its links. Rendering is bundled at
  build time, with no CDN at runtime. A list view of the same data is the keyboard fallback.
- The graph comes from the harness index, so the map works even when Copilot is busy or over its
  daily limit.

## 6. Risks

| Risk | Mitigation |
|---|---|
| Desktop OneNote missing or COM blocked on the target machine | Probe P1 first; fallback = Graph API (needs an app registration) or a Markdown vault on OneDrive |
| User edits a page while the harness rewrites it | Only rewrite the outlines the harness owns; compare the page's `lastModifiedTime` before writing |
| Copilot links poorly or invents targets | Validator, shortlist, a review queue in the UI before writing (optional per item) |
| Copilot daily limit | Batch ingest; refresh hubs lazily; cache results |
| OneNote page XML quirks | Small tested writer module with recorded fixtures |
| Copilot's own OneNote grounding is unreliable | Don't depend on it (route 1) |

## 7. Go / no-go probes (before building)

P3 and P4 (Copilot's own grounding over OneNote and Loop) mean something **only on a Microsoft
365 business tenant with a Copilot licence** (Work IQ). A consumer account tests the COM
mechanics (P1) but not that grounding, so P1 is repeated on a business tenant too. P2 (linking
quality) only needs Copilot to reason, so any Copilot account works. Steps are in
`probes/README.md`.

| # | Probe | Pass if |
|---|---|---|
| P1 | **PASS on a consumer OneDrive (2026-11-12). Still to run on a business tenant.** COM round trip on a consumer and a business account: create a test notebook on OneDrive, add two pages, add an `onenote:` link between them, update an outline, read it back | Everything works from PS 5.1 without admin rights |
| P2 | Linking quality: 20 invented notes (dummy data), with and without a shortlist, through the Copilot bridge | Valid JSON every time; at least 80% of the links look sensible on review |
| P3 | **Set up 2026-11-12 14:34 UTC.** Marker `OBSN-PROBE-7Q4K` is on page "Zero-trust networking" in notebook ObsidiNote-Probe on a consumer OneDrive. The question was not sent yet because the bridge's MCP server failed with `Set-WorkSign not recognized`. Copilot grounding: put a unique marker phrase on a test page, then ask Copilot Chat (with Work IQ) about it after 1 hour and after 24 hours | Copilot finds and cites the page, which shows route 2 works |
| P4 | Same as P3 with a Loop page and a Copilot Page | Shows whether Loop is worth keeping as a read-only copy |
| P5 | *(optional)* Drive Loop over CDP: create a page, type a heading and a link | Only if the user wants Loop as a write target |
| P7 | Internal link summary: paste a SharePoint page URL and a OneDrive document URL into Copilot Chat (business tenant, Work IQ on) with the fixed summary prompt | Copilot returns the fixed page shape from the real content; a link without access gives a clear "cannot open" |
| P8 | Web link summary: the same for a public URL, with web grounding on and off | With grounding: the fixed shape. Without it: the Edge-text fallback gives the same shape |

## Sources
- [How Microsoft 365 Copilot Notebooks works](https://support.microsoft.com/en-US/Microsoft-365-Copilot/how-microsoft-365-copilot-notebooks-works): supported reference types (OneNote pages, .loop, .page) and reference limits
- [Build your first Notebook (Learn)](https://learn.microsoft.com/en-us/training/modules/copilot-chat-notebooks/3-build-your-first-notebook): OneNote pages are text-only; 20-reference figure
- [Grounding issue in Copilot Notebooks and OneNote (Q&A, Jun to Aug 2026)](https://learn.microsoft.com/en-us/answers/questions/5929747/the-grounding-issue-in-copilot-notebooks-and-oneno)
- [Request for a Loop API (Q&A, Feb 2026)](https://learn.microsoft.com/en-us/answers/questions/5760312/can-ms-provide-a-microsoft-loop-api-for-programmat)
- [Compare Loop, Copilot Pages and Copilot Notebooks](https://support.microsoft.com/en-us/microsoft-365-copilot/compare-microsoft-loop-copilot-pages-and-copilot-notebooks)
- [Loop workspaces storage and permissions](https://learn.microsoft.com/en-us/microsoft-365/loop/loop-workspaces-storage-permission?view=o365-worldwide)
- [OneNote: create pages (Graph)](https://learn.microsoft.com/en-us/graph/onenote-create-page)

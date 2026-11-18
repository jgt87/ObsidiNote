// The knowledge graph's data model: what GET /api/graph?vault=<id> | ?notebook=<id> returns.
//
// One model per source (an ObsidiNote vault, or a connected notebook loaded read only). The
// server builds it from the central index (vault) or from the derived in-memory index
// (connected notebook, FEASIBILITY.md "Connected notebooks"); the map only draws it.
//
// Rules the map relies on:
// - Every page is a real page (DESIGN.md "Every Dot Is Content"); there is no decorative data.
// - A page is drawn once, in the area of its FIRST topic id (its primary topic). Its other
//   topics are listed in the page dialog. A page without topic ids is drawn in an "Unfiled" area.
// - Topic areas come from the topic tree (parent ids); the same model always gives the same
//   picture (layout.ts).
// - Edge strength is 1..3 (the link JSON's `strength`); kind 'mention' = mentioned, not linked
//   (drawn only with the "Mentions, not linked" filter).
// - Windows PowerShell can send a one-item list as an object and an empty one as null:
//   normalizeGraph() repairs that, and clamps or drops anything it cannot draw.

import { webUrl } from '../model/links'
import { validOrigin } from '../model/origins'
import { applyLinkWeights } from './weights'

export type Strength = 1 | 2 | 3

export interface GraphTopic {
  /** Stable topic id from the index (obsn topic id). */
  id: string
  /** Display name: the last step of the path, e.g. "Zero trust". */
  name: string
  /** Full index path, steps joined by " / ", e.g. "Security / Networking / Zero trust". */
  path: string
  /** Parent topic id; null for a root topic. */
  parent: string | null
  /** Pages under this topic (including pages whose primary topic is elsewhere). */
  pageCount: number
  /** One line with the main subjects, e.g. "zero trust, identity, policies". */
  subjects: string
}

export interface GraphPage {
  /** Stable page id (obsn page id, or the OneNote page id for a connected notebook). */
  id: string
  title: string
  /** Topic ids; the first is the primary topic (where the dot is drawn). May be empty. */
  topicIds: string[]
  /** The page's type bucket, e.g. "Notes", "Web links", "Journal" (never the rollover or the year). */
  bucket: string
  /** The page's own section path as OneNote has it: "Notes 2", "Journal/2026", "Group/Section". */
  section: string
  /** Tags set by hand, in normal form (tags.ts); never set by Copilot. */
  tags: string[]
  /** Only on a regrouped model (tagView.ts): what the page belongs to inside its area, so the
   *  layout keeps the pages of one group together and names it (the page's topic). */
  group?: { id: string; name: string }
  /** Copilot's type, e.g. "concept", "link-web", "meeting"; free text for connected notebooks. */
  kind: string
  /** Distinct linked pages, either direction (weights.ts, derived from the edges). */
  links: number
  /** Pages that link to this one (weights.ts). */
  linkedFrom: number
  /** Link weight: strengths of the links to it plus half of its own (weights.ts); drives dot size. */
  weight: number
  /** Hub: among the most linked-to pages of the vault (weights.ts); thicker outline, labelled first. */
  isHub: boolean
  /** No links yet: drawn as a hollow dashed dot. */
  unlinked: boolean
  /** Where the page comes from (an id of GraphModel.sources): its area in the Sources view. */
  sourceId: string
  /** Where a page without an address came from (model/origins.ts; '' = typed or not known). */
  origin: string
  /** One-line summary from the index. */
  summary: string
  /** onenote: link that opens the page in OneNote desktop. */
  onenoteUrl: string
  /** Last modified, ISO 8601. */
  modified: string
  /** True when the page belongs to a read-only source (a connected notebook or another vault). */
  readOnly: boolean
  /** Other names for the page (index `aliases`); search and mentions match them like the title. */
  aliases: string[]
  /** Host of a link page's source ("contoso.sharepoint.com", "example.org"); '' for other pages. */
  site: string
  /** Archived (in `Archive / <bucket>`, restorable). */
  archived: boolean
  /** A link page's original http(s) address ('' otherwise): opened before OneNote. */
  url: string
  /** When a link page's source was last read, ISO ('' or absent for other pages): the filter
   *  "Link summaries older than N days" (linkUpdateRun.ts). */
  summarizedAt?: string
  /** One of ObsidiNote's own pages (it can be edited, archived and deleted); false for a page the
   *  person made in OneNote, which is listed and never changed. Absent = true (older server). */
  own?: boolean
  /** When the page was made, ISO (OneNote's own page date); '' when the server does not know it. */
  created?: string
  /** A journal day page's entries, oldest first (one page per day, 2026-11-17); [] for other pages. */
  entries?: JournalEntry[]
  /** A meeting page's series (its Teams title) and start ("yyyy-mm-ddTHH:mm" or a day), '' otherwise
   *  (2026-11-18; tests/fixtures/graph-pages.json). */
  series?: string
  meetingAt?: string
}

/** One entry of a journal day page (lib/GraphModel.psm1 ConvertTo-GraphEntries). */
export interface JournalEntry {
  /** The request reference of the Add that wrote it; names it for Undo. */
  ref: string
  /** Local time it was written, "yyyy-MM-ddTHH:mm". */
  at: string
  title: string
  summary: string
  /** The entry's own topic ids (the page's topics are the union of its entries'). */
  topicIds: string[]
  /** The pages the entry links to. */
  links: { to: string; strength: Strength; why: string }[]
}

export interface GraphEdge {
  from: string
  to: string
  strength: Strength
  /** 'link' (default) or 'mention' = the page mentions the other one but does not link it. */
  kind?: 'link' | 'mention'
  /** Why the link exists, one line (from the link JSON's `why`). */
  reason?: string
}

export interface GraphSource {
  kind: 'vault' | 'notebook'
  id: string
  name: string
  /** Connected notebooks (and vaults other than the active one) are read only. */
  readOnly: boolean
  /** Why (GET /api/graph): 'lease' = the active vault, but another ObsidiNote is its writer;
   *  'not-active' = a vault that is not the active one; 'notebook' = a connected notebook;
   *  '' = it can be changed, or a server older than the field. Wording: readOnly.ts. */
  readOnlyReason: '' | 'lease' | 'not-active' | 'notebook'
}

export interface GraphModel {
  source: GraphSource
  topics: GraphTopic[]
  pages: GraphPage[]
  edges: GraphEdge[]
  /** The page types and the section each belongs to (the active vault only; for Edit). */
  types?: { type: string; bucket: string }[]
  /** Where the pages come from, for the Sources view (lib/GraphModel.psm1): every page's sourceId is here. */
  sources?: GraphSourceArea[]
}

/** One source area of the Sources view: a Microsoft 365 app (SharePoint per site), a company
 *  service, a web site, "Other web sites", or the pages without an address. */
export interface GraphSourceArea {
  id: string
  name: string
  kind: 'm365' | 'service' | 'other-internal' | 'web' | 'other' | 'notes'
  pageCount: number
}

const READ_ONLY_REASONS = new Set(['lease', 'not-active', 'notebook'])

/** Id of the synthetic area for pages without a topic. */
export const UNFILED_ID = '__unfiled'

function asList<T>(value: T[] | T | null | undefined): T[] {
  if (value == null) return []
  return Array.isArray(value) ? value : [value]
}

function str(v: unknown, fallback = ''): string {
  return typeof v === 'string' ? v : v == null ? fallback : String(v)
}

function num(v: unknown): number {
  const n = typeof v === 'number' ? v : Number(v)
  return Number.isFinite(n) && n > 0 ? Math.floor(n) : 0
}

export function clampStrength(v: unknown): Strength {
  const n = Math.round(Number(v))
  return (n >= 3 ? 3 : n <= 1 || !Number.isFinite(n) ? 1 : 2) as Strength
}

/**
 * Makes a server answer safe to draw: lists repaired, strengths clamped, edges to unknown pages,
 * self-loops and duplicate pages dropped, topic ids that do not exist removed from pages.
 */
export function normalizeGraph(raw: unknown): GraphModel {
  const r = (raw ?? {}) as Record<string, unknown>
  const source = normalizeSource(r.source)
  const topics = normalizeTopics(r.topics)
  const pages = normalizePages(r.pages, new Set(topics.map((t) => t.id)), source.readOnly)
  const edges = normalizeEdges(r.edges, new Set(pages.map((p) => p.id)))
  // Sizes and hubs come from the edges (applyLinkWeights): one definition of both.
  applyLinkWeights(pages, edges)
  const types = normalizeTypes(r.types)
  const sources = normalizeSources(r.sources, pages, source)
  return types.length ? { source, topics, pages, edges, types, sources } : { source, topics, pages, edges, sources }
}

/** The records of a list from the server (PS 5.1 may send one record or none for a list). */
const records = (v: unknown): Record<string, unknown>[] => asList(v as unknown[]) as Record<string, unknown>[]

/** Which notebook the graph is of; a reason for read only only when it is read only. */
function normalizeSource(v: unknown): GraphSource {
  const src = (v ?? {}) as Record<string, unknown>
  const readOnly = src.readOnly === true
  return {
    kind: src.kind === 'notebook' ? 'notebook' : 'vault',
    id: str(src.id),
    name: str(src.name),
    readOnly,
    readOnlyReason: readOnly && READ_ONLY_REASONS.has(src.readOnlyReason as string) ? (src.readOnlyReason as GraphSource['readOnlyReason']) : '',
  }
}

/** The topics, once per id (the first wins); a parent that is not a topic of the graph is dropped. */
function normalizeTopics(v: unknown): GraphTopic[] {
  const ids = new Set<string>()
  const topics: GraphTopic[] = []
  for (const t of records(v)) {
    const id = str(t?.id)
    if (!id || ids.has(id)) continue
    ids.add(id)
    const name = str(t.name, id)
    topics.push({ id, name, path: str(t.path, name), parent: topicParent(t.parent), pageCount: num(t.pageCount), subjects: str(t.subjects) })
  }
  for (const t of topics) if (t.parent !== null && !ids.has(t.parent)) t.parent = null
  return topics
}

/** A topic's parent id; null for a root (no parent, or an empty one). */
const topicParent = (v: unknown): string | null => (v == null || v === '' ? null : str(v))

/** The pages, once per id (the first wins), each repaired by normalizePage. */
function normalizePages(v: unknown, topicIds: Set<string>, sourceReadOnly: boolean): GraphPage[] {
  const ids = new Set<string>()
  const pages: GraphPage[] = []
  for (const p of records(v)) {
    const id = str(p?.id)
    if (!id || ids.has(id)) continue
    ids.add(id)
    pages.push(normalizePage(p, id, topicIds, sourceReadOnly))
  }
  return pages
}

/** One page: topics that exist only, tags in their one form (lower case, once each), only a web
 *  address that may be opened, a known origin; read only when its source is. The link counts,
 *  weight and hub flag are filled in later from the edges. */
function normalizePage(p: Record<string, unknown>, id: string, topicIds: Set<string>, sourceReadOnly: boolean): GraphPage {
  return {
    id,
    title: str(p.title, '(untitled)'),
    topicIds: asList(p.topicIds as string[]).map((x) => str(x)).filter((x) => topicIds.has(x)),
    bucket: str(p.bucket),
    section: str(p.section),
    tags: [...new Set(asList(p.tags as string[]).map((x) => str(x).trim().toLowerCase()).filter(Boolean))],
    kind: str(p.kind),
    links: 0,
    linkedFrom: 0,
    weight: 0,
    isHub: false,
    unlinked: true,
    summary: str(p.summary),
    onenoteUrl: str(p.onenoteUrl),
    modified: str(p.modified),
    readOnly: p.readOnly === true || sourceReadOnly,
    aliases: asList(p.aliases as string[]).map((x) => str(x).trim()).filter(Boolean),
    site: str(p.site),
    archived: p.archived === true,
    url: webUrl(str(p.url)),
    summarizedAt: str(p.summarizedAt),
    own: p.own !== false,
    sourceId: str(p.sourceId),
    origin: validOrigin(p.origin),
    created: str(p.created),
    entries: normalizeEntries(p.entries),
    series: str(p.series),
    meetingAt: str(p.meetingAt),
  }
}

/** A day page's entries: lists repaired, strengths clamped, an entry without a title or time dropped. */
function normalizeEntries(v: unknown): JournalEntry[] {
  return records(v)
    .map((e) => ({
      ref: str(e.ref),
      at: str(e.at),
      title: str(e.title),
      summary: str(e.summary),
      topicIds: asList(e.topicIds as string[]).map((x) => str(x)).filter(Boolean),
      links: records(e.links)
        .map((l) => ({ to: str(l.to), strength: clampStrength(l.strength), why: str(l.why) }))
        .filter((l) => l.to),
    }))
    .filter((e) => e.title && e.at)
}

/** The edges between known pages, no self-loops, once per kind and direction (the first wins),
 *  strength clamped to 1-3; anything but a mention is a link. */
function normalizeEdges(v: unknown, pageIds: Set<string>): GraphEdge[] {
  const seen = new Set<string>()
  const edges: GraphEdge[] = []
  for (const e of records(v)) {
    const ends = edgeEnds(e, pageIds)
    if (!ends) continue
    const { from, to } = ends
    const kind = e.kind === 'mention' ? 'mention' : 'link'
    const key = `${kind}:${from}>${to}`
    if (seen.has(key)) continue
    seen.add(key)
    const edge: GraphEdge = { from, to, strength: clampStrength(e.strength), kind }
    if (e.reason) edge.reason = str(e.reason)
    edges.push(edge)
  }
  return edges
}

/** An edge's two pages; null when either is not a page of the graph, or both are the same page. */
function edgeEnds(e: Record<string, unknown> | null | undefined, pageIds: Set<string>): { from: string; to: string } | null {
  const from = str(e?.from)
  const to = str(e?.to)
  return pageIds.has(from) && pageIds.has(to) && from !== to ? { from, to } : null
}

/** The page types the Edit form offers (only those with a type and a section). */
function normalizeTypes(v: unknown): { type: string; bucket: string }[] {
  return records(v)
    .map((t) => ({ type: str(t?.type), bucket: str(t?.bucket) }))
    .filter((t) => t.type && t.bucket)
}

const SOURCE_KINDS = new Set<GraphSourceArea['kind']>(['m365', 'service', 'other-internal', 'web', 'other', 'notes'])

/** The sources list, repaired: one entry per id, counts from the pages, and every page's sourceId in
 *  it (a page without one, or with an unknown one, goes to the notes area). */
function normalizeSources(raw: unknown, pages: GraphPage[], source: GraphSource): GraphSourceArea[] {
  const notes = notesArea(source)
  const byId = sourceAreasById(raw)
  for (const p of pages) {
    if (!p.sourceId || !byId.has(p.sourceId)) {
      if (!byId.has(notes.id)) byId.set(notes.id, { ...notes })
      p.sourceId = notes.id
    }
    byId.get(p.sourceId)!.pageCount++
  }
  return [...byId.values()].filter((s) => s.pageCount > 0)
}

/** The area of pages without an address: a connected notebook's OneNote pages, or the vault's own
 *  notes. */
function notesArea(source: GraphSource): GraphSourceArea {
  return source.kind === 'notebook'
    ? { id: 'onenote', name: 'OneNote pages', kind: 'notes', pageCount: 0 }
    : { id: 'obsidinote', name: 'ObsidiNote notes', kind: 'notes', pageCount: 0 }
}

/** The server's source areas by id, once per id (the first wins), an unknown kind as 'other', the
 *  counts at 0 (they are counted from the pages). */
function sourceAreasById(raw: unknown): Map<string, GraphSourceArea> {
  const byId = new Map<string, GraphSourceArea>()
  for (const s of records(raw)) {
    const id = str(s?.id)
    if (!id || byId.has(id)) continue
    const kind = SOURCE_KINDS.has(s.kind as GraphSourceArea['kind']) ? (s.kind as GraphSourceArea['kind']) : 'other'
    byId.set(id, { id, name: str(s.name, id), kind, pageCount: 0 })
  }
  return byId
}

/** Primary topic of a page (the area it is drawn in). */
export function primaryTopic(page: GraphPage): string {
  return page.topicIds[0] ?? UNFILED_ID
}

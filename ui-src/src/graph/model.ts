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
  const src = (r.source ?? {}) as Record<string, unknown>
  const source: GraphSource = {
    kind: src.kind === 'notebook' ? 'notebook' : 'vault',
    id: str(src.id),
    name: str(src.name),
    readOnly: src.readOnly === true,
    readOnlyReason: src.readOnly === true && READ_ONLY_REASONS.has(src.readOnlyReason as string) ? (src.readOnlyReason as GraphSource['readOnlyReason']) : '',
  }
  const topicIds = new Set<string>()
  const topics: GraphTopic[] = []
  for (const t of asList(r.topics as unknown[]) as Record<string, unknown>[]) {
    const id = str(t?.id)
    if (!id || topicIds.has(id)) continue
    topicIds.add(id)
    const name = str(t.name, id)
    topics.push({ id, name, path: str(t.path, name), parent: t.parent == null || t.parent === '' ? null : str(t.parent), pageCount: num(t.pageCount), subjects: str(t.subjects) })
  }
  for (const t of topics) if (t.parent !== null && !topicIds.has(t.parent)) t.parent = null

  const pageIds = new Set<string>()
  const pages: GraphPage[] = []
  for (const p of asList(r.pages as unknown[]) as Record<string, unknown>[]) {
    const id = str(p?.id)
    if (!id || pageIds.has(id)) continue
    pageIds.add(id)
    pages.push({
      id,
      title: str(p.title, '(untitled)'),
      topicIds: asList(p.topicIds as string[]).map((x) => str(x)).filter((x) => topicIds.has(x)),
      bucket: str(p.bucket),
      section: str(p.section),
      tags: [...new Set(asList(p.tags as string[]).map((x) => str(x).trim().toLowerCase()).filter(Boolean))],
      kind: str(p.kind),
      // Set from the edges below (applyLinkWeights): one definition of size and hubs.
      links: 0,
      linkedFrom: 0,
      weight: 0,
      isHub: false,
      unlinked: true,
      summary: str(p.summary),
      onenoteUrl: str(p.onenoteUrl),
      modified: str(p.modified),
      readOnly: p.readOnly === true || source.readOnly,
      aliases: asList(p.aliases as string[]).map((x) => str(x).trim()).filter(Boolean),
      site: str(p.site),
      archived: p.archived === true,
      url: webUrl(str(p.url)),
      summarizedAt: str(p.summarizedAt),
      sourceId: str(p.sourceId),
      origin: validOrigin(p.origin),
    })
  }

  const seen = new Set<string>()
  const edges: GraphEdge[] = []
  for (const e of asList(r.edges as unknown[]) as Record<string, unknown>[]) {
    const from = str(e?.from)
    const to = str(e?.to)
    if (!pageIds.has(from) || !pageIds.has(to) || from === to) continue
    const kind = e.kind === 'mention' ? 'mention' : 'link'
    const key = `${kind}:${from}>${to}`
    if (seen.has(key)) continue
    seen.add(key)
    const edge: GraphEdge = { from, to, strength: clampStrength(e.strength), kind }
    if (e.reason) edge.reason = str(e.reason)
    edges.push(edge)
  }
  applyLinkWeights(pages, edges)
  const types = (asList(r.types as unknown[]) as Record<string, unknown>[])
    .map((t) => ({ type: str(t?.type), bucket: str(t?.bucket) }))
    .filter((t) => t.type && t.bucket)
  const sources = normalizeSources(r.sources, pages, source)
  return types.length ? { source, topics, pages, edges, types, sources } : { source, topics, pages, edges, sources }
}

const SOURCE_KINDS = new Set<GraphSourceArea['kind']>(['m365', 'service', 'other-internal', 'web', 'other', 'notes'])

/** The sources list, repaired: one entry per id, counts from the pages, and every page's sourceId in
 *  it (a page without one, or with an unknown one, goes to the notes area). */
function normalizeSources(raw: unknown, pages: GraphPage[], source: GraphSource): GraphSourceArea[] {
  const notes: GraphSourceArea = source.kind === 'notebook' ? { id: 'onenote', name: 'OneNote pages', kind: 'notes', pageCount: 0 } : { id: 'obsidinote', name: 'ObsidiNote notes', kind: 'notes', pageCount: 0 }
  const byId = new Map<string, GraphSourceArea>()
  for (const s of asList(raw as unknown[]) as Record<string, unknown>[]) {
    const id = str(s?.id)
    if (!id || byId.has(id)) continue
    const kind = SOURCE_KINDS.has(s.kind as GraphSourceArea['kind']) ? (s.kind as GraphSourceArea['kind']) : 'other'
    byId.set(id, { id, name: str(s.name, id), kind, pageCount: 0 })
  }
  for (const p of pages) {
    if (!p.sourceId || !byId.has(p.sourceId)) {
      if (!byId.has(notes.id)) byId.set(notes.id, { ...notes })
      p.sourceId = notes.id
    }
    byId.get(p.sourceId)!.pageCount++
  }
  return [...byId.values()].filter((s) => s.pageCount > 0)
}

/** Primary topic of a page (the area it is drawn in). */
export function primaryTopic(page: GraphPage): string {
  return page.topicIds[0] ?? UNFILED_ID
}

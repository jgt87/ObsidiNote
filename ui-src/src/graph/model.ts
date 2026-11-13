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
  /** The page's section = its type bucket, e.g. "Notes", "Web links", "Meetings". */
  bucket: string
  /** Copilot's type, e.g. "concept", "link-web", "meeting"; free text for connected notebooks. */
  kind: string
  /** Number of links (in + out); drives dot size. */
  links: number
  /** Hub (index/MOC page or high centrality): drawn bigger, labelled when nothing is focused. */
  isHub: boolean
  /** No links yet: drawn as a hollow dashed dot. */
  unlinked: boolean
  /** One-line summary from the index. */
  summary: string
  /** onenote: link that opens the page in OneNote desktop. */
  onenoteUrl: string
  /** Last modified, ISO 8601. */
  modified: string
  /** True when the page belongs to a read-only source (a connected notebook or another vault). */
  readOnly: boolean
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
}

export interface GraphModel {
  source: GraphSource
  topics: GraphTopic[]
  pages: GraphPage[]
  edges: GraphEdge[]
}

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
      kind: str(p.kind),
      links: num(p.links),
      isHub: p.isHub === true,
      unlinked: p.unlinked === true,
      summary: str(p.summary),
      onenoteUrl: str(p.onenoteUrl),
      modified: str(p.modified),
      readOnly: p.readOnly === true || source.readOnly,
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
  return { source, topics, pages, edges }
}

/** Primary topic of a page (the area it is drawn in). */
export function primaryTopic(page: GraphPage): string {
  return page.topicIds[0] ?? UNFILED_ID
}

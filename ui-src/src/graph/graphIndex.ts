// Lookups the map and the page dialog need, derived once per model. Pure.

import { primaryTopic, UNFILED_ID, type GraphEdge, type GraphModel, type GraphPage, type GraphTopic } from './model'

export interface GraphIndex {
  model: GraphModel
  pageById: Map<string, GraphPage>
  topicById: Map<string, GraphTopic>
  /** Links going out of a page (kind 'link'), strongest first. */
  out: Map<string, GraphEdge[]>
  /** Links coming into a page (kind 'link'), strongest first. */
  in: Map<string, GraphEdge[]>
  /** Mentions, not linked, in either direction. */
  mentions: Map<string, GraphEdge[]>
  /** Directly linked pages (either direction), strongest link first, then by title. */
  neighbours: Map<string, string[]>
  /** Strongest link strength between two pages, keyed "a|b" with a < b. */
  strengthBetween: Map<string, number>
  /** Pages per primary topic area (UNFILED_ID for pages without a topic). */
  pagesByArea: Map<string, string[]>
  linkCount: number
  mentionCount: number
}

export function pairKey(a: string, b: string): string {
  return a < b ? `${a}|${b}` : `${b}|${a}`
}

function push<K, V>(m: Map<K, V[]>, k: K, v: V): void {
  const list = m.get(k)
  if (list) list.push(v)
  else m.set(k, [v])
}

export function buildIndex(model: GraphModel): GraphIndex {
  const pageById = new Map(model.pages.map((p) => [p.id, p]))
  const topicById = new Map(model.topics.map((t) => [t.id, t]))
  const out = new Map<string, GraphEdge[]>()
  const inn = new Map<string, GraphEdge[]>()
  const mentions = new Map<string, GraphEdge[]>()
  const strengthBetween = new Map<string, number>()
  let linkCount = 0
  let mentionCount = 0
  for (const e of model.edges) {
    if (e.kind === 'mention') {
      mentionCount++
      push(mentions, e.from, e)
      push(mentions, e.to, e)
      continue
    }
    linkCount++
    push(out, e.from, e)
    push(inn, e.to, e)
    const k = pairKey(e.from, e.to)
    strengthBetween.set(k, Math.max(strengthBetween.get(k) ?? 0, e.strength))
  }
  // Ties by ids, so the order never depends on the order the server sent the edges in.
  const byStrength = (a: GraphEdge, b: GraphEdge) => b.strength - a.strength || (`${a.from}>${a.to}` < `${b.from}>${b.to}` ? -1 : 1)
  for (const m of [out, inn, mentions]) for (const list of m.values()) list.sort(byStrength)

  const neighbours = new Map<string, string[]>()
  for (const p of model.pages) {
    const ids = new Set<string>()
    for (const e of out.get(p.id) ?? []) ids.add(e.to)
    for (const e of inn.get(p.id) ?? []) ids.add(e.from)
    const list = [...ids]
    list.sort((a, b) => {
      const s = (strengthBetween.get(pairKey(p.id, b)) ?? 0) - (strengthBetween.get(pairKey(p.id, a)) ?? 0)
      if (s !== 0) return s
      const ta = pageById.get(a)!.title
      const tb = pageById.get(b)!.title
      return ta < tb ? -1 : ta > tb ? 1 : a < b ? -1 : 1
    })
    neighbours.set(p.id, list)
  }

  const pagesByArea = new Map<string, string[]>()
  for (const p of model.pages) push(pagesByArea, primaryTopic(p), p.id)

  return { model, pageById, topicById, out, in: inn, mentions, neighbours, strengthBetween, pagesByArea, linkCount, mentionCount }
}

/** "Index › Security › Networking › Zero trust" for a page (its primary topic) or a topic id. */
export function indexPath(index: GraphIndex, topicId: string): string {
  if (topicId === UNFILED_ID) return 'Index › Unfiled'
  const t = index.topicById.get(topicId)
  if (!t) return 'Index'
  return ['Index', ...t.path.split(' / ').filter(Boolean)].join(' › ')
}

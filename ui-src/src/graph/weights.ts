// How much a page matters on the map, from its links (operator, 2026-11-14). Pure; the one
// definition: the server sends the edges, normalizeGraph() derives these numbers from them.
//
// - Being linked TO is what counts: Copilot gives every new page up to 8 links of its own at once,
//   so a page's own (outgoing) links count half. Otherwise a fresh page with five proposed links
//   was a hub on its first day while a page four others link to stayed small.
// - Strength counts: a core link (3) weighs three loose ones (1).
// - A page that links back counts once as a neighbour (links), not twice.
// - Hubs are relative to the vault: the top HUB_SHARE of pages by weight that at least
//   HUB_MIN_IN pages link to. A fixed "5 links" made no hubs in a small vault and dozens in a big one.

import type { GraphEdge, GraphPage } from './model'

/** Share of the pages that can be hubs. */
export const HUB_SHARE = 0.05
/** A hub is linked to by at least this many pages. */
export const HUB_MIN_IN = 3
/** What a page's own links weigh against links to it. */
export const OUT_SHARE = 0.5

export interface LinkWeight {
  /** Distinct linked pages, either direction. */
  links: number
  /** Pages that link to this one. */
  linkedFrom: number
  /** Sum of the strengths of the links to it, plus OUT_SHARE times those of its own links. */
  weight: number
}

/** Weights of every page id from the links (mentions do not count). */
export function linkWeights(pageIds: string[], edges: GraphEdge[]): Map<string, LinkWeight> {
  const w = new Map<string, LinkWeight>(pageIds.map((id) => [id, { links: 0, linkedFrom: 0, weight: 0 }]))
  const near = new Map<string, Set<string>>(pageIds.map((id) => [id, new Set<string>()]))
  const seen = new Set<string>()
  for (const e of edges) {
    if (e.kind === 'mention' || e.from === e.to) continue
    const from = w.get(e.from)
    const to = w.get(e.to)
    if (!from || !to) continue
    const key = `${e.from}>${e.to}`
    if (seen.has(key)) continue
    seen.add(key)
    to.linkedFrom++
    to.weight += e.strength
    from.weight += e.strength * OUT_SHARE
    near.get(e.from)!.add(e.to)
    near.get(e.to)!.add(e.from)
  }
  for (const [id, v] of w) v.links = near.get(id)!.size
  return w
}

/** The hub pages: the top HUB_SHARE by weight with at least HUB_MIN_IN pages linking to them.
 *  Pages tied with the last place are in too, unless that more than doubles the share (forty pages
 *  that each have three links to them are not forty hubs); then only those above the tie are. */
export function hubIds(weights: Map<string, LinkWeight>): Set<string> {
  const all = [...weights.values()].map((v) => v.weight).sort((a, b) => b - a)
  const out = new Set<string>()
  if (!all.length) return out
  const k = Math.max(1, Math.ceil(all.length * HUB_SHARE))
  const threshold = all[Math.min(k, all.length) - 1]
  const strict = all.filter((w) => w >= threshold).length > 2 * k
  for (const [id, v] of weights) {
    const high = strict ? v.weight > threshold : v.weight >= threshold
    if (high && v.weight > 0 && v.linkedFrom >= HUB_MIN_IN) out.add(id)
  }
  return out
}

/** Sets links, linkedFrom, weight, isHub and unlinked on every page from the edges. */
export function applyLinkWeights(pages: GraphPage[], edges: GraphEdge[]): void {
  const weights = linkWeights(
    pages.map((p) => p.id),
    edges,
  )
  const hubs = hubIds(weights)
  for (const p of pages) {
    const v = weights.get(p.id)!
    p.links = v.links
    p.linkedFrom = v.linkedFrom
    p.weight = v.weight
    p.isHub = hubs.has(p.id)
    p.unlinked = v.links === 0
  }
}

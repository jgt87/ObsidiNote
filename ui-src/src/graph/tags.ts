// Tags: marks a person sets by hand to group pages that nothing else relates (operator,
// 2026-11-15). Copilot never sets them. Pure (tests: tags.test.ts, on tests/fixtures/tags.json,
// which the server's tag function is tested against too: change all three together).

import type { GraphPage } from './model'

export const TAG_MAX_LENGTH = 40
export const TAGS_PER_PAGE = 12

export type TagResult = { ok: true; tag: string } | { ok: false; error: string }

/** The normal form of one tag: trimmed, inner spaces collapsed, lower case; or why it is refused. */
export function normalizeTag(text: string): TagResult {
  if (/[\r\n]/.test(text)) return { ok: false, error: 'A tag is one line.' }
  const tag = text.trim().replace(/\s+/g, ' ').toLowerCase()
  if (!tag) return { ok: false, error: 'Type a tag first.' }
  if (tag.length > TAG_MAX_LENGTH) return { ok: false, error: `A tag is at most ${TAG_MAX_LENGTH} characters.` }
  if (/[",:]/.test(tag)) return { ok: false, error: 'A tag cannot hold a comma, a colon or a double quote.' }
  // eslint-disable-next-line no-control-regex
  if (/[\u0000-\u001f]/.test(tag)) return { ok: false, error: 'A tag cannot hold control characters.' }
  return { ok: true, tag }
}

/** A list of tags in normal form (duplicates go, the first stays), or why it is refused. */
export function normalizeTags(list: string[]): { ok: true; tags: string[] } | { ok: false; error: string } {
  const out: string[] = []
  for (const t of list) {
    const r = normalizeTag(t)
    if (!r.ok) return r
    if (!out.includes(r.tag)) out.push(r.tag)
  }
  if (out.length > TAGS_PER_PAGE) return { ok: false, error: `A page has at most ${TAGS_PER_PAGE} tags.` }
  return { ok: true, tags: out }
}

export interface TagCount {
  name: string
  count: number
}

/** Every tag in use with the number of pages that carry it, by name. */
export function tagCounts(pages: Pick<GraphPage, 'tags' | 'archived'>[], withArchived = true): TagCount[] {
  const n = new Map<string, number>()
  for (const p of pages) {
    if (p.archived && !withArchived) continue
    for (const t of p.tags) n.set(t, (n.get(t) ?? 0) + 1)
  }
  return [...n].map(([name, count]) => ({ name, count })).sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0))
}

/** Tags to offer while typing: those in use that hold the typed text and the page does not have
 *  yet, starting matches first. Keeps "licensing" and "licences" from both coming into being. */
export function suggestTags(all: TagCount[], typed: string, has: string[]): string[] {
  const t = typed.trim().replace(/\s+/g, ' ').toLowerCase()
  const rest = all.map((a) => a.name).filter((n) => !has.includes(n) && n.includes(t))
  return [...rest.filter((n) => n.startsWith(t)), ...rest.filter((n) => !n.startsWith(t))].slice(0, 8)
}

/** The search query that shows one tag's pages: tag:licensing or tag:"follow up". */
export function tagQuery(tag: string): string {
  return /\s/.test(tag) ? `tag:"${tag}"` : `tag:${tag}`
}

/** The tag a query asks for when it is exactly one tag filter (so the map's tag picker can show it). */
export function tagOfQuery(query: string): string {
  const m = /^\s*tag:(?:"([^"]+)"|(\S+))\s*$/i.exec(query)
  return m ? (m[1] ?? m[2]).toLowerCase() : ''
}

/**
 * The lines that join the pages of one tag on the map into one group: a minimum spanning tree over
 * their positions (each page joined to its nearest already-joined page), so n pages get n - 1 short
 * lines instead of a line between every pair. Deterministic: starts at the first id in order.
 */
export function joinLines(points: { id: string; x: number; y: number }[], max = 200): [string, string][] {
  const pts = [...points].sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0)).slice(0, max)
  if (pts.length < 2) return []
  const inTree = [pts[0]]
  const rest = pts.slice(1)
  const out: [string, string][] = []
  while (rest.length) {
    let best = { d: Infinity, i: 0, from: inTree[0] }
    for (let i = 0; i < rest.length; i++) {
      for (const t of inTree) {
        const d = (rest[i].x - t.x) ** 2 + (rest[i].y - t.y) ** 2
        if (d < best.d) best = { d, i, from: t }
      }
    }
    const [next] = rest.splice(best.i, 1)
    out.push([best.from.id, next.id])
    inTree.push(next)
  }
  return out
}

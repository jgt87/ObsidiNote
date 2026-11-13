// Graph focus: which pages the map and the list show. Pure (tests: filters.test.ts).
//
// Filters hide pages; they never change the layout, so dots never jump. A hidden page has no
// dot, no link line and no place in arrow-key navigation; the list gets the same set.
// - types: page types (the page's bucket, see typeOf); empty = every type.
// - topics: topic ids; a topic includes its subtopics; UNFILED_ID = pages without a topic.
// - unlinkedOnly: only pages without links.
// - showArchived: archived pages are hidden unless this is on.
// - focus: the page plus the pages within `depth` link steps (links only, not mentions). The
//   steps are counted on the whole graph; the other filters then apply to the result, except
//   that the focused page itself always stays visible.

import type { GraphIndex } from './graphIndex'
import { UNFILED_ID, type GraphPage } from './model'

export type FocusDepth = 1 | 2

export interface GraphFilter {
  types: Set<string>
  topics: Set<string>
  unlinkedOnly: boolean
  showArchived: boolean
  focus: { id: string; depth: FocusDepth } | null
}

export function emptyFilter(): GraphFilter {
  return { types: new Set(), topics: new Set(), unlinkedOnly: false, showArchived: false, focus: null }
}

/** True when the filter hides anything beyond archived pages (the default). */
export function isFilterActive(f: GraphFilter): boolean {
  return f.types.size > 0 || f.topics.size > 0 || f.unlinkedOnly || f.showArchived || f.focus !== null
}

/**
 * A page's type for the filter: its bucket (section) without the archive prefix, the rollover
 * number or the year ("Archive / Notes 2" -> "Notes", "Journal / 2026" -> "Journal"); the
 * page kind when there is no bucket; "Other" when there is neither.
 */
export function typeOf(page: GraphPage): string {
  let parts = page.bucket.split('/').map((s) => s.trim()).filter(Boolean)
  if (parts.length > 1 && parts[0].toLowerCase() === 'archive') parts = parts.slice(1)
  const first = (parts[0] ?? '').replace(/\s+\d+$/, '').trim()
  return first || page.kind.trim() || 'Other'
}

/** Topic id -> that topic and all its subtopics (ids). */
export function topicDescendants(index: GraphIndex): Map<string, Set<string>> {
  const children = new Map<string, string[]>()
  for (const t of index.model.topics) {
    if (t.parent === null) continue
    const list = children.get(t.parent)
    if (list) list.push(t.id)
    else children.set(t.parent, [t.id])
  }
  const out = new Map<string, Set<string>>()
  for (const t of index.model.topics) {
    const set = new Set<string>()
    const stack = [t.id]
    while (stack.length) {
      const id = stack.pop()!
      if (set.has(id)) continue // a broken tree with a cycle must not hang the map
      set.add(id)
      for (const c of children.get(id) ?? []) stack.push(c)
    }
    out.set(t.id, set)
  }
  return out
}

/** The page plus every page within `depth` link steps (either direction). */
export function focusNeighbourhood(index: GraphIndex, id: string, depth: FocusDepth): Set<string> {
  const seen = new Set<string>()
  if (!index.pageById.has(id)) return seen
  seen.add(id)
  let ring = [id]
  for (let step = 0; step < depth; step++) {
    const next: string[] = []
    for (const p of ring) {
      for (const n of index.neighbours.get(p) ?? []) {
        if (seen.has(n)) continue
        seen.add(n)
        next.push(n)
      }
    }
    ring = next
  }
  return seen
}

function underTopics(page: GraphPage, wanted: Set<string>): boolean {
  if (!page.topicIds.length) return wanted.has(UNFILED_ID)
  return page.topicIds.some((t) => wanted.has(t))
}

/** Every topic id the selected topics stand for (each with its subtopics), plus UNFILED_ID when chosen. */
function expandTopics(index: GraphIndex, topics: Set<string>): Set<string> {
  const desc = topicDescendants(index)
  const wanted = new Set<string>()
  for (const t of topics) {
    if (t === UNFILED_ID) wanted.add(t)
    for (const d of desc.get(t) ?? []) wanted.add(d)
  }
  return wanted
}

/** The ids of the pages that stay visible, in model order. */
export function visiblePageIds(index: GraphIndex, f: GraphFilter): Set<string> {
  const wanted = f.topics.size ? expandTopics(index, f.topics) : null
  const near = f.focus ? focusNeighbourhood(index, f.focus.id, f.focus.depth) : null
  const shown = new Set<string>()
  for (const p of index.model.pages) {
    if (near && p.id === f.focus!.id) {
      shown.add(p.id)
      continue
    }
    if (near && !near.has(p.id)) continue
    if (p.archived && !f.showArchived) continue
    if (f.types.size && !f.types.has(typeOf(p))) continue
    if (wanted && !underTopics(p, wanted)) continue
    if (f.unlinkedOnly && !isUnlinked(index, p)) continue
    shown.add(p.id)
  }
  return shown
}

/** No links in either direction (mentions do not count). */
export function isUnlinked(index: GraphIndex, p: GraphPage): boolean {
  return p.unlinked || (index.neighbours.get(p.id)?.length ?? 0) === 0
}

export interface TypeOption {
  key: string
  count: number
}

export interface TopicOption {
  id: string
  name: string
  path: string
  /** 0 for a root topic. */
  depth: number
  /** Pages under this topic or its subtopics (any of their topics, not only the primary one). */
  count: number
}

/**
 * The choices in the filter panel with their page counts. Counts leave archived pages out unless
 * they are shown, so a count is what ticking the box would show (before the other filters).
 */
export function filterOptions(index: GraphIndex, showArchived: boolean): { types: TypeOption[]; topics: TopicOption[] } {
  const pages = index.model.pages.filter((p) => showArchived || !p.archived)
  const typeCount = new Map<string, number>()
  for (const p of pages) {
    const k = typeOf(p)
    typeCount.set(k, (typeCount.get(k) ?? 0) + 1)
  }
  const types = [...typeCount].map(([key, count]) => ({ key, count })).sort((a, b) => (a.key < b.key ? -1 : a.key > b.key ? 1 : 0))

  const desc = topicDescendants(index)
  const byId = index.topicById
  const depthOf = (id: string): number => {
    let d = 0
    let t = byId.get(id)
    const guard = new Set<string>()
    while (t && t.parent !== null && !guard.has(t.id)) {
      guard.add(t.id)
      d++
      t = byId.get(t.parent)
    }
    return d
  }
  const topics: TopicOption[] = index.model.topics
    .map((t) => {
      const ids = desc.get(t.id)!
      let count = 0
      for (const p of pages) if (p.topicIds.some((x) => ids.has(x))) count++
      return { id: t.id, name: t.name, path: t.path, depth: depthOf(t.id), count }
    })
    .sort((a, b) => (a.path < b.path ? -1 : a.path > b.path ? 1 : 0))
  const unfiled = pages.filter((p) => !p.topicIds.length).length
  if (unfiled) topics.push({ id: UNFILED_ID, name: 'Unfiled', path: 'Unfiled', depth: 0, count: unfiled })
  return { types, topics }
}

/** Archived pages the current filter hides because "Show archived" is off. */
export function archivedHidden(index: GraphIndex, f: GraphFilter): number {
  if (f.showArchived) return 0
  let n = 0
  for (const p of index.model.pages) if (p.archived) n++
  return n
}

/** Drops choices that no longer exist (after a reload of the model); keeps the rest. */
export function pruneFilter(index: GraphIndex, f: GraphFilter): GraphFilter {
  const types = new Set(index.model.pages.map(typeOf))
  const nextTypes = new Set([...f.types].filter((t) => types.has(t)))
  const nextTopics = new Set([...f.topics].filter((t) => t === UNFILED_ID || index.topicById.has(t)))
  const focus = f.focus && index.pageById.has(f.focus.id) ? f.focus : null
  if (nextTypes.size === f.types.size && nextTopics.size === f.topics.size && focus === f.focus) return f
  return { ...f, types: nextTypes, topics: nextTopics, focus }
}

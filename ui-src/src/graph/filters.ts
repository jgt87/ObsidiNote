// Graph focus: which pages the map and the list show. Pure (tests: filters.test.ts).
//
// Filters hide pages; they never change the layout, so dots never jump. A hidden page has no
// dot, no link line and no place in arrow-key navigation; the list gets the same set.
// - types: page types (the page's bucket, see typeOf); empty = every type.
// - topics: topic ids; a topic includes its subtopics; UNFILED_ID = pages without a topic.
// - tags: tags set by hand; a page with any of the chosen tags stays; empty = no tag filter.
// - unlinkedOnly: only pages without links.
// - duplicatesOnly: only pages that share a title or an alias with another page (duplicates.ts).
// - showArchived: archived pages are hidden unless this is on.
// - staleBefore: only link pages whose summary was read before this ISO time, or never
//   (linkUpdateRun.ts isStale); null = no such filter. Set from the vault's linkStaleDays.
// - focus: the page plus the pages within `depth` link steps (links only, not mentions). The
//   steps are counted on the whole graph; the other filters then apply to the result, except
//   that the focused page itself always stays visible.

import type { GraphIndex } from './graphIndex'
import { UNFILED_ID, type GraphPage } from './model'
import { duplicateIds } from './duplicates'
import { isStale } from './linkUpdateRun'
import { tagCounts, type TagCount } from './tags'

export type FocusDepth = 1 | 2

export interface GraphFilter {
  types: Set<string>
  topics: Set<string>
  tags: Set<string>
  unlinkedOnly: boolean
  duplicatesOnly: boolean
  showArchived: boolean
  staleBefore: string | null
  focus: { id: string; depth: FocusDepth } | null
}

export function emptyFilter(): GraphFilter {
  return { types: new Set(), topics: new Set(), tags: new Set(), unlinkedOnly: false, duplicatesOnly: false, showArchived: false, staleBefore: null, focus: null }
}

/** The active choices in words, for the one-line summary under the map ("type: note · without
 *  links"); topic ids are named by `topicName`. The focus is not one of them (it has its own part). */
export function filterParts(f: GraphFilter, topicName: (id: string) => string): string[] {
  const parts: string[] = []
  if (f.types.size) parts.push(`type: ${[...f.types].join(', ')}`)
  if (f.topics.size) parts.push(`topic: ${[...f.topics].map(topicName).join(', ')}`)
  if (f.tags.size) parts.push(`tag: ${[...f.tags].join(', ')}`)
  if (f.unlinkedOnly) parts.push('without links')
  if (f.duplicatesOnly) parts.push('possible duplicates (open one to link, edit or archive it)')
  if (f.staleBefore !== null) parts.push('old link summaries (select them in the List to update)')
  if (f.showArchived) parts.push('archived shown')
  return parts
}

/** True when the filter hides anything beyond archived pages (the default). */
export function isFilterActive(f: GraphFilter): boolean {
  return f.types.size > 0 || f.topics.size > 0 || f.tags.size > 0 || f.unlinkedOnly || f.duplicatesOnly || f.showArchived || f.staleBefore !== null || f.focus !== null
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
  for (let step = 0; step < depth; step++) ring = stepOut(index, ring, seen)
  return seen
}

/** The pages one link step beyond `ring` that are not in `seen` yet, in order; adds them to `seen`. */
function stepOut(index: GraphIndex, ring: string[], seen: Set<string>): string[] {
  const next: string[] = []
  for (const p of ring) {
    for (const n of index.neighbours.get(p) ?? []) {
      if (seen.has(n)) continue
      seen.add(n)
      next.push(n)
    }
  }
  return next
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

type PageCheck = (p: GraphPage) => boolean

/** One check per active choice of the filter (the focus aside); a page must pass all of them.
 *  Each check is pure, so their order does not change which pages pass. */
function pageChecks(index: GraphIndex, f: GraphFilter): PageCheck[] {
  const checks: PageCheck[] = []
  if (!f.showArchived) checks.push((p) => !p.archived)
  if (f.types.size) checks.push((p) => f.types.has(typeOf(p)))
  if (f.topics.size) {
    const wanted = expandTopics(index, f.topics)
    checks.push((p) => underTopics(p, wanted))
  }
  if (f.tags.size) checks.push((p) => p.tags.some((t) => f.tags.has(t)))
  if (f.unlinkedOnly) checks.push((p) => isUnlinked(index, p))
  if (f.duplicatesOnly) {
    const dups = duplicateIds(index.model.pages, f.showArchived)
    checks.push((p) => dups.has(p.id))
  }
  const cutOff = f.staleBefore
  if (cutOff !== null) checks.push((p) => isStale(p, cutOff))
  return checks
}

/** The ids of the pages that stay visible, in model order. */
export function visiblePageIds(index: GraphIndex, f: GraphFilter): Set<string> {
  const near = f.focus ? focusNeighbourhood(index, f.focus.id, f.focus.depth) : null
  const focusId = f.focus?.id ?? null
  const checks = pageChecks(index, f)
  const shown = new Set<string>()
  for (const p of index.model.pages) {
    // The focused page itself stays whatever the other choices say.
    if (p.id === focusId || ((!near || near.has(p.id)) && checks.every((c) => c(p)))) shown.add(p.id)
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
export function filterOptions(index: GraphIndex, showArchived: boolean): { types: TypeOption[]; topics: TopicOption[]; tags: TagCount[] } {
  const pages = index.model.pages.filter((p) => showArchived || !p.archived)
  return { types: typeOptions(pages), topics: topicOptions(index, pages), tags: tagCounts(pages) }
}

/** Code-unit order (not the locale's), as the panel has always listed them. */
function byText(a: string, b: string): number {
  return a < b ? -1 : a > b ? 1 : 0
}

function typeOptions(pages: GraphPage[]): TypeOption[] {
  const typeCount = new Map<string, number>()
  for (const p of pages) {
    const k = typeOf(p)
    typeCount.set(k, (typeCount.get(k) ?? 0) + 1)
  }
  return [...typeCount].map(([key, count]) => ({ key, count })).sort((a, b) => byText(a.key, b.key))
}

/** Every topic by path with its page count, then Unfiled when some pages have no topic. */
function topicOptions(index: GraphIndex, pages: GraphPage[]): TopicOption[] {
  const desc = topicDescendants(index)
  const topics: TopicOption[] = index.model.topics
    .map((t) => {
      const ids = desc.get(t.id)!
      let count = 0
      for (const p of pages) if (p.topicIds.some((x) => ids.has(x))) count++
      return { id: t.id, name: t.name, path: t.path, depth: topicDepth(index, t.id), count }
    })
    .sort((a, b) => byText(a.path, b.path))
  const unfiled = pages.filter((p) => !p.topicIds.length).length
  if (unfiled) topics.push({ id: UNFILED_ID, name: 'Unfiled', path: 'Unfiled', depth: 0, count: unfiled })
  return topics
}

/** Steps from the topic up to its root; 0 for a root. A cycle in a broken tree stops the walk. */
function topicDepth(index: GraphIndex, id: string): number {
  let d = 0
  let t = index.topicById.get(id)
  const guard = new Set<string>()
  while (t && t.parent !== null && !guard.has(t.id)) {
    guard.add(t.id)
    d++
    t = index.topicById.get(t.parent)
  }
  return d
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
  const tags = new Set(index.model.pages.flatMap((p) => p.tags))
  const nextTags = new Set([...f.tags].filter((t) => tags.has(t)))
  if (nextTypes.size === f.types.size && nextTopics.size === f.topics.size && nextTags.size === f.tags.size && focus === f.focus) return f
  return { ...f, types: nextTypes, topics: nextTopics, tags: nextTags, focus }
}

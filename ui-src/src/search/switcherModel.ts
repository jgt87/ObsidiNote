// The quick switcher's list: rows, suggestions for an empty box, keyboard moves. Pure
// (tests: switcherModel.test.ts).

import { primaryTopic, UNFILED_ID } from '../graph/model'
import type { GraphIndex } from '../graph/graphIndex'
import { plural } from '../graph/format'
import { findAll, topicQuery, type FindItem } from './query'

/** A pick from the quick switcher, for the knowledge graph: open a page's dialog, or set the
 *  search. `sourceId` is the model's source id, so a graph showing another source ignores it.
 *  Set by the switcher, cleared by the graph once applied (onRequestDone). */
export interface FindRequest {
  sourceId: string
  pageId?: string
  query?: string
}

export interface SwitcherRow {
  item: FindItem
  /** DOM id part, unique in the list. */
  key: string
  label: string
  /** Muted context: where the page sits, or how many pages a topic holds. */
  context: string
  /** "Topic", "Hub", "Archived" or ''. */
  tag: string
}

export const SWITCHER_LIMIT = 50
const SUGGESTIONS = 12

export function rowFor(index: GraphIndex, item: FindItem): SwitcherRow | null {
  if (item.kind === 'topic') {
    const t = index.topicById.get(item.id)
    if (!t) return null
    const parent = t.path.split(' / ').slice(0, -1).join(' / ')
    const count = index.pagesByArea.get(t.id)?.length ?? t.pageCount
    return { item, key: `t-${t.id}`, label: t.name, context: [parent, plural(Math.max(count, t.pageCount), 'page')].filter(Boolean).join(' · '), tag: 'Topic' }
  }
  const p = index.pageById.get(item.id)
  if (!p) return null
  const area = primaryTopic(p)
  const where = area === UNFILED_ID ? 'Unfiled' : index.topicById.get(area)?.path ?? ''
  return {
    item,
    key: `p-${p.id}`,
    label: p.title,
    context: [where, p.bucket || p.kind].filter(Boolean).join(' · '),
    tag: p.archived ? 'Archived' : p.isHub ? 'Hub' : '',
  }
}

/** An empty box: the root topics, then the hub pages (at most 12), as a place to start. */
export function suggestions(index: GraphIndex): FindItem[] {
  const roots: FindItem[] = index.model.topics.filter((t) => t.parent === null).map((t) => ({ kind: 'topic', id: t.id }))
  const hubs: FindItem[] = index.model.pages.filter((p) => p.isHub && !p.archived).map((p) => ({ kind: 'page', id: p.id }))
  return [...roots, ...hubs].slice(0, SUGGESTIONS)
}

export interface SwitcherList {
  rows: SwitcherRow[]
  /** Matches beyond the rows shown. */
  hidden: number
  /** True when the rows are suggestions for an empty box. */
  suggested: boolean
}

export function switcherList(index: GraphIndex, text: string): SwitcherList {
  if (!text.trim()) return { rows: suggestions(index).map((i) => rowFor(index, i)).filter((r): r is SwitcherRow => r !== null), hidden: 0, suggested: true }
  const { items, total } = findAll(index, text, SWITCHER_LIMIT)
  const rows = items.map((i) => rowFor(index, i)).filter((r): r is SwitcherRow => r !== null)
  return { rows, hidden: Math.max(0, total - items.length), suggested: false }
}

/** Arrow keys: next or previous row, wrapping; -1 when there are none. */
export function moveActive(current: number, delta: 1 | -1, count: number): number {
  if (count <= 0) return -1
  if (current < 0) return delta > 0 ? 0 : count - 1
  return (current + delta + count) % count
}

/** What Enter on a row asks the knowledge graph to do. */
export function requestFor(index: GraphIndex, item: FindItem): FindRequest | null {
  const sourceId = index.model.source.id
  if (item.kind === 'page') return index.pageById.has(item.id) ? { sourceId, pageId: item.id } : null
  const t = index.topicById.get(item.id)
  return t ? { sourceId, query: topicQuery(t.path) } : null
}

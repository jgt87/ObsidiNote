// The List view's table: rows from the graph index (filtered by the search/filter matches),
// grouped and sorted. Pure (tests: tableModel.test.ts).
//
// Default order (no column sort): grouped by topic area in the map's area order, hubs first,
// then most links, then title. A column sort orders the rows inside each group; the groups keep
// their own order. Every sort is stable and ends on the page id, so the same data always gives
// the same table. Empty values (no site, no date, no topic) sort last in both directions.

import type { GraphIndex } from '../graphIndex'
import { UNFILED_ID, type GraphPage } from '../model'

export type SortKey = 'title' | 'type' | 'topics' | 'site' | 'links' | 'modified'
export type SortDir = 'asc' | 'desc'
export interface TableSort {
  key: SortKey
  dir: SortDir
}
export type GroupBy = 'topic' | 'type' | 'site' | 'year' | 'none'

export const GROUP_BY_OPTIONS: { value: GroupBy; label: string }[] = [
  { value: 'topic', label: 'Topic' },
  { value: 'type', label: 'Type' },
  { value: 'site', label: 'Site' },
  { value: 'year', label: 'Year' },
  { value: 'none', label: 'None' },
]

/** Rows shown before a group folds or asks "Show N more" (the table stays fast at 5,000 pages). */
export const ROW_BUDGET = 500

/** The area order of the map (layout.areas): id, and the topic for topic areas. */
export interface AreaRef {
  id: string
  name: string
  topic: { id: string; path: string } | null
}

export interface TableRow {
  id: string
  page: GraphPage
  title: string
  /** Copilot's type, else the bucket. */
  type: string
  /** Topic display names, primary first. */
  topicNames: string[]
  /** Full topic paths, primary first (for the cell's title). */
  topicPaths: string[]
  /** Area id of the primary topic (UNFILED_ID without a topic). */
  areaId: string
  site: string
  links: number
  modified: string
  /** Milliseconds since 1970; NaN when the date is unreadable. */
  time: number
}

export interface TableGroup {
  key: string
  name: string
  /** The topic id when the group is a topic area (for "Export as Markdown"). */
  topicId: string | null
  rows: TableRow[]
}

const collator = new Intl.Collator(undefined, { sensitivity: 'base', numeric: true })

export function compareText(a: string, b: string): number {
  return collator.compare(a, b)
}

/** One row per page in `matches` (all pages when null), in the model's order. */
export function buildRows(index: GraphIndex, matches: readonly string[] | null): TableRow[] {
  const keep = matches ? new Set(matches) : null
  const rows: TableRow[] = []
  for (const page of index.model.pages) {
    if (keep && !keep.has(page.id)) continue
    const topics = page.topicIds.map((id) => index.topicById.get(id)).filter((t) => t !== undefined)
    rows.push({
      id: page.id,
      page,
      title: page.title,
      type: page.kind || page.bucket,
      topicNames: topics.map((t) => t.name),
      topicPaths: topics.map((t) => t.path),
      areaId: page.topicIds[0] ?? UNFILED_ID,
      site: page.site,
      links: page.links,
      modified: page.modified,
      time: page.modified ? Date.parse(page.modified) : NaN,
    })
  }
  return rows
}

const byId = (a: TableRow, b: TableRow) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0)

/** Hubs first, then most links, then title, then id: the order without a column sort. */
export function defaultCompare(a: TableRow, b: TableRow): number {
  return Number(b.page.isHub) - Number(a.page.isHub) || b.links - a.links || compareText(a.title, b.title) || byId(a, b)
}

/** Empty values last in both directions; returns null when neither is empty. */
function emptyLast(aEmpty: boolean, bEmpty: boolean): number | null {
  if (aEmpty === bEmpty) return aEmpty ? 0 : null
  return aEmpty ? 1 : -1
}

export function rowCompare(sort: TableSort | null): (a: TableRow, b: TableRow) => number {
  if (!sort) return defaultCompare
  const sign = sort.dir === 'asc' ? 1 : -1
  const tie = (a: TableRow, b: TableRow) => compareText(a.title, b.title) || byId(a, b)
  switch (sort.key) {
    case 'title':
      return (a, b) => sign * compareText(a.title, b.title) || byId(a, b)
    case 'type':
      return (a, b) => emptyLast(!a.type, !b.type) || sign * compareText(a.type, b.type) || tie(a, b)
    case 'topics':
      return (a, b) => emptyLast(!a.topicPaths.length, !b.topicPaths.length) || sign * compareText(a.topicPaths[0] ?? '', b.topicPaths[0] ?? '') || tie(a, b)
    case 'site':
      return (a, b) => emptyLast(!a.site, !b.site) || sign * compareText(a.site, b.site) || tie(a, b)
    case 'links':
      return (a, b) => sign * (a.links - b.links) || tie(a, b)
    case 'modified':
      return (a, b) => emptyLast(Number.isNaN(a.time), Number.isNaN(b.time)) || sign * (a.time - b.time) || tie(a, b)
  }
}

/** Sorted copy (Array.prototype.sort is stable; ties end on the id anyway). */
export function sortRows(rows: readonly TableRow[], sort: TableSort | null): TableRow[] {
  return [...rows].sort(rowCompare(sort))
}

/** The year of a row's change date, '' when unreadable. */
export function rowYear(row: TableRow): string {
  return Number.isNaN(row.time) ? '' : String(new Date(row.time).getFullYear())
}

/** Rows into groups. Topic: the map's area order (unknown areas last). Type and site: by name,
 *  empty last. Year: newest first, no date last. None: one group. Empty groups are left out. */
export function groupRows(rows: readonly TableRow[], groupBy: GroupBy, areas: readonly AreaRef[]): TableGroup[] {
  if (groupBy === 'none') return rows.length ? [{ key: 'all', name: 'All pages', topicId: null, rows: [...rows] }] : []
  const groups = new Map<string, TableGroup>()
  const keyOf = (r: TableRow): string => {
    if (groupBy === 'topic') return r.areaId
    if (groupBy === 'type') return r.type.toLowerCase()
    if (groupBy === 'site') return r.site.toLowerCase()
    return rowYear(r)
  }
  const area = new Map(areas.map((a, i) => [a.id, { a, i }]))
  for (const r of rows) {
    const key = keyOf(r)
    let g = groups.get(key)
    if (!g) {
      let name: string
      let topicId: string | null = null
      if (groupBy === 'topic') {
        const a = area.get(key)?.a
        name = a ? (a.topic?.path ?? a.name) : key === UNFILED_ID ? 'Unfiled' : (r.topicPaths[0] ?? key)
        topicId = a?.topic?.id ?? null
      } else if (groupBy === 'type') name = r.type || 'No type'
      else if (groupBy === 'site') name = r.site || 'No site'
      else name = key || 'No date'
      g = { key, name, topicId, rows: [] }
      groups.set(key, g)
    }
    g.rows.push(r)
  }
  const list = [...groups.values()]
  if (groupBy === 'topic') {
    const pos = (g: TableGroup) => area.get(g.key)?.i ?? Number.MAX_SAFE_INTEGER
    list.sort((a, b) => pos(a) - pos(b) || compareText(a.name, b.name))
  } else if (groupBy === 'year') {
    list.sort((a, b) => emptyLast(!a.key, !b.key) || (a.key < b.key ? 1 : a.key > b.key ? -1 : 0))
  } else {
    list.sort((a, b) => emptyLast(!a.key, !b.key) || compareText(a.name, b.name) || (a.key < b.key ? -1 : 1))
  }
  return list
}

/** Groups with their rows sorted: the whole table in one call. */
export function buildTable(
  index: GraphIndex,
  areas: readonly AreaRef[],
  matches: readonly string[] | null,
  groupBy: GroupBy,
  sort: TableSort | null,
): { groups: TableGroup[]; total: number } {
  const rows = buildRows(index, matches)
  const groups = groupRows(rows, groupBy, areas)
  const cmp = rowCompare(sort)
  for (const g of groups) g.rows.sort(cmp)
  return { groups, total: rows.length }
}

/** Groups open by default: in order, while fewer than `budget` rows are already open. The first
 *  group is always open. Returns the open group keys. */
export function defaultOpenGroups(groups: readonly TableGroup[], budget = ROW_BUDGET): Set<string> {
  const open = new Set<string>()
  let shown = 0
  for (const g of groups) {
    if (open.size > 0 && shown >= budget) break
    open.add(g.key)
    shown += g.rows.length
  }
  return open
}

/** Next sort when a column header is clicked: first click sorts (text A-Z; links and dates
 *  highest/newest first), the second reverses, the third goes back to the default order. */
export function nextSort(current: TableSort | null, key: SortKey): TableSort | null {
  const first: SortDir = key === 'links' || key === 'modified' ? 'desc' : 'asc'
  if (!current || current.key !== key) return { key, dir: first }
  if (current.dir === first) return { key, dir: first === 'asc' ? 'desc' : 'asc' }
  return null
}

/** The aria-sort value of a column header. */
export function ariaSort(sort: TableSort | null, key: SortKey): 'ascending' | 'descending' | undefined {
  if (!sort || sort.key !== key) return undefined
  return sort.dir === 'asc' ? 'ascending' : 'descending'
}

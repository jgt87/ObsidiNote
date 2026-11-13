import { describe, expect, it } from 'vitest'
import { buildIndex } from '../graphIndex'
import { layoutGraph } from '../layout'
import { normalizeGraph, UNFILED_ID } from '../model'
import { syntheticGraph } from '../synthetic'
import {
  ariaSort,
  buildRows,
  buildTable,
  defaultOpenGroups,
  groupRows,
  nextSort,
  ROW_BUDGET,
  rowYear,
  sortRows,
  type AreaRef,
} from './tableModel'

// Invented example data only.
const model = normalizeGraph({
  source: { kind: 'vault', id: 'v1', name: 'Test vault' },
  topics: [
    { id: 't1', name: 'Security', path: 'Security' },
    { id: 't2', name: 'Networking', path: 'Security / Networking', parent: 't1' },
    { id: 't3', name: 'Reading', path: 'Reading' },
  ],
  pages: [
    { id: 'p1', title: 'zebra notes', topicIds: ['t1', 't3'], kind: 'note', bucket: 'Notes', links: 2, modified: '2026-03-01T10:00:00Z' },
    { id: 'p2', title: 'Alpha hub', topicIds: ['t1'], kind: 'concept', bucket: 'Notes', links: 1, isHub: true, modified: '2025-05-01T10:00:00Z' },
    { id: 'p3', title: 'Proxy placement', topicIds: ['t2'], kind: 'link-web', bucket: 'Web links', links: 5, site: 'www.example.org', modified: '2026-01-01T10:00:00Z' },
    { id: 'p4', title: 'Beta', topicIds: ['t3'], kind: '', bucket: 'Sources', links: 0, unlinked: true, modified: '' },
    { id: 'p5', title: 'Item 10', topicIds: [], kind: 'note', bucket: 'Notes', links: 2, modified: '2026-02-01T10:00:00Z' },
    { id: 'p6', title: 'item 9', topicIds: [], kind: 'note', bucket: 'Notes', links: 2, site: 'docs.example.net', archived: true, modified: '2026-02-01T10:00:00Z' },
  ],
  edges: [],
})
const index = buildIndex(model)
const areas: AreaRef[] = [
  { id: 't3', name: 'Reading', topic: { id: 't3', path: 'Reading' } },
  { id: 't1', name: 'Security', topic: { id: 't1', path: 'Security' } },
  { id: 't2', name: 'Networking', topic: { id: 't2', path: 'Security / Networking' } },
  { id: UNFILED_ID, name: 'Unfiled', topic: null },
]
const ids = (rows: { id: string }[]) => rows.map((r) => r.id)

describe('buildRows', () => {
  it('keeps only the matches, in model order, all pages for null', () => {
    expect(ids(buildRows(index, null))).toEqual(['p1', 'p2', 'p3', 'p4', 'p5', 'p6'])
    expect(ids(buildRows(index, ['p3', 'p1', 'nope']))).toEqual(['p1', 'p3'])
    expect(buildRows(index, [])).toEqual([])
  })
  it('fills type, topics (primary first), site and the date', () => {
    const [p1, , p3, p4] = buildRows(index, null)
    expect(p1.topicNames).toEqual(['Security', 'Reading'])
    expect(p1.topicPaths).toEqual(['Security', 'Reading'])
    expect(p3.type).toBe('link-web')
    expect(p3.site).toBe('www.example.org')
    expect(p4.type).toBe('Sources') // no kind: the bucket
    expect(Number.isNaN(p4.time)).toBe(true)
    expect(rowYear(p4)).toBe('')
    expect(rowYear(p1)).toBe('2026')
  })
})

describe('sorting', () => {
  const rows = buildRows(index, null)
  it('default: hubs first, then links, then title', () => {
    // "item 9" before "Item 10": numeric, case-insensitive titles
    expect(ids(sortRows(rows, null))).toEqual(['p2', 'p3', 'p6', 'p5', 'p1', 'p4'])
  })
  it('title is locale-aware and numeric, case-insensitive', () => {
    expect(ids(sortRows(rows, { key: 'title', dir: 'asc' }))).toEqual(['p2', 'p4', 'p6', 'p5', 'p3', 'p1'])
    expect(ids(sortRows(rows, { key: 'title', dir: 'desc' }))).toEqual(['p1', 'p3', 'p5', 'p6', 'p4', 'p2'])
  })
  it('links: ties by title then id', () => {
    expect(ids(sortRows(rows, { key: 'links', dir: 'desc' }))).toEqual(['p3', 'p6', 'p5', 'p1', 'p2', 'p4'])
    expect(ids(sortRows(rows, { key: 'links', dir: 'asc' }))).toEqual(['p4', 'p2', 'p6', 'p5', 'p1', 'p3'])
  })
  it('empty site and date sort last in both directions', () => {
    const asc = ids(sortRows(rows, { key: 'site', dir: 'asc' }))
    const desc = ids(sortRows(rows, { key: 'site', dir: 'desc' }))
    expect(asc.slice(0, 2)).toEqual(['p6', 'p3'])
    expect(desc.slice(0, 2)).toEqual(['p3', 'p6'])
    expect(ids(sortRows(rows, { key: 'modified', dir: 'asc' })).at(-1)).toBe('p4')
    expect(ids(sortRows(rows, { key: 'modified', dir: 'desc' }))).toEqual(['p1', 'p6', 'p5', 'p3', 'p2', 'p4'])
  })
  it('topics sort by the primary path, no topic last', () => {
    expect(ids(sortRows(rows, { key: 'topics', dir: 'asc' }))).toEqual(['p4', 'p2', 'p1', 'p3', 'p6', 'p5'])
  })
  it('type sorts by name', () => {
    expect(ids(sortRows(rows, { key: 'type', dir: 'asc' }))).toEqual(['p2', 'p3', 'p6', 'p5', 'p1', 'p4'])
  })
  it('is stable: the input order never changes the result', () => {
    const reversed = [...rows].reverse()
    for (const key of ['title', 'type', 'topics', 'site', 'links', 'modified'] as const) {
      expect(ids(sortRows(reversed, { key, dir: 'asc' }))).toEqual(ids(sortRows(rows, { key, dir: 'asc' })))
    }
    expect(ids(sortRows(reversed, null))).toEqual(ids(sortRows(rows, null)))
  })
})

describe('grouping', () => {
  const rows = buildRows(index, null)
  it('topic: the map area order, the path as name, the topic id for export', () => {
    const groups = groupRows(rows, 'topic', areas)
    expect(groups.map((g) => g.key)).toEqual(['t3', 't1', 't2', UNFILED_ID])
    expect(groups.map((g) => g.name)).toEqual(['Reading', 'Security', 'Security / Networking', 'Unfiled'])
    expect(groups.map((g) => g.topicId)).toEqual(['t3', 't1', 't2', null])
    expect(groups.map((g) => g.rows.length)).toEqual([1, 2, 1, 2])
  })
  it('type and site: by name, empty last', () => {
    expect(groupRows(rows, 'type', areas).map((g) => g.name)).toEqual(['concept', 'link-web', 'note', 'Sources'])
    expect(groupRows(rows, 'site', areas).map((g) => g.name)).toEqual(['docs.example.net', 'www.example.org', 'No site'])
  })
  it('year: newest first, no date last', () => {
    const groups = groupRows(rows, 'year', areas)
    expect(groups.map((g) => g.name)).toEqual(['2026', '2025', 'No date'])
    expect(groups.map((g) => g.rows.length)).toEqual([4, 1, 1])
  })
  it('none: one group; no rows, no groups', () => {
    expect(groupRows(rows, 'none', areas).map((g) => g.rows.length)).toEqual([6])
    expect(groupRows([], 'none', areas)).toEqual([])
    expect(groupRows([], 'topic', areas)).toEqual([])
  })
  it('buildTable sorts inside the groups and counts the rows', () => {
    const t = buildTable(index, areas, ['p1', 'p2', 'p4'], 'topic', null)
    expect(t.total).toBe(3)
    expect(t.groups.map((g) => [g.key, ids(g.rows)])).toEqual([
      ['t3', ['p4']],
      ['t1', ['p2', 'p1']],
    ])
    const byTitle = buildTable(index, areas, null, 'none', { key: 'title', dir: 'asc' })
    expect(ids(byTitle.groups[0].rows)).toEqual(['p2', 'p4', 'p6', 'p5', 'p3', 'p1'])
  })
})

describe('header and folding helpers', () => {
  it('nextSort: first, reversed, then back to the default', () => {
    expect(nextSort(null, 'title')).toEqual({ key: 'title', dir: 'asc' })
    expect(nextSort({ key: 'title', dir: 'asc' }, 'title')).toEqual({ key: 'title', dir: 'desc' })
    expect(nextSort({ key: 'title', dir: 'desc' }, 'title')).toBeNull()
    expect(nextSort({ key: 'title', dir: 'desc' }, 'links')).toEqual({ key: 'links', dir: 'desc' })
    expect(nextSort({ key: 'modified', dir: 'desc' }, 'modified')).toEqual({ key: 'modified', dir: 'asc' })
    expect(nextSort({ key: 'modified', dir: 'asc' }, 'modified')).toBeNull()
  })
  it('ariaSort only on the sorted column', () => {
    expect(ariaSort(null, 'title')).toBeUndefined()
    expect(ariaSort({ key: 'links', dir: 'desc' }, 'links')).toBe('descending')
    expect(ariaSort({ key: 'links', dir: 'asc' }, 'title')).toBeUndefined()
  })
  it('defaultOpenGroups opens groups until the row budget is used, always the first', () => {
    const g = (key: string, n: number) => ({ key, name: key, topicId: null, rows: new Array(n) })
    expect([...defaultOpenGroups([g('a', 300), g('b', 150), g('c', 100), g('d', 5)], 500)]).toEqual(['a', 'b', 'c'])
    expect([...defaultOpenGroups([g('a', 5000), g('b', 1)], 500)]).toEqual(['a'])
    expect([...defaultOpenGroups([])]).toEqual([])
  })
  it('5,000 pages: the table builds fast and opens at most about one budget of rows', () => {
    const big = syntheticGraph({ pages: 5000, topics: 12, seed: 7 })
    const bigIndex = buildIndex(big)
    const layout = layoutGraph(big, {}, bigIndex)
    const t0 = performance.now()
    const t = buildTable(bigIndex, layout.areas, null, 'topic', { key: 'title', dir: 'asc' })
    const ms = performance.now() - t0
    expect(t.total).toBe(5000)
    expect(t.groups.reduce((n, g) => n + g.rows.length, 0)).toBe(5000)
    expect(ms).toBeLessThan(1000)
    const open = defaultOpenGroups(t.groups)
    const openRows = t.groups.filter((g) => open.has(g.key)).reduce((n, g) => n + g.rows.length, 0)
    const firstClosed = t.groups.findIndex((g) => !open.has(g.key))
    expect(firstClosed).toBeGreaterThan(0)
    expect(openRows - t.groups[firstClosed - 1].rows.length).toBeLessThan(ROW_BUDGET)
  })
})

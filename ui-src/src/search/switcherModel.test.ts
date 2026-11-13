import { describe, expect, it } from 'vitest'
import { buildIndex } from '../graph/graphIndex'
import { normalizeGraph } from '../graph/model'
import { syntheticGraph } from '../graph/synthetic'
import { parseQuery } from './query'
import { moveActive, requestFor, rowFor, SWITCHER_LIMIT, switcherList } from './switcherModel'

// Invented example data.
const index = buildIndex(
  normalizeGraph({
    source: { kind: 'vault', id: 'v1', name: 'Test vault' },
    topics: [
      { id: 't1', name: 'Security', path: 'Security', parent: null, pageCount: 2 },
      { id: 't2', name: 'Networking', path: 'Security / Networking', parent: 't1', pageCount: 1 },
    ],
    pages: [
      { id: 'p1', title: 'Zero-trust networking', topicIds: ['t2'], bucket: 'Notes', kind: 'concept', isHub: true },
      { id: 'p2', title: 'Old proxy notes', topicIds: ['t1'], bucket: 'Notes', kind: 'note', archived: true },
      { id: 'p3', title: 'Loose note', topicIds: [], bucket: 'Notes', kind: 'note' },
    ],
    edges: [],
  }),
)

describe('switcher rows', () => {
  it('describes topics and pages', () => {
    expect(rowFor(index, { kind: 'topic', id: 't2' })).toMatchObject({ label: 'Networking', context: 'Security · 1 page', tag: 'Topic' })
    expect(rowFor(index, { kind: 'page', id: 'p1' })).toMatchObject({ label: 'Zero-trust networking', context: 'Security / Networking · Notes', tag: 'Hub' })
    expect(rowFor(index, { kind: 'page', id: 'p2' })?.tag).toBe('Archived')
    expect(rowFor(index, { kind: 'page', id: 'p3' })?.context).toBe('Unfiled · Notes')
    expect(rowFor(index, { kind: 'page', id: 'nope' })).toBeNull()
  })

  it('suggests root topics and hubs for an empty box', () => {
    const l = switcherList(index, '  ')
    expect(l.suggested).toBe(true)
    expect(l.rows.map((r) => r.key)).toEqual(['t-t1', 'p-p1'])
  })

  it('caps the results and counts the rest', () => {
    const big = buildIndex(syntheticGraph({ pages: 400 }))
    const all = switcherList(big, 'type:note')
    const matches = big.model.pages.filter((p) => p.kind.toLowerCase().startsWith('note') || p.bucket.toLowerCase().startsWith('note')).length
    expect(all.rows.length).toBe(Math.min(SWITCHER_LIMIT, matches))
    expect(all.hidden).toBe(Math.max(0, matches - SWITCHER_LIMIT))
    expect(parseQuery('type:note').filters.length).toBe(1)
  })

  it('moves with wrap', () => {
    expect(moveActive(-1, 1, 3)).toBe(0)
    expect(moveActive(-1, -1, 3)).toBe(2)
    expect(moveActive(2, 1, 3)).toBe(0)
    expect(moveActive(0, -1, 3)).toBe(2)
    expect(moveActive(0, 1, 0)).toBe(-1)
  })

  it('asks the graph to open a page, or to search a topic', () => {
    expect(requestFor(index, { kind: 'page', id: 'p1' })).toEqual({ sourceId: 'v1', pageId: 'p1' })
    expect(requestFor(index, { kind: 'topic', id: 't2' })).toEqual({ sourceId: 'v1', query: 'topic:"Security / Networking"' })
    expect(requestFor(index, { kind: 'topic', id: 'x' })).toBeNull()
  })
})

import { describe, expect, it } from 'vitest'
import { archivedHidden, emptyFilter, filterOptions, focusNeighbourhood, isFilterActive, pruneFilter, topicDescendants, typeOf, visiblePageIds, type GraphFilter } from './filters'
import { buildIndex } from './graphIndex'
import { normalizeGraph, UNFILED_ID, type GraphPage } from './model'

// a - b - c - d (links), e alone, f archived, g mentions a (no link).
function sample() {
  return buildIndex(
    normalizeGraph({
      topics: [
        { id: 'sec', name: 'Security', path: 'Security', parent: null },
        { id: 'net', name: 'Networking', path: 'Security / Networking', parent: 'sec' },
        { id: 'ops', name: 'Ops', path: 'Ops', parent: null },
      ],
      pages: [
        { id: 'a', title: 'A', topicIds: ['sec'], bucket: 'Notes', kind: 'concept' },
        { id: 'b', title: 'B', topicIds: ['net'], bucket: 'Meetings', kind: 'meeting' },
        { id: 'c', title: 'C', topicIds: ['ops', 'net'], bucket: 'Notes 2', kind: 'concept' },
        { id: 'd', title: 'D', topicIds: ['ops'], bucket: 'Web links', kind: 'link-web' },
        { id: 'e', title: 'E', topicIds: [], bucket: 'Notes', kind: 'concept', unlinked: true },
        { id: 'f', title: 'F', topicIds: ['sec'], bucket: 'Archive / Notes', kind: 'concept', archived: true },
        { id: 'g', title: 'G', topicIds: ['ops'], bucket: '', kind: 'person' },
      ],
      edges: [
        { from: 'a', to: 'b', strength: 2 },
        { from: 'c', to: 'b', strength: 1 },
        { from: 'c', to: 'd', strength: 3 },
        { from: 'g', to: 'a', strength: 1, kind: 'mention' },
      ],
    }),
  )
}
const ids = (s: Set<string>) => [...s].sort()
const f = (patch: Partial<GraphFilter>): GraphFilter => ({ ...emptyFilter(), ...patch })

describe('typeOf', () => {
  const p = (bucket: string, kind = ''): GraphPage => ({ bucket, kind } as GraphPage)
  it('uses the bucket without archive prefix, rollover number or year', () => {
    expect(typeOf(p('Notes'))).toBe('Notes')
    expect(typeOf(p('Notes 2'))).toBe('Notes')
    expect(typeOf(p('Archive / Notes 2'))).toBe('Notes')
    expect(typeOf(p('Journal / 2026'))).toBe('Journal')
    expect(typeOf(p('00 Index'))).toBe('00 Index')
  })
  it('falls back to the kind, then Other', () => {
    expect(typeOf(p('', 'person'))).toBe('person')
    expect(typeOf(p(''))).toBe('Other')
  })
})

describe('visiblePageIds', () => {
  it('hides only archived pages by default', () => {
    const index = sample()
    expect(ids(visiblePageIds(index, emptyFilter()))).toEqual(['a', 'b', 'c', 'd', 'e', 'g'])
    expect(archivedHidden(index, emptyFilter())).toBe(1)
    expect(isFilterActive(emptyFilter())).toBe(false)
  })

  it('shows archived pages when asked', () => {
    const index = sample()
    expect(visiblePageIds(index, f({ showArchived: true })).has('f')).toBe(true)
    expect(archivedHidden(index, f({ showArchived: true }))).toBe(0)
  })

  it('filters by type', () => {
    expect(ids(visiblePageIds(sample(), f({ types: new Set(['Notes']) })))).toEqual(['a', 'c', 'e'])
    expect(ids(visiblePageIds(sample(), f({ types: new Set(['Meetings', 'person']) })))).toEqual(['b', 'g'])
  })

  it('a topic includes its subtopics and any of a page topics', () => {
    expect(ids(visiblePageIds(sample(), f({ topics: new Set(['sec']) })))).toEqual(['a', 'b', 'c'])
    expect(ids(visiblePageIds(sample(), f({ topics: new Set(['net']) })))).toEqual(['b', 'c'])
    expect(ids(visiblePageIds(sample(), f({ topics: new Set([UNFILED_ID]) })))).toEqual(['e'])
  })

  it('only pages without links (mentions do not count as links)', () => {
    expect(ids(visiblePageIds(sample(), f({ unlinkedOnly: true })))).toEqual(['e', 'g'])
  })

  it('combines filters with AND', () => {
    expect(ids(visiblePageIds(sample(), f({ types: new Set(['Notes']), topics: new Set(['ops']) })))).toEqual(['c'])
  })

  it('focus shows the page and its neighbours within depth (links only)', () => {
    const index = sample()
    expect(ids(visiblePageIds(index, f({ focus: { id: 'a', depth: 1 } })))).toEqual(['a', 'b'])
    expect(ids(visiblePageIds(index, f({ focus: { id: 'a', depth: 2 } })))).toEqual(['a', 'b', 'c'])
    expect(ids(focusNeighbourhood(index, 'b', 2))).toEqual(['a', 'b', 'c', 'd'])
    expect(focusNeighbourhood(index, 'nope', 1).size).toBe(0)
  })

  it('focus combines with the other filters but keeps the focused page', () => {
    const index = sample()
    expect(ids(visiblePageIds(index, f({ focus: { id: 'b', depth: 2 }, types: new Set(['Notes']) })))).toEqual(['a', 'b', 'c'])
    expect(ids(visiblePageIds(index, f({ focus: { id: 'f', depth: 1 } })))).toEqual(['f'])
  })
})

describe('filterOptions', () => {
  it('counts types and topics (subtopics included), archived left out unless shown', () => {
    const index = sample()
    const o = filterOptions(index, false)
    expect(o.types).toEqual([
      { key: 'Meetings', count: 1 },
      { key: 'Notes', count: 3 },
      { key: 'Web links', count: 1 },
      { key: 'person', count: 1 },
    ])
    expect(o.topics.map((t) => [t.id, t.depth, t.count])).toEqual([
      ['ops', 0, 3],
      ['sec', 0, 3],
      ['net', 1, 2],
      [UNFILED_ID, 0, 1],
    ])
    expect(filterOptions(index, true).types.find((t) => t.key === 'Notes')!.count).toBe(4)
  })
})

describe('topicDescendants and pruneFilter', () => {
  it('survives a cycle in the topic tree', () => {
    const index = buildIndex(normalizeGraph({ topics: [{ id: 'x', name: 'X', parent: 'y' }, { id: 'y', name: 'Y', parent: 'x' }] }))
    expect(ids(topicDescendants(index).get('x')!)).toEqual(['x', 'y'])
  })

  it('drops choices that no longer exist and keeps the same object when nothing changed', () => {
    const index = sample()
    const keep = f({ types: new Set(['Notes']), topics: new Set(['sec', UNFILED_ID]), focus: { id: 'a', depth: 1 } })
    expect(pruneFilter(index, keep)).toBe(keep)
    const gone = pruneFilter(index, f({ types: new Set(['Gone']), topics: new Set(['nope']), focus: { id: 'zz', depth: 2 } }))
    expect(gone.types.size).toBe(0)
    expect(gone.topics.size).toBe(0)
    expect(gone.focus).toBeNull()
  })
})

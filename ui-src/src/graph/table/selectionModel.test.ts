import { describe, expect, it } from 'vitest'
import { normalizeGraph, type GraphPage } from '../model'
import { keepVisible, retireLabel, selectionParts } from './selectionModel'

// Invented example data only.
const model = normalizeGraph({
  source: { kind: 'vault', readOnly: false },
  topics: [{ id: 't1', name: 'Methods' }],
  pages: [
    { id: 'p1', title: 'Note one', kind: 'note', topicIds: ['t1'], tags: ['beta', 'alpha'] },
    { id: 'p2', title: 'Old note', kind: 'note', topicIds: ['t1'], archived: true, tags: ['alpha'] },
    { id: 'p3', title: 'A site', kind: 'link-web', url: 'https://site.example/a', topicIds: ['t1'] },
    { id: 'p4', title: 'Old link', kind: 'link-internal', topicIds: ['t1'], archived: true, tags: ['gamma'] },
  ],
})
const byId = new Map<string, GraphPage>(model.pages.map((p) => [p.id, p]))

describe('selectionParts: what the selection bar acts on', () => {
  it('splits the ticked pages into live, archived and link pages, in tick order', () => {
    const s = selectionParts(['p4', 'p1', 'p3', 'p2'], byId)
    expect(s.live).toEqual(['p1', 'p3'])
    expect(s.archived).toEqual(['p4', 'p2'])
    expect(s.links).toEqual(['p4', 'p3'])
  })
  it('gathers every tag of the ticked pages once, sorted', () => {
    expect(selectionParts(['p4', 'p1', 'p2'], byId).tags).toEqual(['alpha', 'beta', 'gamma'])
  })
  it('leaves out ids that are no page', () => {
    expect(selectionParts(['gone', 'p1'], byId)).toEqual({ tags: ['alpha', 'beta'], live: ['p1'], archived: [], links: [] })
    expect(selectionParts([], byId)).toEqual({ tags: [], live: [], archived: [], links: [] })
  })
})

describe('retireLabel: Archive and Restore say their count only beside the other', () => {
  it('names the count when both kinds are ticked', () => {
    expect(retireLabel('Archive', 2, 1)).toBe('Archive (2)')
    expect(retireLabel('Restore', 1, 2)).toBe('Restore (1)')
  })
  it('the plain word when only one kind is ticked', () => {
    expect(retireLabel('Archive', 3, 0)).toBe('Archive')
  })
})

describe('keepVisible: a hidden or vanished page is unticked', () => {
  const exists = (id: string) => byId.has(id)
  it('drops pages the search hides and pages that left the model', () => {
    expect([...keepVisible(new Set(['p1', 'p2', 'gone']), exists, ['p2', 'p3'])]).toEqual(['p2'])
    expect([...keepVisible(new Set(['p1', 'gone']), exists, null)]).toEqual(['p1'])
  })
  it('gives back the same set when nothing changes, so React does not render again', () => {
    const s = new Set(['p1', 'p3'])
    expect(keepVisible(s, exists, null)).toBe(s)
    expect(keepVisible(s, exists, ['p1', 'p3', 'p4'])).toBe(s)
  })
})
